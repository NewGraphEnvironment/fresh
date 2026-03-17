# -- frs_watershed_split unit tests --------------------------------------------

test_that("frs_watershed_split validates inputs", {
  expect_error(frs_watershed_split("mock", "not a df"), "points must be a data frame")
  expect_error(
    frs_watershed_split("mock", data.frame(x = 1, y = 2)),
    "must have 'lon' and 'lat' columns"
  )
  expect_error(
    frs_watershed_split("mock", data.frame(lon = numeric(0), lat = numeric(0))),
    "points has no rows"
  )
  expect_error(
    frs_watershed_split("mock", data.frame(lon = 1, lat = 1), aoi = "bad"),
    "aoi must be an sf or sfc"
  )
})

test_that("frs_watershed_split errors when all snaps fail", {
  mockery::stub(frs_watershed_split, "frs_point_snap", function(...) {
    stop("no stream")
  })
  pts <- data.frame(lon = c(0, 0), lat = c(0, 0))
  expect_error(
    suppressMessages(frs_watershed_split("mock", pts)),
    "No points could be snapped"
  )
})

test_that("frs_watershed_split errors when all watersheds fail", {
  snap_result <- sf::st_sf(
    linear_feature_id = 1L,
    gnis_name = "Test Creek",
    blue_line_key = 123L,
    downstream_route_measure = 100,
    distance_to_stream = 10,
    geom = sf::st_sfc(sf::st_point(c(0, 0)), crs = 3005)
  )
  mockery::stub(frs_watershed_split, "frs_point_snap", function(...) snap_result)
  mockery::stub(frs_watershed_split, "frs_watershed_at_measure", function(...) {
    stop("delineation failed")
  })
  pts <- data.frame(lon = c(-126, -125), lat = c(54, 55))
  expect_error(
    suppressMessages(frs_watershed_split("mock", pts)),
    "No watersheds could be delineated"
  )
})

test_that("frs_watershed_split produces sub-basins from mocked data", {
  # Mock snap: two points on different parts of the same stream
  snap_call <- 0L
  snap_results <- list(
    sf::st_sf(
      linear_feature_id = 1L, gnis_name = "Test Creek",
      blue_line_key = 100L, downstream_route_measure = 500,
      distance_to_stream = 5,
      geom = sf::st_sfc(sf::st_point(c(1000, 1000)), crs = 3005)
    ),
    sf::st_sf(
      linear_feature_id = 2L, gnis_name = "Test Creek",
      blue_line_key = 100L, downstream_route_measure = 1000,
      distance_to_stream = 8,
      geom = sf::st_sfc(sf::st_point(c(1000, 2000)), crs = 3005)
    )
  )
  mockery::stub(frs_watershed_split, "frs_point_snap", function(...) {
    snap_call <<- snap_call + 1L
    snap_results[[snap_call]]
  })

  # Mock watersheds: big downstream, small upstream (in 4326 coords)
  ws_call <- 0L
  big_ws <- sf::st_sf(
    geom = sf::st_sfc(sf::st_polygon(list(rbind(
      c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, 0)
    ))), crs = 3005)
  )
  small_ws <- sf::st_sf(
    geom = sf::st_sfc(sf::st_polygon(list(rbind(
      c(3, 3), c(7, 3), c(7, 7), c(3, 7), c(3, 3)
    ))), crs = 3005)
  )
  mockery::stub(frs_watershed_split, "frs_watershed_at_measure", function(conn, blk, drm, ...) {
    ws_call <<- ws_call + 1L
    if (ws_call == 1L) big_ws else small_ws
  })

  pts <- data.frame(
    lon = c(-126.5, -126.25),
    lat = c(54.19, 54.46),
    site_name = c("Lower", "Upper")
  )
  result <- suppressMessages(frs_watershed_split("mock", pts))

  expect_s3_class(result, "sf")
  expect_equal(nrow(result), 2L)
  expect_true("blk" %in% names(result))
  expect_true("drm" %in% names(result))
  expect_true("gnis_name" %in% names(result))
  expect_true("area_km2" %in% names(result))
  # Extra column preserved
  expect_true("site_name" %in% names(result))
  expect_equal(result$site_name, c("Lower", "Upper"))
})

test_that("frs_watershed_split drops sf geometry from input", {
  pts_sf <- sf::st_sf(
    lon = -126.5, lat = 54.19,
    geometry = sf::st_sfc(sf::st_point(c(-126.5, 54.19)), crs = 4326)
  )

  snap_result <- sf::st_sf(
    linear_feature_id = 1L, gnis_name = "Test Creek",
    blue_line_key = 100L, downstream_route_measure = 500,
    distance_to_stream = 5,
    geom = sf::st_sfc(sf::st_point(c(1000, 1000)), crs = 3005)
  )
  ws <- sf::st_sf(
    geom = sf::st_sfc(sf::st_polygon(list(rbind(
      c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, 0)
    ))), crs = 3005)
  )
  mockery::stub(frs_watershed_split, "frs_point_snap", function(...) snap_result)
  mockery::stub(frs_watershed_split, "frs_watershed_at_measure", function(...) ws)

  result <- suppressMessages(frs_watershed_split("mock", pts_sf))
  expect_s3_class(result, "sf")
  expect_equal(nrow(result), 1L)
})

test_that("frs_watershed_split transforms to target crs", {
  snap_result <- sf::st_sf(
    linear_feature_id = 1L, gnis_name = "Test Creek",
    blue_line_key = 100L, downstream_route_measure = 500,
    distance_to_stream = 5,
    geom = sf::st_sfc(sf::st_point(c(1000, 1000)), crs = 3005)
  )
  ws <- sf::st_sf(
    geom = sf::st_sfc(sf::st_polygon(list(rbind(
      c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, 0)
    ))), crs = 3005)
  )
  mockery::stub(frs_watershed_split, "frs_point_snap", function(...) snap_result)
  mockery::stub(frs_watershed_split, "frs_watershed_at_measure", function(...) ws)

  pts <- data.frame(lon = -126.5, lat = 54.19)
  result <- suppressMessages(frs_watershed_split("mock", pts, crs = 3005))
  expect_equal(sf::st_crs(result)$epsg, 3005L)
})
