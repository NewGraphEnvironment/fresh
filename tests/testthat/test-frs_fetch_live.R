# Live determinism of the fetchers (#286). Two calls on one database follow
# the same plan, so identical() alone cannot catch a missing ORDER BY; the
# is.unsorted() checks can, and the mocked SQL tests in test-frs_fetch_sql.R
# are the dependable guard.

test_that("simplified fetches return identical sf, ordered by key", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  cases <- list(
    list(f = frs_lake_fetch, key = "waterbody_poly_id"),
    list(f = frs_wetland_fetch, key = "waterbody_poly_id"),
    list(f = frs_stream_fetch, key = "linear_feature_id")
  )
  for (cs in cases) {
    a <- cs$f(conn, watershed_group_code = "BULK", simplify_m = 25)
    b <- cs$f(conn, watershed_group_code = "BULK", simplify_m = 25)
    expect_gt(nrow(a), 0)
    expect_identical(a, b)
    expect_false(is.unsorted(a[[cs$key]], strictly = TRUE))
  }
})

test_that("limit returns the lowest keys", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  all_ids <- frs_lake_fetch(conn, watershed_group_code = "BULK",
                            cols = c("waterbody_poly_id", "geom"))
  top <- frs_lake_fetch(conn, watershed_group_code = "BULK", limit = 5,
                        cols = c("waterbody_poly_id", "geom"))
  expect_identical(top$waterbody_poly_id, head(all_ids$waterbody_poly_id, 5))
})

test_that("simplify_m keeps stored area_ha and stream direction", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  raw <- frs_lake_fetch(conn, watershed_group_code = "BULK", area_ha_min = 50)
  simp <- frs_lake_fetch(conn, watershed_group_code = "BULK", area_ha_min = 50,
                         simplify_m = 100)
  expect_identical(simp$area_ha, raw$area_ha)
  expect_true(all(sf::st_is_valid(simp)))

  s_raw <- frs_stream_fetch(conn, watershed_group_code = "BULK",
                            stream_order_min = 5)
  s_simp <- frs_stream_fetch(conn, watershed_group_code = "BULK",
                             stream_order_min = 5, simplify_m = 25)
  first_xy <- function(x) {
    xy <- sf::st_coordinates(sf::st_zm(x))
    l <- xy[, ncol(xy)]
    xy[!duplicated(l), c("X", "Y")]
  }
  # Simplification keeps end points, so an unreversed segment starts where
  # it did
  expect_equal(first_xy(s_simp), first_xy(s_raw))
})

test_that("aoi intersects exactly where bbox matches envelopes", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  lake <- frs_lake_fetch(conn, watershed_group_code = "BULK",
                         area_ha_min = 100, limit = 1)
  bb <- sf::st_bbox(lake)
  # A 1 m square just inside the lake's envelope corner
  sq <- sf::st_as_sfc(sf::st_bbox(c(xmin = bb[["xmin"]] + 1,
    ymin = bb[["ymin"]] + 1, xmax = bb[["xmin"]] + 2,
    ymax = bb[["ymin"]] + 2), crs = 3005))
  skip_if(lengths(sf::st_intersects(lake, sq)) > 0,
          "corner square touches the lake")

  by_bbox <- frs_lake_fetch(conn, bbox = as.numeric(sf::st_bbox(sq)))
  by_aoi <- frs_lake_fetch(conn, aoi = sq)
  expect_true(lake$waterbody_poly_id %in% by_bbox$waterbody_poly_id)
  expect_false(lake$waterbody_poly_id %in% by_aoi$waterbody_poly_id)
})

test_that("simplified watershed and subbasin are identical on repeat", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  ws1 <- frs_watershed_at_measure(conn, 360873822, 208877,
                                  upstream_measure = 233564, simplify_m = 50)
  ws2 <- frs_watershed_at_measure(conn, 360873822, 208877,
                                  upstream_measure = 233564, simplify_m = 50)
  expect_identical(ws1, ws2)
  expect_equal(nrow(ws1), 1)
  expect_true(sf::st_is_valid(ws1))

  raw <- frs_watershed_at_measure(conn, 360873822, 208877,
                                  upstream_measure = 233564)
  # Simplified at 50 m, the area moves by well under 1%
  expect_lt(abs(as.numeric(sf::st_area(ws1) / sf::st_area(raw)) - 1), 0.01)
})
