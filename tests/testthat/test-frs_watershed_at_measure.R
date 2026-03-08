test_that("frs_watershed_at_measure calls fwa_watershedatmeasure", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
      matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
    )), crs = 3005))
  })

  result <- frs_watershed_at_measure(360873822, 208877)

  expect_match(sql_sent, "fwa_watershedatmeasure")
  expect_match(sql_sent, "360873822")
  expect_match(sql_sent, "208877")
  expect_s3_class(result, "sf")
  expect_equal(nrow(result), 1)
})

test_that("frs_watershed_at_measure with upstream_measure returns difference", {
  call_count <- 0
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    call_count <<- call_count + 1
    # Return progressively smaller polygons
    if (call_count == 1) {
      sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
        matrix(c(0, 0, 2, 0, 2, 2, 0, 2, 0, 0), ncol = 2, byrow = TRUE)
      )), crs = 3005))
    } else {
      sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
        matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
      )), crs = 3005))
    }
  })

  result <- frs_watershed_at_measure(360873822, 208877, upstream_measure = 233564)

  expect_equal(call_count, 2)
  expect_s3_class(result, "sf")
  # Difference area should be smaller than the downstream watershed
  expect_lt(as.numeric(sf::st_area(result)), 4)
  expect_gt(as.numeric(sf::st_area(result)), 0)
})

test_that("frs_watershed_at_measure errors when upstream <= downstream", {
  expect_error(
    frs_watershed_at_measure(360873822, 233564, upstream_measure = 208877),
    "upstream_measure must be greater"
  )
})
