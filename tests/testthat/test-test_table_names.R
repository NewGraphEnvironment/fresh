# The per-run table-name guard (#279). The scanner is checked against both
# answers on snippets first, one per shape it must catch and one per shape it
# must pass: a guard that only ever returns one value cannot be told from a
# broken one. Then it runs over every file it guards.

scan_snippet <- function(code, default_to = c(frs_break_find = 3L),
                         defs_from = character()) {
  f <- withr::local_tempfile(fileext = ".R")
  writeLines(code, f)
  .frs_test_fixed_names(f, default_to = default_to, defs_from = defs_from)
}

live <- function(...) c('test_that("live", {', "  conn <- frs_db_conn()", ..., "})")

test_that("a fixed working name in a live block is flagged", {
  hits <- scan_snippet(live('  frs_extract(conn, "a.b", "working.test_x")'))
  expect_identical(hits$kind, "working")
  expect_identical(hits$text, "working.test_x")
  expect_identical(hits$line, 3L)
})

test_that("each spelling of the working schema is flagged", {
  shapes <- c('paste0("working.", x)', 'sprintf("working.%s", x)',
              '"WORKING.streams"', '"\\"working\\".\\"x\\""',
              '"SET search_path TO working, public"',
              '"SET search_path TO working"',
              '"WHERE table_schema = \'working\'"',
              'DBI::Id(schema = "working", table = "x")')
  for (sh in shapes) {
    hits <- scan_snippet(live(paste0("  y <- ", sh)))
    expect(identical(hits$kind, "working"), paste("not flagged:", sh))
  }
})

test_that("a fixed index or constraint name in a live block is flagged", {
  code <- live(
    '  DBI::dbExecute(conn, sprintf("CREATE UNIQUE INDEX x_pkey ON %s (a)", t))',
    '  DBI::dbExecute(conn, "ALTER TABLE t ADD CONSTRAINT t_uq UNIQUE (a)")',
    '  DBI::dbExecute(conn, sprintf("CREATE INDEX %s_idx ON %s (a)", n, t))',
    '  DBI::dbExecute(conn, sprintf("CREATE INDEX ON %s (a)", t))'
  )
  hits <- scan_snippet(code)
  expect_identical(hits$kind, c("index", "index"))
  expect_identical(hits$line, c(3L, 4L))
})

test_that("a fixed working name in a mock block is not flagged", {
  code <- c(
    'test_that("mock", {',
    '  frs_extract("mock", "a.b", "working.test_x")',
    "})"
  )
  hits <- scan_snippet(code)
  expect_identical(nrow(hits), 0L)
})

test_that("a live block that names tables through the helpers is clean", {
  code <- c(
    'test_that("live", {',
    '  skip_if_not(.frs_db_available(), "DB not available")',
    '  tbl <- frs_test_tbl("test_x")',
    '  frs_habitat(conn, aoi = "x", label = frs_test_label("a"), to_streams = tbl)',
    '  frs_break_find(conn, tbl, to = frs_test_tbl("b"))',
    '  frs_break_find(conn, tbl, frs_test_tbl("b"))',
    "})"
  )
  hits <- scan_snippet(code)
  expect_identical(nrow(hits), 0L)
})

test_that("a frs_habitat() label not built by frs_test_label() is flagged", {
  code <- live(
    '  frs_habitat(conn, aoi = "x", species = "CO",',
    '    label = "brktest", verbose = FALSE)',
    '  frs_habitat(conn, aoi = "x", label = lab)'
  )
  hits <- scan_snippet(code)
  expect_identical(hits$kind, c("label", "label"))
  expect_identical(hits$text, c('"brktest"', "lab"))
})

test_that("frs_habitat() in watershed-group mode is flagged", {
  code <- live(
    '  frs_habitat(conn, "BULK", species = "CO")',
    '  frs_habitat(conn, wsg = "BULK", species = "CO")'
  )
  hits <- scan_snippet(code)
  expect_identical(hits$kind, c("wsg", "wsg"))
})

test_that("a call that leaves `to` at a working default is flagged", {
  hits <- scan_snippet(live('  frs_break_find(conn, frs_test_tbl("s"))'))
  expect_identical(hits$kind, "to")
})

test_that("a top-level helper is checked even without a connection", {
  code <- c(
    "run_it <- function(conn, label) {",
    '  frs_habitat(conn, aoi = "x", label = label,',
    '    to_streams = paste0("working.rt_", label))',
    "}"
  )
  hits <- scan_snippet(code)
  expect_setequal(hits$kind, c("label", "working"))
})

test_that("a block calling a file's own live connector is checked", {
  code <- c(
    "my_conn <- function() DBI::dbConnect(RPostgres::Postgres())",
    'test_that("uses my_conn", {',
    "  conn <- my_conn()",
    '  frs_extract(conn, "a.b", "working.test_x")',
    "})"
  )
  hits <- scan_snippet(code)
  expect_identical(hits$line, 4L)
})

test_that("a connector defined in helper-db.R makes a block live", {
  code <- c(
    'test_that("gate", {',
    "  conn <- local_fwapg_indexpoint()",
    '  DBI::dbExecute(conn, "CREATE TABLE working.test_gate_x (a int)")',
    "})"
  )
  expect_identical(nrow(scan_snippet(code)), 0L)
  hits <- scan_snippet(code, defs_from = .frs_test_guard_defs())
  expect_identical(hits$line, 3L)
})

test_that("a top-level helper that drives a mock connection is not flagged", {
  code <- c(
    "run_mock <- function(...) {",
    '  frs_channel_width("mock", "working.streams", ...)',
    "}"
  )
  hits <- scan_snippet(code)
  expect_identical(nrow(hits), 0L)
})

test_that("a top-level helper is not exempted by a comment quoting mock", {
  code <- c(
    "run_it <- function(conn) {",
    '  # unlike the "mock" tests above',
    '  frs_extract(conn, "a.b", "working.test_x")',
    "}"
  )
  hits <- scan_snippet(code)
  expect_identical(hits$line, 3L)
})

test_that("prose and the working schema's creation are not flagged", {
  code <- live(
    '  expect_true(TRUE, info = "the working table is gone")',
    '  x <- "networking.x"',
    '  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")'
  )
  hits <- scan_snippet(code)
  expect_identical(nrow(hits), 0L)
})

test_that("the default-to list is read from the package", {
  d <- .frs_test_default_to()
  expect_true(all(c("frs_break_find", "frs_feature_find",
                    "frs_barriers_minimal") %in% names(d)))
  expect_identical(unname(d[["frs_break_find"]]),
                   match("to", names(formals(frs_break_find))))
})

test_that("no test names a table two runs against one database would share", {
  files <- .frs_test_guard_files()
  expect_gt(length(files), 40L)
  hits <- .frs_test_fixed_names(files, defs_from = .frs_test_guard_defs())
  msg <- paste(sprintf("%s:%d %s %s", hits$file, hits$line, hits$kind,
                       hits$text), collapse = "\n")
  expect(nrow(hits) == 0L, paste0(
    nrow(hits), " name(s) shared between runs where a test reaches the ",
    "database; name tables with frs_test_tbl() and frs_habitat() labels with ",
    "frs_test_label():\n", msg
  ))
})
