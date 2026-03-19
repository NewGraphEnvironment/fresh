# -- input validation (mocked, no DB needed) ----------------------------------

test_that("x must be single numeric", {
  expect_error(frs_point_snap("mock", x = "a", y = 1), "x must be a single numeric")
  expect_error(frs_point_snap("mock", x = NULL, y = 1), "x must be a single numeric")
  expect_error(frs_point_snap("mock", x = NA, y = 1), "x must be a single numeric")
  expect_error(frs_point_snap("mock", x = c(1, 2), y = 1), "x must be a single numeric")
})

test_that("y must be single numeric", {
  expect_error(frs_point_snap("mock", x = 1, y = "a"), "y must be a single numeric")
  expect_error(frs_point_snap("mock", x = 1, y = NA), "y must be a single numeric")
  expect_error(frs_point_snap("mock", x = 1, y = c(1, 2)), "y must be a single numeric")
})

test_that("srid must be single numeric", {
  expect_error(frs_point_snap("mock", x = 1, y = 1, srid = "abc"), "srid must be a single numeric")
  expect_error(frs_point_snap("mock", x = 1, y = 1, srid = NA), "srid must be a single numeric")
})

test_that("tolerance must be single numeric", {
  expect_error(frs_point_snap("mock", x = 1, y = 1, tolerance = "abc"), "tolerance must be a single numeric")
  expect_error(frs_point_snap("mock", x = 1, y = 1, tolerance = NA), "tolerance must be a single numeric")
})

test_that("num_features must be single numeric", {
  expect_error(frs_point_snap("mock", x = 1, y = 1, num_features = "abc"), "num_features must be a single numeric")
  expect_error(frs_point_snap("mock", x = 1, y = 1, num_features = NA), "num_features must be a single numeric")
})

test_that("blue_line_key must be single numeric when provided", {
  expect_error(
    frs_point_snap("mock", x = 1, y = 1, blue_line_key = "abc"),
    "blue_line_key must be a single numeric"
  )
  expect_error(
    frs_point_snap("mock", x = 1, y = 1, blue_line_key = NA),
    "blue_line_key must be a single numeric"
  )
  expect_error(
    frs_point_snap("mock", x = 1, y = 1, blue_line_key = c(1, 2)),
    "blue_line_key must be a single numeric"
  )
})

test_that("stream_order_min must be single numeric when provided", {
  expect_error(
    frs_point_snap("mock", x = 1, y = 1, stream_order_min = "abc"),
    "stream_order_min must be a single numeric"
  )
  expect_error(
    frs_point_snap("mock", x = 1, y = 1, stream_order_min = NA),
    "stream_order_min must be a single numeric"
  )
})

# -- SQL generation (mocked) -------------------------------------------------

test_that("default path uses fwa_indexpoint", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L,
    gnis_name = "Test",
    blue_line_key = 360873822L,
    downstream_route_measure = 1000,
    distance_to_stream = 10,
    geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_match(sql, "fwa_indexpoint")
      mock_result
    }
  )
  result <- frs_point_snap("mock", x = -126.5, y = 54.5)
  expect_s3_class(result, "sf")
})

test_that("blue_line_key triggers KNN path", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L,
    gnis_name = "Test",
    blue_line_key = 360873822L,
    downstream_route_measure = 1000,
    distance_to_stream = 10,
    geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_match(sql, "blue_line_key = 360873822")
      expect_match(sql, "ST_LineLocatePoint")
      expect_no_match(sql, "fwa_indexpoint")
      mock_result
    }
  )
  result <- frs_point_snap("mock", x = -126.5, y = 54.5, blue_line_key = 360873822)
  expect_s3_class(result, "sf")
})

test_that("stream_order_min triggers KNN path with filter", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L,
    gnis_name = "Test",
    blue_line_key = 360873822L,
    downstream_route_measure = 1000,
    distance_to_stream = 10,
    geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_match(sql, "stream_order >= 4")
      expect_no_match(sql, "fwa_indexpoint")
      mock_result
    }
  )
  result <- frs_point_snap("mock", x = -126.5, y = 54.5, stream_order_min = 4)
  expect_s3_class(result, "sf")
})

test_that("KNN path includes stream filtering guards", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L,
    gnis_name = "Test",
    blue_line_key = 360873822L,
    downstream_route_measure = 1000,
    distance_to_stream = 10,
    geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_match(sql, "localcode_ltree IS NOT NULL")
      expect_match(sql, "wscode_ltree <@ '999'")
      expect_match(sql, "edge_type NOT IN \\(1425\\)")
      mock_result
    }
  )
  result <- frs_point_snap("mock", x = -126.5, y = 54.5, blue_line_key = 360873822)
  expect_s3_class(result, "sf")
})

test_that("blue_line_key and stream_order_min combine in KNN", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L,
    gnis_name = "Test",
    blue_line_key = 360873822L,
    downstream_route_measure = 1000,
    distance_to_stream = 10,
    geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_match(sql, "blue_line_key = 360873822")
      expect_match(sql, "stream_order >= 3")
      mock_result
    }
  )
  result <- frs_point_snap("mock", x = -126.5, y = 54.5,
    blue_line_key = 360873822, stream_order_min = 3)
  expect_s3_class(result, "sf")
})

test_that("KNN SQL has boundary clamping", {
  mock_result <- sf::st_sf(
    linear_feature_id = 1L,
    gnis_name = "Test",
    blue_line_key = 360873822L,
    downstream_route_measure = 1000,
    distance_to_stream = 10,
    geom = sf::st_sfc(sf::st_point(c(1, 1)), crs = 3005)
  )
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      expect_match(sql, "CEIL.*GREATEST")
      expect_match(sql, "FLOOR.*LEAST")
      expect_match(sql, "upstream_route_measure")
      mock_result
    }
  )
  result <- frs_point_snap("mock", x = -126.5, y = 54.5, blue_line_key = 360873822)
  expect_s3_class(result, "sf")
})

# -- live DB tests (shared connection) ----------------------------------------

test_that("frs_point_snap integration tests", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  # Basic snap returns sf with network position
  snapped <- frs_point_snap(conn, x = -126.5, y = 54.5)
  expect_s3_class(snapped, "sf")
  expect_true(nrow(snapped) == 1)
  expect_true("blue_line_key" %in% names(snapped))
  expect_true("downstream_route_measure" %in% names(snapped))
  expect_true("distance_to_stream" %in% names(snapped))

  # Multiple candidates
  multi <- frs_point_snap(conn, x = -126.5, y = 54.5, num_features = 3)
  expect_true(nrow(multi) <= 3)

  # blue_line_key snaps to specified stream
  blk_snap <- frs_point_snap(conn, x = -126.5, y = 54.5,
    blue_line_key = 360873822)
  expect_equal(blk_snap$blue_line_key, 360873822L)

  # stream_order_min filters small streams
  order_snap <- frs_point_snap(conn, x = -126.5, y = 54.5,
    stream_order_min = 4)
  expect_true(nrow(order_snap) >= 1)

  # blue_line_key + stream_order_min work together
  combo_snap <- frs_point_snap(conn, x = -126.5, y = 54.5,
    blue_line_key = 360873822, stream_order_min = 3)
  expect_equal(combo_snap$blue_line_key, 360873822L)

  # KNN returns consistent measure with fwa_indexpoint
  knn <- frs_point_snap(conn, x = -126.5, y = 54.5,
    blue_line_key = snapped$blue_line_key)
  expect_equal(knn$blue_line_key, snapped$blue_line_key)
  expect_true(abs(knn$downstream_route_measure -
    snapped$downstream_route_measure) < 2)
})
