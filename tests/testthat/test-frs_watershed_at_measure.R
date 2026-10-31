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

# -- simplify_m (#286) ----------------------------------------------------------

unit_square_sf <- function(...) {
  sf::st_sf(..., geom = sf::st_sfc(sf::st_polygon(list(
    matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE)
  )), crs = 3005))
}

test_that("frs_watershed_at_measure without simplify_m sends the same SQL as before", {
  sqls <- character(0)
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sqls <<- c(sqls, sql)
    unit_square_sf()
  })
  frs_watershed_at_measure("mock", 360873822, 208877)
  expect_identical(sqls, paste(
    "SELECT geom FROM whse_basemapping.fwa_watershedatmeasure(360873822,",
    "208877)"))
})

test_that("frs_watershed_at_measure simplifies and normalizes a single watershed", {
  sqls <- character(0)
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sqls <<- c(sqls, sql)
    unit_square_sf()
  })
  frs_watershed_at_measure("mock", 360873822, 208877, simplify_m = 50)
  expect_length(sqls, 1)
  expect_match(sqls, paste0(
    "SELECT ST_Normalize(ST_SimplifyPreserveTopology(geom, 50)) AS geom ",
    "FROM whse_basemapping.fwa_watershedatmeasure(360873822, 208877)"),
    fixed = TRUE)
})

test_that("frs_watershed_at_measure simplifies a subbasin once, after the difference", {
  sqls <- character(0)
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sqls <<- c(sqls, sql)
    unit_square_sf(intersects = TRUE)
  })
  res <- frs_watershed_at_measure("mock", 360873822, 165115,
    upstream_measure = 838, upstream_blk = 360886221, simplify_m = 50)
  expect_length(sqls, 1)
  expect_match(sqls, paste0(
    "ST_Normalize(ST_SimplifyPreserveTopology(",
    "ST_Difference(d.geom, u.geom), 50)) AS geom"), fixed = TRUE)
  expect_match(sqls, "fwa_watershedatmeasure(360873822, 165115) d", fixed = TRUE)
  expect_match(sqls, "fwa_watershedatmeasure(360886221, 838) u", fixed = TRUE)
  expect_identical(names(res), "geom")
})

test_that("frs_watershed_at_measure simplified subbasin errors when not intersecting", {
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    unit_square_sf(intersects = FALSE)
  })
  expect_error(
    frs_watershed_at_measure("mock", 111111, 1000, upstream_measure = 500,
                             upstream_blk = 222222, simplify_m = 10),
    "does not intersect"
  )
})

test_that("frs_watershed_at_measure simplified subbasin drops an empty difference", {
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sf::st_sf(intersects = TRUE,
              geom = sf::st_sfc(sf::st_polygon(), crs = 3005))
  })
  res <- frs_watershed_at_measure("mock", 1, 10, upstream_measure = 20,
                                  simplify_m = 10)
  expect_equal(nrow(res), 0)
})

test_that("frs_watershed_at_measure rejects a bad simplify_m before the DB", {
  expect_error(frs_watershed_at_measure("mock", 1, 10, simplify_m = 0),
               "simplify_m must be a single positive number")
})

test_that("frs_watershed_at_measure writes a round key and measure in full", {
  # sprintf("%s", 356000000) is "3.56e+08", which Postgres reads as numeric
  # and matches to no fwa_watershedatmeasure() signature (#286 review)
  for (simplify_m in list(NULL, 25)) {
    sqls <- character(0)
    local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
      sqls <<- c(sqls, sql)
      if (grepl("intersects", sql)) unit_square_sf(intersects = TRUE) else
        unit_square_sf()
    })
    frs_watershed_at_measure("mock", 356000000, 1e6,
      upstream_measure = 2e6, simplify_m = simplify_m)
    all_sql <- paste(sqls, collapse = "\n")
    expect_match(all_sql, "fwa_watershedatmeasure(356000000, 1000000)",
                 fixed = TRUE)
    expect_match(all_sql, "fwa_watershedatmeasure(356000000, 2000000)",
                 fixed = TRUE)
    expect_no_match(all_sql, "e+", fixed = TRUE)
  }
})

test_that("frs_watershed_at_measure writes a measure at full precision", {
  # A segment's own downstream_route_measure rounded to 10 digits can fall
  # below it, and fwapg then picks the segment before (#286 review round 3).
  # This value needs all 17 digits: 15 do not read back as the same double.
  m <- 1234567.8912345678
  expect_false(as.numeric(sprintf("%.15g", m)) == m)
  for (simplify_m in list(NULL, 25)) {
    sqls <- character(0)
    local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
      sqls <<- c(sqls, sql)
      unit_square_sf()
    })
    frs_watershed_at_measure("mock", 360609038, m, simplify_m = simplify_m)
    sent <- regmatches(sqls, regexpr("(?<=360609038, )[^)]+", sqls,
                                     perl = TRUE))
    expect_identical(sent, "1234567.8912345679")
  }
})
