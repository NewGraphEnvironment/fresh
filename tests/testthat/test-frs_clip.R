# -- frs_clip unit tests -------------------------------------------------------

test_that("frs_clip clips polygons to AOI", {
  # Create a polygon that extends beyond the AOI
  big_poly <- sf::st_sf(
    id = 1L,
    geom = sf::st_sfc(
      sf::st_polygon(list(rbind(c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, 0)))),
      crs = 4326
    )
  )
  aoi <- sf::st_sf(
    geom = sf::st_sfc(
      sf::st_polygon(list(rbind(c(2, 2), c(8, 2), c(8, 8), c(2, 8), c(2, 2)))),
      crs = 4326
    )
  )

  clipped <- frs_clip(big_poly, aoi)
  expect_s3_class(clipped, "sf")
  expect_true(nrow(clipped) == 1L)

  # Clipped area should be smaller
  expect_true(sf::st_area(clipped) < sf::st_area(big_poly))
})

test_that("frs_clip clips linestrings to AOI", {
  line <- sf::st_sf(
    id = 1L,
    geom = sf::st_sfc(
      sf::st_linestring(rbind(c(0, 5), c(10, 5))),
      crs = 4326
    )
  )
  aoi <- sf::st_sf(
    geom = sf::st_sfc(
      sf::st_polygon(list(rbind(c(2, 0), c(8, 0), c(8, 10), c(2, 10), c(2, 0)))),
      crs = 4326
    )
  )

  clipped <- frs_clip(line, aoi)
  expect_s3_class(clipped, "sf")
  expect_true(nrow(clipped) >= 1L)
  # Geometry type should still be linestring
  expect_true(all(sf::st_geometry_type(clipped) %in% c("LINESTRING", "MULTILINESTRING")))
})

test_that("frs_clip returns empty sf for non-intersecting features", {
  poly <- sf::st_sf(
    id = 1L,
    geom = sf::st_sfc(
      sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0)))),
      crs = 4326
    )
  )
  aoi <- sf::st_sf(
    geom = sf::st_sfc(
      sf::st_polygon(list(rbind(c(50, 50), c(51, 50), c(51, 51), c(50, 51), c(50, 50)))),
      crs = 4326
    )
  )

  clipped <- frs_clip(poly, aoi)
  expect_s3_class(clipped, "sf")
  expect_true(nrow(clipped) == 0L)
})

test_that("frs_clip returns input unchanged when empty", {
  empty <- sf::st_sf(
    id = integer(0),
    geom = sf::st_sfc(crs = 4326)
  )
  aoi <- sf::st_sf(
    geom = sf::st_sfc(
      sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0)))),
      crs = 4326
    )
  )

  result <- frs_clip(empty, aoi)
  expect_true(nrow(result) == 0L)
})

test_that("frs_clip transforms CRS when mismatched", {
  poly <- sf::st_sf(
    id = 1L,
    geom = sf::st_sfc(
      sf::st_polygon(list(rbind(
        c(-126, 54), c(-125, 54), c(-125, 55), c(-126, 55), c(-126, 54)
      ))),
      crs = 4326
    )
  )
  # AOI in BC Albers
  aoi_albers <- sf::st_transform(poly, 3005)

  clipped <- frs_clip(poly, aoi_albers)
  expect_s3_class(clipped, "sf")
  expect_equal(sf::st_crs(clipped), sf::st_crs(poly))
})

test_that("frs_clip validates inputs", {
  expect_error(frs_clip(data.frame(x = 1), sf::st_sfc()), "x must be an sf")
  poly <- sf::st_sf(
    id = 1L,
    geom = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326)
  )
  expect_error(frs_clip(poly, data.frame()), "aoi must be an sf")
})
