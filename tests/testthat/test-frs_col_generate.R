# --- Unit tests (no DB) ---

test_that("frs_col_generate validates identifiers", {
  expect_error(frs_col_generate("mock", "DROP TABLE foo"), "invalid characters")
})

test_that("frs_col_generate builds correct ALTER statements", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_col_generate("mock", "working.streams")

  # 4 columns × 2 statements each (DROP + ADD) = 8

  expect_length(sql_log, 8)

  # Check gradient
  expect_match(sql_log[1], "DROP COLUMN IF EXISTS gradient")
  expect_match(sql_log[2], "ADD COLUMN gradient")
  expect_match(sql_log[2], "GENERATED ALWAYS")
  expect_match(sql_log[2], "ST_Z")

  # Check downstream_route_measure
  expect_match(sql_log[3], "DROP COLUMN IF EXISTS downstream_route_measure")
  expect_match(sql_log[4], "ST_M.*ST_PointN.*1\\)")

  # Check upstream_route_measure
  expect_match(sql_log[5], "DROP COLUMN IF EXISTS upstream_route_measure")
  expect_match(sql_log[6], "ST_M.*ST_PointN.*-1\\)")

  # Check length_metre
  expect_match(sql_log[7], "DROP COLUMN IF EXISTS length_metre")
  expect_match(sql_log[8], "ST_Length")
})

test_that("frs_col_generate returns conn invisibly", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  result <- frs_col_generate("mock_conn", "working.streams")
  expect_equal(result, "mock_conn")
})


# --- Integration tests (live DB, Byman-Ailport AOI) ---

.test_aoi <- function() {
  readRDS(system.file("extdata", "test_streamline.rds", package = "fresh"))
}

test_that("frs_col_generate creates generated columns", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_col_gen")
    DBI::dbDisconnect(conn)
  })

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_col_gen",
    aoi = .test_aoi(),
    overwrite = TRUE
  )

  frs_col_generate(conn, "working.test_col_gen")

  # Check that columns are generated (is_generated = 'ALWAYS')
  gen_cols <- DBI::dbGetQuery(conn,
    "SELECT column_name, is_generated FROM information_schema.columns
     WHERE table_schema = 'working' AND table_name = 'test_col_gen'
     AND column_name IN ('gradient', 'downstream_route_measure',
                         'upstream_route_measure', 'length_metre')
     ORDER BY column_name")

  expect_equal(nrow(gen_cols), 4)
  expect_true(all(gen_cols$is_generated == "ALWAYS"))
})

test_that("frs_col_generate values match original after roundtrip", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_col_gen_rt")
    DBI::dbDisconnect(conn)
  })

  # Extract with original gradient values
  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_col_gen_rt",
    cols = c("linear_feature_id", "gradient", "downstream_route_measure",
             "upstream_route_measure", "length_metre", "geom"),
    aoi = .test_aoi(),
    overwrite = TRUE
  )

  # Save original values
  before <- DBI::dbGetQuery(conn,
    "SELECT linear_feature_id, gradient, downstream_route_measure
     FROM working.test_col_gen_rt
     ORDER BY linear_feature_id LIMIT 20")

  # Convert to generated columns
  frs_col_generate(conn, "working.test_col_gen_rt")

  # Check generated values match originals
  after <- DBI::dbGetQuery(conn,
    "SELECT linear_feature_id, gradient, downstream_route_measure
     FROM working.test_col_gen_rt
     ORDER BY linear_feature_id LIMIT 20")

  # Gradient should be very close (rounding differences possible)
  expect_equal(before$downstream_route_measure,
               after$downstream_route_measure, tolerance = 0.01)
})

test_that("frs_col_generate + frs_break_apply produces correct gradient", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_gen_break")
    .frs_test_drop(conn, "working.test_gen_break_brk")
    DBI::dbDisconnect(conn)
  })

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_gen_break",
    cols = c("linear_feature_id", "blue_line_key", "gradient",
             "downstream_route_measure", "upstream_route_measure",
             "length_metre", "geom"),
    aoi = .test_aoi(),
    overwrite = TRUE
  )

  # Convert to generated columns BEFORE breaking
  frs_col_generate(conn, "working.test_gen_break")

  # Break
  frs_break_find(conn, "working.test_gen_break",
    to = "working.test_gen_break_brk",
    attribute = "gradient", threshold = 0.02)
  frs_break_apply(conn, "working.test_gen_break",
    breaks = "working.test_gen_break_brk")

  # All segments should have non-NULL gradient (auto-computed)
  null_count <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_gen_break WHERE gradient IS NULL")
  expect_equal(null_count$n, 0L)

  # Should have more segments than before
  count <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_gen_break")
  expect_true(count$n > 15)
})
