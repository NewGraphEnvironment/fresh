test_that("frs_watershed_at_measure calls fwa_watershedatmeasure", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sql_sent <<- sql
    sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
      matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
    )), crs = 3005))
  })

  result <- frs_watershed_at_measure("mock", 360873822, 208877)

  expect_match(sql_sent, "fwa_watershedatmeasure")
  expect_match(sql_sent, "360873822")
  expect_match(sql_sent, "208877")
  expect_s3_class(result, "sf")
  expect_equal(nrow(result), 1)
})

test_that("frs_watershed_at_measure with upstream_measure returns difference", {
  call_count <- 0
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
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

  result <- frs_watershed_at_measure("mock", 360873822, 208877, upstream_measure = 233564)

  expect_equal(call_count, 2)
  expect_s3_class(result, "sf")
  # Difference area should be smaller than the downstream watershed
  expect_lt(as.numeric(sf::st_area(result)), 4)
  expect_gt(as.numeric(sf::st_area(result)), 0)
})

test_that("frs_watershed_at_measure errors when upstream <= downstream on same BLK", {
  expect_error(
    frs_watershed_at_measure("mock", 360873822, 233564, upstream_measure = 208877),
    "upstream_measure must be greater"
  )
})

test_that("frs_watershed_at_measure with upstream_blk uses different BLK", {
  sqls <- list()
  call_count <- 0
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    call_count <<- call_count + 1
    sqls[[call_count]] <<- sql
    if (call_count == 1) {
      # Large downstream watershed
      sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
        matrix(c(0, 0, 3, 0, 3, 3, 0, 3, 0, 0), ncol = 2, byrow = TRUE)
      )), crs = 3005))
    } else {
      # Smaller upstream watershed (contained within downstream)
      sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
        matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
      )), crs = 3005))
    }
  })

  result <- frs_watershed_at_measure("mock", 360873822, 165115,
    upstream_measure = 838, upstream_blk = 360886221)

  expect_equal(call_count, 2)
  expect_match(sqls[[1]], "360873822")
  expect_match(sqls[[2]], "360886221")
  expect_match(sqls[[2]], "838")
  expect_s3_class(result, "sf")
  expect_gt(as.numeric(sf::st_area(result)), 0)
})

test_that("frs_watershed_at_measure skips measure check for different BLK", {
  call_count <- 0
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    call_count <<- call_count + 1
    if (call_count == 1) {
      sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
        matrix(c(0, 0, 3, 0, 3, 3, 0, 3, 0, 0), ncol = 2, byrow = TRUE)
      )), crs = 3005))
    } else {
      sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
        matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
      )), crs = 3005))
    }
  })

  # upstream_measure < downstream_route_measure but on different BLK — should NOT error
  result <- frs_watershed_at_measure("mock", 360873822, 208877,
    upstream_measure = 838, upstream_blk = 360886221)
  expect_equal(call_count, 2)
  expect_s3_class(result, "sf")
})

test_that("frs_watershed_at_measure rejects NULL blue_line_key", {
  expect_error(frs_watershed_at_measure("mock", NULL, 208877), "single numeric")
})

test_that("frs_watershed_at_measure rejects NA blue_line_key", {
  expect_error(frs_watershed_at_measure("mock", NA, 208877), "single numeric")
})

test_that("frs_watershed_at_measure rejects character blue_line_key", {
  expect_error(frs_watershed_at_measure("mock", "abc", 208877), "single numeric")
})

test_that("frs_watershed_at_measure rejects NULL measure", {
  expect_error(frs_watershed_at_measure("mock", 360873822, NULL), "single numeric")
})

test_that("frs_watershed_at_measure rejects NA measure", {
  expect_error(frs_watershed_at_measure("mock", 360873822, NA), "single numeric")
})

test_that("frs_watershed_at_measure rejects vector blk", {
  expect_error(frs_watershed_at_measure("mock", c(1, 2), 208877), "single numeric")
})

test_that("frs_watershed_at_measure rejects NA upstream_measure", {
  expect_error(
    frs_watershed_at_measure("mock", 360873822, 208877, upstream_measure = NA),
    "single numeric"
  )
})

test_that("frs_watershed_at_measure rejects character upstream_blk", {
  expect_error(
    frs_watershed_at_measure("mock", 360873822, 208877, upstream_measure = 233564,
      upstream_blk = "abc"),
    "single numeric"
  )
})

test_that("frs_watershed_at_measure upstream_blk without upstream_measure is ignored", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sql_sent <<- sql
    sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
      matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
    )), crs = 3005))
  })

  # upstream_blk provided but upstream_measure is NULL — should return single ws
  result <- frs_watershed_at_measure("mock", 360873822, 208877, upstream_blk = 360886221)
  expect_s3_class(result, "sf")
  # Only one query (no subtraction)
  expect_match(sql_sent, "360873822")
})

test_that("frs_watershed_at_measure equal measures on same BLK errors", {
  expect_error(
    frs_watershed_at_measure("mock", 360873822, 208877, upstream_measure = 208877),
    "upstream_measure must be greater"
  )
})

test_that("frs_watershed_at_measure handles negative measure", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sql_sent <<- sql
    sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
      matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
    )), crs = 3005))
  })

  # Negative measure — function doesn't validate, passes to fwapg
  result <- frs_watershed_at_measure("mock", 360873822, -100)
  expect_match(sql_sent, "-100")
})

test_that("frs_watershed_at_measure zero measure works", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sql_sent <<- sql
    sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
      matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
    )), crs = 3005))
  })

  result <- frs_watershed_at_measure("mock", 360873822, 0)
  expect_match(sql_sent, "fwa_watershedatmeasure\\(360873822, 0\\)")
})

test_that("frs_watershed_at_measure errors when watersheds don't intersect", {
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    if (grepl("111111", sql)) {
      # Downstream — box at (0,0)
      sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
        matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
      )), crs = 3005))
    } else {
      # Upstream — box at (10,10), no overlap
      sf::st_sf(geom = sf::st_sfc(sf::st_polygon(list(
        matrix(c(10, 10, 11, 10, 11, 11, 10, 11, 10, 10), ncol = 2, byrow = TRUE)
      )), crs = 3005))
    }
  })

  expect_error(
    frs_watershed_at_measure("mock", 111111, 1000,
      upstream_measure = 500, upstream_blk = 222222),
    "does not intersect"
  )
})
