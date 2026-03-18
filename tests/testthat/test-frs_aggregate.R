# --- Unit tests (no DB) ---

test_that("frs_aggregate validates identifiers", {
  expect_error(
    frs_aggregate("mock", "DROP foo", "working.streams",
                  metrics = c(n = "COUNT(*)")),
    "invalid characters"
  )
})

test_that("frs_aggregate validates direction", {
  expect_error(
    frs_aggregate("mock", "working.pts", "working.streams",
                  metrics = c(n = "COUNT(*)"), direction = "sideways"),
    "direction"
  )
})

test_that("frs_aggregate builds correct upstream SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_aggregate("mock", "working.crossings", "working.streams",
                metrics = c(length_m = "SUM(ST_Length(f.geom))",
                            count = "COUNT(*)"),
                to = "working.result")

  # DROP + CREATE TABLE AS
  expect_length(sql_log, 2)
  expect_match(sql_log[1], "DROP TABLE IF EXISTS working.result")
  expect_match(sql_log[2], "CREATE TABLE working.result")
  expect_match(sql_log[2], "fwa_upstream")
  expect_match(sql_log[2], "SUM.*ST_Length")
  expect_match(sql_log[2], "COUNT")
  expect_match(sql_log[2], "GROUP BY p.blue_line_key, p.downstream_route_measure")
  # Joins to FWA base table for ltree codes
  expect_match(sql_log[2], "fwa_stream_networks_sp ref")
})

test_that("frs_aggregate builds downstream SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_aggregate("mock", "working.pts", "working.streams",
                metrics = c(length_m = "SUM(ST_Length(f.geom))"),
                direction = "downstream",
                to = "working.result")

  expect_match(sql_log[2], "fwa_downstream")
})

test_that("frs_aggregate adds where filter", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_aggregate("mock", "working.pts", "working.streams",
                metrics = c(n = "COUNT(*)"),
                where = "f.accessible IS TRUE",
                to = "working.result")

  expect_match(sql_log[2], "f.accessible IS TRUE")
})

test_that("frs_aggregate returns conn when writing to table", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  result <- frs_aggregate("mock_conn", "working.pts", "working.streams",
                          metrics = c(n = "COUNT(*)"),
                          to = "working.result")
  expect_equal(result, "mock_conn")
})

test_that("frs_aggregate uses .frs_opt for feature column names", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  withr::local_options(fresh.wscode_col = "wscode",
                       fresh.localcode_col = "localcode")

  frs_aggregate("mock", "working.pts", "working.streams",
                metrics = c(n = "COUNT(*)"),
                to = "working.result")

  # Features table uses configured column names
  expect_match(sql_log[2], "f.wscode")
  expect_match(sql_log[2], "f.localcode")
  # Points resolve via FWA ref table (always wscode_ltree)
  expect_match(sql_log[2], "ref.wscode_ltree")
})


# --- Integration tests (live DB) ---

.test_aoi <- function() {
  readRDS(system.file("extdata", "test_streamline.rds", package = "fresh"))
}

test_that("frs_aggregate returns data.frame with collect", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_agg_streams")
    .frs_test_drop(conn, "working.test_agg_pts")
    DBI::dbDisconnect(conn)
  })

  # Extract streams
  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_agg_streams",
    aoi = .test_aoi(),
    overwrite = TRUE
  )

  # Create a single point table from the first segment
  DBI::dbExecute(conn,
    "CREATE TABLE working.test_agg_pts AS
     SELECT blue_line_key, downstream_route_measure,
            wscode_ltree, localcode_ltree
     FROM working.test_agg_streams
     ORDER BY downstream_route_measure
     LIMIT 1")

  # Aggregate upstream length
  result <- frs_aggregate(conn,
    points = "working.test_agg_pts",
    features = "working.test_agg_streams",
    metrics = c(length_m = "ROUND(SUM(ST_Length(f.geom))::numeric, 1)",
                n_segments = "COUNT(*)"),
    direction = "upstream")

  expect_s3_class(result, "data.frame")
  expect_true("length_m" %in% names(result))
  expect_true("n_segments" %in% names(result))
  expect_true("blue_line_key" %in% names(result))
  expect_true("downstream_route_measure" %in% names(result))
  expect_true(result$n_segments[1] > 0)
  expect_true(result$length_m[1] > 0)
})
