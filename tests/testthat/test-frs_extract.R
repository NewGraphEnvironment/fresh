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

test_that("frs_extract adds WHERE clause from where parameter", {
  sql_log <- character(0)
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) {
    sql_log <<- c(sql_log, sql)
    0L
  })

  frs_extract("mock", "whse_basemapping.fwa_stream_networks_sp",
              "working.bulk_streams",
              where = "watershed_group_code = 'BULK'")

  expect_match(sql_log[1], "WHERE watershed_group_code = 'BULK'")
  expect_no_match(sql_log[1], "ST_Intersects")
})

test_that("frs_extract ANDs aoi and where together", {
  sql_log <- character(0)
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) {
    sql_log <<- c(sql_log, sql)
    0L
  })

  frs_extract("mock", "whse_basemapping.fwa_stream_networks_sp",
              "working.bulk_streams",
              aoi = "BULK",
              where = "edge_type NOT IN (1425)")

  expect_match(sql_log[1], "WHERE.*AND")
  expect_match(sql_log[1], "watershed_group_code.*BULK")
  expect_match(sql_log[1], "edge_type NOT IN \\(1425\\)")
})

test_that("frs_extract validates where parameter", {
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) 0L)

  expect_error(frs_extract("mock", "schema.tbl", "working.test",
                           where = 123), "is.character")
  expect_error(frs_extract("mock", "schema.tbl", "working.test",
                           where = ""), "nzchar")
  expect_error(frs_extract("mock", "schema.tbl", "working.test",
                           where = c("a = 1", "b = 2")), "length")
})

test_that("frs_extract returns conn invisibly", {
  mockery::stub(frs_extract, ".frs_db_execute", function(conn, sql) 0L)

  result <- frs_extract("mock_conn", "bcfishpass.streams", "working.test")
  expect_equal(result, "mock_conn")
})


# --- Integration tests (live DB, Byman-Ailport AOI) ---

# Load the bundled AOI once for all integration tests
.test_aoi <- function() {
  readRDS(system.file("extdata", "test_streamline.rds", package = "fresh"))
}

test_that("frs_extract creates table in working schema", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_extract")
    DBI::dbDisconnect(conn)
  })

  result <- frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_extract",
    cols = c("linear_feature_id", "blue_line_key", "gradient", "geom"),
    aoi = .test_aoi()
  )

  expect_true(inherits(result, "PqConnection"))

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

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_extract",
    cols = c("linear_feature_id", "geom"),
    aoi = .test_aoi()
  )

  expect_error(
    frs_extract(conn,
      from = "whse_basemapping.fwa_stream_networks_sp",
      to = "working.test_extract",
      cols = c("linear_feature_id", "geom"),
      aoi = .test_aoi()
    )
  )
})

test_that("frs_extract filters by where predicate", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_extract_where")
    DBI::dbDisconnect(conn)
  })

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_extract_where",
    cols = c("linear_feature_id", "watershed_group_code", "geom"),
    where = "watershed_group_code = 'BULK' AND stream_order >= 5"
  )

  result <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n, count(DISTINCT watershed_group_code) AS n_wsg
     FROM working.test_extract_where")
  expect_true(result$n > 0)
  expect_equal(result$n_wsg, 1L)
})

test_that("frs_extract combines aoi and where", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_extract_both")
    DBI::dbDisconnect(conn)
  })

  aoi <- .test_aoi()

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_extract_both",
    cols = c("linear_feature_id", "stream_order", "geom"),
    aoi = aoi,
    where = "stream_order >= 2"
  )

  # Fewer rows than unfiltered extract (aoi alone)
  n_filtered <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_extract_both")$n

  .frs_test_drop(conn, "working.test_extract_unfiltered")
  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_extract_unfiltered",
    cols = c("linear_feature_id", "stream_order", "geom"),
    aoi = aoi
  )
  n_all <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_extract_unfiltered")$n
  .frs_test_drop(conn, "working.test_extract_unfiltered")

  expect_true(n_filtered > 0)
  expect_true(n_filtered < n_all)
})

test_that("frs_extract overwrites when overwrite = TRUE", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_extract")
    DBI::dbDisconnect(conn)
  })

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_extract",
    cols = c("linear_feature_id", "geom"),
    aoi = .test_aoi()
  )

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_extract",
    cols = c("linear_feature_id", "blue_line_key", "geom"),
    aoi = .test_aoi(),
    overwrite = TRUE
  )

  cols <- DBI::dbGetQuery(conn,
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'working' AND table_name = 'test_extract'
     ORDER BY ordinal_position")
  expect_true("blue_line_key" %in% cols$column_name)
})
