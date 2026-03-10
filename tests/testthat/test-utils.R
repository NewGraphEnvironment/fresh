# -- SQL quoting ---------------------------------------------------------------

test_that(".frs_quote_string escapes single quotes", {
  expect_equal(fresh:::.frs_quote_string("BULK"), "'BULK'")
  expect_equal(fresh:::.frs_quote_string("O'Brien"), "'O''Brien'")
  expect_equal(fresh:::.frs_quote_string("'; DROP TABLE --"), "'''; DROP TABLE --'")
})

# -- identifier validation ----------------------------------------------------

test_that(".frs_validate_identifier accepts valid names", {
  expect_silent(fresh:::.frs_validate_identifier("blue_line_key", "column"))
  expect_silent(fresh:::.frs_validate_identifier("whse_basemapping.fwa_stream_networks_sp", "table"))
  expect_silent(fresh:::.frs_validate_identifier("*", "column"))
})

test_that(".frs_validate_identifier rejects injection attempts", {
  expect_error(fresh:::.frs_validate_identifier("'; DROP TABLE --", "table"),
    "table contains invalid characters")
  expect_error(fresh:::.frs_validate_identifier("col; DELETE", "column"),
    "column contains invalid characters")
  expect_error(fresh:::.frs_validate_identifier("1bad", "column"),
    "column contains invalid characters")
})

# -- env var check -------------------------------------------------------------

test_that("frs_db_conn stops on missing env vars", {
  expect_error(frs_db_conn(dbname = ""), "PG_DB_SHARE")
  expect_error(frs_db_conn(dbname = "x", host = ""), "PG_HOST_SHARE")
  expect_error(frs_db_conn(dbname = "x", host = "x", port = ""), "PG_PORT_SHARE")
  expect_error(frs_db_conn(dbname = "x", host = "x", port = "5432", user = ""), "PG_USER_SHARE")
})
