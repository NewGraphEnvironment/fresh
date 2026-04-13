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

# -- .frs_index_working ---------------------------------------------------------

test_that(".frs_index_working is idempotent — no error on double call", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  tbl <- "working.test_idx_idem"
  on.exit({
    .frs_test_drop(conn, tbl)
    DBI::dbDisconnect(conn)
  })

  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
  .frs_db_execute(conn, sprintf(
    "CREATE TABLE %s (
       id_segment integer,
       blue_line_key integer,
       downstream_route_measure double precision,
       wscode_ltree ltree,
       localcode_ltree ltree,
       label text
     )", tbl))

  # First call creates indexes
  expect_no_error(fresh:::.frs_index_working(conn, tbl))

  # Second call is a no-op — IF NOT EXISTS prevents error

  expect_no_error(fresh:::.frs_index_working(conn, tbl))

  # Verify indexes exist
  idx_count <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) AS n FROM pg_indexes WHERE tablename = 'test_idx_idem'"))
  expect_true(idx_count$n >= 6)
})

test_that(".frs_index_working skips non-DB connections", {
  mock_conn <- structure(list(), class = "mock_connection")
  expect_no_error(fresh:::.frs_index_working(mock_conn, "schema.table"))
})

# -- env var check -------------------------------------------------------------

test_that("frs_db_conn stops on missing env vars", {
  expect_error(frs_db_conn(dbname = ""), "PG_DB_SHARE")
  expect_error(frs_db_conn(dbname = "x", host = ""), "PG_HOST_SHARE")
  expect_error(frs_db_conn(dbname = "x", host = "x", port = ""), "PG_PORT_SHARE")
  expect_error(frs_db_conn(dbname = "x", host = "x", port = "5432", user = ""), "PG_USER_SHARE")
})
