# --- Unit tests (no DB) ---

.mock_type_query <- function(conn, sql) {
  cols_match <- regmatches(sql, gregexpr("'[a-z_]+'", sql))[[1]]
  cols_match <- gsub("'", "", cols_match)
  known_tables <- c("public", "fwa_stream_networks_channel_width",
    "fwa_stream_networks_mean_annual_precip", "fwa_stream_networks_discharge",
    "custom_model", "widths", "lookup")
  cols_match <- cols_match[!cols_match %in% known_tables]
  data.frame(
    column_name = cols_match,
    data_type = rep("double precision", length(cols_match)),
    stringsAsFactors = FALSE
  )
}

test_that("frs_col_join builds correct SQL for single key", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) { sql_log <<- c(sql_log, sql); 0L }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql) .mock_type_query(conn, sql),
    .package = "DBI"
  )

  frs_col_join("mock", "working.streams",
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")

  expect_length(sql_log, 3)
  expect_match(sql_log[1], "ADD COLUMN IF NOT EXISTS channel_width")
  expect_match(sql_log[2], "ADD COLUMN IF NOT EXISTS channel_width_source")
  expect_match(sql_log[3], "UPDATE working.streams t SET")
  expect_match(sql_log[3], "channel_width = _src.channel_width")
  expect_match(sql_log[3], "channel_width_source = _src.channel_width_source")
  expect_match(sql_log[3], "t.linear_feature_id = _src.linear_feature_id")
})

test_that("frs_col_join handles composite keys", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) { sql_log <<- c(sql_log, sql); 0L }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql) .mock_type_query(conn, sql),
    .package = "DBI"
  )

  frs_col_join("mock", "working.streams",
    from = "fwa_stream_networks_mean_annual_precip",
    cols = "map_upstream",
    by = c("wscode_ltree", "localcode_ltree"))

  update_sql <- sql_log[length(sql_log)]
  expect_match(update_sql, "t.wscode_ltree = _src.wscode_ltree")
  expect_match(update_sql, "t.localcode_ltree = _src.localcode_ltree")
})

test_that("frs_col_join handles named by (different column names)", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) { sql_log <<- c(sql_log, sql); 0L }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql) .mock_type_query(conn, sql),
    .package = "DBI"
  )

  frs_col_join("mock", "working.streams",
    from = "custom_model.widths",
    cols = "width_m",
    by = c(linear_feature_id = "lid"))

  update_sql <- sql_log[length(sql_log)]
  expect_match(update_sql, "t.linear_feature_id = _src.lid")
})

test_that("frs_col_join accepts subquery in from", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) { sql_log <<- c(sql_log, sql); 0L }
  )

  frs_col_join("mock", "working.streams",
    from = "(SELECT l.linear_feature_id, ua.upstream_area_ha
             FROM fwa_streams_watersheds_lut l
             JOIN fwa_watersheds_upstream_area ua
               ON l.watershed_feature_id = ua.watershed_feature_id) sub",
    cols = "upstream_area_ha",
    by = "linear_feature_id")

  update_sql <- sql_log[length(sql_log)]
  expect_match(update_sql, "fwa_streams_watersheds_lut")
  expect_match(update_sql, "upstream_area_ha = _src.upstream_area_ha")
})

test_that("frs_col_join validates identifiers", {
  expect_error(
    frs_col_join("mock", "DROP TABLE foo",
      from = "lookup", cols = "x", by = "id"),
    "invalid characters"
  )
})

test_that("frs_col_join returns conn invisibly", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql) .mock_type_query(conn, sql),
    .package = "DBI"
  )

  result <- frs_col_join("mock_conn", "working.streams",
    from = "lookup", cols = "x", by = "id")
  expect_equal(result, "mock_conn")
})


# --- Integration tests (live DB) ---

test_that("frs_col_join adds channel_width from FWA lookup", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_col_join")
    DBI::dbDisconnect(conn)
  })

  aoi <- readRDS(system.file("extdata", "test_streamline.rds", package = "fresh"))

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_col_join",
    cols = c("linear_feature_id", "blue_line_key", "geom"),
    aoi = aoi, overwrite = TRUE)

  frs_col_join(conn, "working.test_col_join",
    from = "fwa_stream_networks_channel_width",
    cols = "channel_width",
    by = "linear_feature_id")

  result <- DBI::dbGetQuery(conn,
    "SELECT channel_width FROM working.test_col_join
     WHERE channel_width IS NOT NULL LIMIT 5")

  expect_true(nrow(result) > 0)
  expect_true(all(result$channel_width > 0))
})
