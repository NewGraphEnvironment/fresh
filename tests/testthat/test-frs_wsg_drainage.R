# -- arg validation (no DB needed) -------------------------------------------

test_that("frs_wsg_drainage rejects non-character watershed_group_code", {
  expect_error(
    frs_wsg_drainage(NULL, watershed_group_code = 1:3),
    "is.character"
  )
})

test_that("frs_wsg_drainage rejects empty watershed_group_code", {
  expect_error(
    frs_wsg_drainage(NULL, watershed_group_code = character(0)),
    "length"
  )
})

test_that("frs_wsg_drainage rejects NA in watershed_group_code", {
  expect_error(
    frs_wsg_drainage(NULL, watershed_group_code = c("BULK", NA_character_)),
    "anyNA"
  )
})

test_that("frs_wsg_drainage rejects empty-string focal codes", {
  expect_error(
    frs_wsg_drainage(NULL, watershed_group_code = c("BULK", "")),
    "nzchar"
  )
})

test_that("frs_wsg_drainage rejects vector table arg", {
  expect_error(
    frs_wsg_drainage(NULL, "BULK", table = c("public.wsg_outlet", "x")),
    "length\\(table\\) == 1L"
  )
})

test_that("frs_wsg_drainage rejects invalid table identifier", {
  expect_error(
    frs_wsg_drainage(NULL, "BULK", table = "x; DROP TABLE y; --"),
    "table contains invalid characters"
  )
})

# -- live DB tests (gated on PG_DB_SHARE) ------------------------------------

test_that("frs_wsg_drainage returns the PARS+BULK 15-WSG closure DS-first", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  expected <- c(
    "KISP", "KLUM", "LKEL", "LSKE", "MSKE", "USKE",
    "BULK", "FINA", "LBTN", "LPCE", "MORR", "PARA", "PCEA", "UPCE",
    "PARS"
  )
  expect_identical(
    frs_wsg_drainage(conn, c("PARS", "BULK")),
    expected
  )
})

test_that("frs_wsg_drainage closure is invariant to focal input order", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  expect_identical(
    frs_wsg_drainage(conn, c("PARS", "BULK")),
    frs_wsg_drainage(conn, c("BULK", "PARS"))
  )
})

test_that("frs_wsg_drainage upper-cases focal codes internally", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  expect_identical(
    frs_wsg_drainage(conn, c("pars", "bulk")),
    frs_wsg_drainage(conn, c("PARS", "BULK"))
  )
})

test_that("frs_wsg_drainage warns on unmatched focal codes but returns valid ones", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  expect_warning(
    res <- frs_wsg_drainage(conn, c("BULK", "TYPO")),
    "TYPO"
  )
  expect_true(length(res) > 0L)
  expect_true("BULK" %in% res)
  expect_false("TYPO" %in% res)
})

test_that("frs_wsg_drainage errors when no focal codes match", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  expect_error(
    frs_wsg_drainage(conn, c("FAK1", "FAK2")),
    "No drainage closure found"
  )
})
