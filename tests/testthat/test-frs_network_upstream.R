# -- stream guard SQL (mocked) ------------------------------------------------

test_that("guards are included by default for FWA base table", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L, geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_match(sql, "localcode_ltree IS NOT NULL")
      expect_match(sql, "wscode_ltree <@ '999'")
      mock_result
    }
  )
  frs_network_upstream("mock", blue_line_key = 360873822, downstream_route_measure = 166030)
})

test_that("guards are skipped with include_all = TRUE", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L, geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_no_match(sql, "edge_type NOT IN")
      expect_no_match(sql, "wscode_ltree <@ '999'")
      mock_result
    }
  )
  frs_network_upstream("mock", blue_line_key = 360873822, downstream_route_measure = 166030,
    include_all = TRUE)
})

test_that("guards are skipped for non-FWA tables", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L, geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_no_match(sql, "edge_type NOT IN")
      mock_result
    }
  )
  frs_network_upstream("mock", blue_line_key = 360873822, downstream_route_measure = 166030,
    table = "bcfishpass.streams_co_vw", wscode_col = "wscode",
    localcode_col = "localcode")
})

# -- live DB tests ------------------------------------------------------------

test_that("frs_network_upstream returns sf of upstream segments", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  snapped <- frs_point_snap(conn, x = -126.5, y = 54.5)

  upstream <- frs_network_upstream(conn,
    blue_line_key = snapped$blue_line_key,
    downstream_route_measure = snapped$downstream_route_measure
  )
  expect_s3_class(upstream, "sf")
  expect_true(nrow(upstream) > 0)
  expect_true("stream_order" %in% names(upstream))
})

test_that("include_all = TRUE returns more or equal segments (placeholder/unmapped)", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  blk <- 360873822
  drm <- 166030
  with_guards <- frs_network_upstream(conn, blk, drm)
  without_guards <- frs_network_upstream(conn, blk, drm, include_all = TRUE)

  # Without guards may include placeholder (999 wscode) or unmapped segments
  # In practice fwa_upstream() rarely returns these, so counts may be equal
  expect_true(nrow(without_guards) >= nrow(with_guards))
})
