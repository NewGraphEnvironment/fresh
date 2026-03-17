# --- Unit tests (no DB) ---

test_that("frs_extract validates identifiers", {
  expect_error(frs_extract("mock", "DROP TABLE foo", "working.test", cols = NULL),
               "invalid characters")
  expect_error(frs_extract("mock", "bcfishpass.streams", "DROP; TABLE", cols = NULL),
               "invalid characters")
})

test_that("frs_extract validates cols", {
  expect_error(frs_extract("mock", "bcfishpass.streams", "working.test", cols = 123),
               "is.character")
  expect_error(frs_extract("mock", "bcfishpass.streams", "working.test",
                           cols = character(0)),
               "length")
})

test_that("frs_extract builds correct SQL for SELECT *", {
  sql_log <- character(0)
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) {
    sql_log <<- c(sql_log, sql)
    0L
  })

  frs_extract("mock", "bcfishpass.streams_co_vw", "working.streams_co")

  expect_length(sql_log, 1)
  expect_match(sql_log[1], "CREATE TABLE working.streams_co AS SELECT \\* FROM bcfishpass.streams_co_vw")
  expect_no_match(sql_log[1], "WHERE")
})

test_that("frs_extract builds correct SQL with cols", {
  sql_log <- character(0)
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) {
    sql_log <<- c(sql_log, sql)
    0L
  })

  frs_extract("mock", "bcfishpass.streams_co_vw", "working.streams_co",
              cols = c("blue_line_key", "gradient", "geom"))

  expect_match(sql_log[1], "SELECT blue_line_key, gradient, geom FROM")
})

test_that("frs_extract adds WHERE clause from character aoi", {
  sql_log <- character(0)
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) {
    sql_log <<- c(sql_log, sql)
    0L
  })

  frs_extract("mock", "bcfishpass.streams_co_vw", "working.streams_co",
              aoi = "BULK")

  expect_match(sql_log[1], "WHERE.*watershed_group_code.*BULK")
})

test_that("frs_extract drops table when overwrite = TRUE", {
  sql_log <- character(0)
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) {
    sql_log <<- c(sql_log, sql)
    0L
  })

  frs_extract("mock", "bcfishpass.streams_co_vw", "working.streams_co",
              overwrite = TRUE)

  expect_length(sql_log, 2)
  expect_match(sql_log[1], "DROP TABLE IF EXISTS working.streams_co")
  expect_match(sql_log[2], "CREATE TABLE")
})

test_that("frs_extract returns conn invisibly", {
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) 0L)

  result <- frs_extract("mock_conn", "bcfishpass.streams", "working.test")
  expect_equal(result, "mock_conn")
})


# --- Integration tests (live DB) ---

test_that("frs_extract creates table in working schema", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_extract")
    DBI::dbDisconnect(conn)
  })

  result <- frs_extract(conn,
    from = "bcfishpass.streams_vw",
    to = "working.test_extract",
    cols = c("segmented_stream_id", "blue_line_key", "gradient",
             "channel_width", "geom"),
    aoi = "ZYMO"
  )

  # Returns conn

  expect_true(inherits(result, "PqConnection"))

  # Table exists and has rows
  count <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_extract")
  expect_true(count$n > 0)
})

test_that("frs_extract errors when table exists and overwrite = FALSE", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_extract")
    DBI::dbDisconnect(conn)
  })

  # Create it first
  frs_extract(conn,
    from = "bcfishpass.streams_vw",
    to = "working.test_extract",
    cols = c("segmented_stream_id", "geom"),
    aoi = "ZYMO"
  )

  # Should error on second attempt
  expect_error(
    frs_extract(conn,
      from = "bcfishpass.streams_vw",
      to = "working.test_extract",
      cols = c("segmented_stream_id", "geom"),
      aoi = "ZYMO"
    )
  )
})

test_that("frs_extract overwrites when overwrite = TRUE", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_extract")
    DBI::dbDisconnect(conn)
  })

  # Create it
  frs_extract(conn,
    from = "bcfishpass.streams_vw",
    to = "working.test_extract",
    cols = c("segmented_stream_id", "geom"),
    aoi = "ZYMO"
  )

  # Overwrite should succeed
  frs_extract(conn,
    from = "bcfishpass.streams_vw",
    to = "working.test_extract",
    cols = c("segmented_stream_id", "blue_line_key", "geom"),
    aoi = "ZYMO",
    overwrite = TRUE
  )

  # Check new column exists
  cols <- DBI::dbGetQuery(conn,
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'working' AND table_name = 'test_extract'
     ORDER BY ordinal_position")
  expect_true("blue_line_key" %in% cols$column_name)
})
