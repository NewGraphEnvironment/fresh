# The per-run table-name guard (#279). The scanner is checked against both
# answers on snippets first: a guard that only ever returns one value cannot
# be told from a broken one. Then it runs over every test file.

scan_snippet <- function(code) {
  f <- withr::local_tempfile(fileext = ".R")
  writeLines(code, f)
  .frs_test_fixed_names(f)
}

test_that("a fixed working name in a live block is flagged", {
  hits <- scan_snippet(c(
    'test_that("live", {',
    '  conn <- frs_db_conn()',
    '  frs_extract(conn, "a.b", "working.test_x")',
    '})'))
  expect_identical(hits$kind, "working")
  expect_identical(hits$text, "working.test_x")
  expect_identical(hits$line, 3L)
})

test_that("a fixed working name in a mock block is not flagged", {
  hits <- scan_snippet(c(
    'test_that("mock", {',
    '  frs_extract("mock", "a.b", "working.test_x")',
    '})'))
  expect_identical(nrow(hits), 0L)
})

test_that("a live block that names tables through the helpers is clean", {
  hits <- scan_snippet(c(
    'test_that("live", {',
    '  skip_if_not(.frs_db_available(), "DB not available")',
    '  tbl <- frs_test_tbl("test_x")',
    '  frs_habitat(conn, aoi = "x", label = frs_test_label("a"), to_streams = tbl)',
    '})'))
  expect_identical(nrow(hits), 0L)
})

test_that("a literal frs_habitat() label in a live block is flagged", {
  hits <- scan_snippet(c(
    'test_that("live", {',
    '  conn <- frs_db_conn()',
    '  frs_habitat(conn, aoi = "x", species = "CO",',
    '    label = "brktest", verbose = FALSE)',
    '})'))
  expect_identical(hits$kind, "label")
  expect_identical(hits$text, "brktest")
  expect_identical(hits$line, 4L)
})

test_that("the schema spelled inside SQL or as an Id() argument is flagged", {
  hits <- scan_snippet(c(
    'test_that("live", {',
    '  conn <- frs_db_conn()',
    '  DBI::dbGetQuery(conn, "SELECT 1 FROM information_schema.tables',
    '    WHERE table_schema = \'working\' AND table_name = \'x\'")',
    '  DBI::dbExistsTable(conn, DBI::Id(schema = "working", table = "x"))',
    '})'))
  expect_identical(hits$kind, c("working", "working"))
  expect_identical(hits$line, c(3L, 5L))
})

test_that("a top-level helper is checked even without a connection", {
  hits <- scan_snippet(c(
    'run_it <- function(conn, label) {',
    '  frs_habitat(conn, aoi = "x", label = "fixed",',
    '    to_streams = paste0("working.rt_", label))',
    '}'))
  expect_setequal(hits$kind, c("label", "working"))
})

test_that("prose that mentions working is not flagged", {
  hits <- scan_snippet(c(
    'test_that("live", {',
    '  conn <- frs_db_conn()',
    '  expect_true(TRUE, info = "the working table is gone")',
    '  x <- "networking.x"',
    '})'))
  expect_identical(nrow(hits), 0L)
})

test_that("no live test names a fixed table in the working schema", {
  files <- list.files(test_path(), "^test-.*\\.R$", full.names = TRUE)
  hits <- do.call(rbind, lapply(files, .frs_test_fixed_names))
  expect_gt(length(files), 40L)
  msg <- paste(sprintf("%s:%d %s %s", hits$file, hits$line, hits$kind,
                       hits$text), collapse = "\n")
  expect(nrow(hits) == 0L, paste0(
    nrow(hits), " fixed name(s) where a test reaches the database; name ",
    "tables with frs_test_tbl() and frs_habitat() labels with ",
    "frs_test_label():\n", msg))
})
