# -- stream guard SQL (mocked) ------------------------------------------------

test_that("guards are included by default for FWA base table", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L, geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(sql, ...) {
      expect_match(sql, "localcode_ltree IS NOT NULL")
      mock_result
    }
  )
  frs_network_downstream(blue_line_key = 360873822, downstream_route_measure = 166030)
})

test_that("guards are skipped with include_all = TRUE", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L, geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(sql, ...) {
      expect_no_match(sql, "edge_type NOT IN")
      mock_result
    }
  )
  frs_network_downstream(blue_line_key = 360873822, downstream_route_measure = 166030,
    include_all = TRUE)
})

# -- live DB tests ------------------------------------------------------------

test_that("frs_network_downstream returns sf of downstream segments", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  snapped <- frs_point_snap(x = -126.5, y = 54.5)

  downstream <- frs_network_downstream(
    blue_line_key = snapped$blue_line_key,
    downstream_route_measure = snapped$downstream_route_measure
  )
  expect_s3_class(downstream, "sf")
  expect_true(nrow(downstream) > 0)
  expect_true("stream_order" %in% names(downstream))
})
