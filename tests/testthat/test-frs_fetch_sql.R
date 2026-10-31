# SQL shape of the three fetchers (#286): row order, simplification, aoi.
# Mocked, so no database is needed.

capture_fetch_sql <- function(fetch, ...) {
  sql_sent <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      sql_sent <<- sql
      data.frame()
    },
    .env = parent.frame()
  )
  fetch("mock", ...)
  sql_sent
}

poly_3005 <- function() {
  sf::st_sfc(sf::st_polygon(list(
    matrix(c(0, 0, 10, 0, 10, 10, 0, 10, 0, 0), ncol = 2, byrow = TRUE)
  )), crs = 3005)
}

fetchers <- list(
  lake    = list(f = frs_lake_fetch,    key = "waterbody_poly_id", normalize = TRUE),
  wetland = list(f = frs_wetland_fetch, key = "waterbody_poly_id", normalize = TRUE),
  stream  = list(f = frs_stream_fetch,  key = "linear_feature_id", normalize = FALSE)
)

for (nm in names(fetchers)) {
  fx <- fetchers[[nm]]

  test_that(paste(nm, "fetch orders by its unique key, before LIMIT"), {
    sql <- capture_fetch_sql(fx$f, watershed_group_code = "BULK", limit = 5)
    expect_match(sql, paste0(" ORDER BY ", fx$key, " LIMIT 5$"))
  })

  test_that(paste(nm, "fetch drops ORDER BY with order_by = NULL"), {
    sql <- capture_fetch_sql(fx$f, watershed_group_code = "BULK",
                             order_by = NULL)
    expect_no_match(sql, "ORDER BY")
  })

  test_that(paste(nm, "fetch rejects a bad order_by"), {
    expect_error(capture_fetch_sql(fx$f, order_by = "id; DROP TABLE x"))
  })

  test_that(paste(nm, "fetch selects plain geom without simplify_m"), {
    sql <- capture_fetch_sql(fx$f, watershed_group_code = "BULK")
    expect_no_match(sql, "ST_Simplify|ST_Normalize")
    expect_match(sql, ", geom FROM ")
  })

  test_that(paste(nm, "fetch simplifies geom with simplify_m"), {
    sql <- capture_fetch_sql(fx$f, watershed_group_code = "BULK",
                             simplify_m = 20)
    simp <- "ST_SimplifyPreserveTopology(geom, 20) AS geom FROM "
    if (fx$normalize) {
      expect_match(sql, paste0("ST_Normalize(", sub(" AS", ") AS", simp)),
                   fixed = TRUE)
    } else {
      expect_match(sql, simp, fixed = TRUE)
      expect_no_match(sql, "ST_Normalize")
    }
  })

  test_that(paste(nm, "fetch rejects a bad simplify_m"), {
    expect_error(capture_fetch_sql(fx$f, simplify_m = -5),
                 "simplify_m must be a single positive number")
  })

  test_that(paste(nm, "fetch filters an sf aoi with ST_Intersects"), {
    sql <- capture_fetch_sql(fx$f, aoi = poly_3005())
    expect_match(sql, "WHERE .*ST_Intersects\\(geom, ST_GeomFromText\\('POLYGON")
  })

  test_that(paste(nm, "fetch keeps bbox as envelope overlap"), {
    sql <- capture_fetch_sql(fx$f, bbox = c(0, 0, 10, 10))
    expect_match(sql, "geom && ST_MakeEnvelope(0, 0, 10, 10, 3005)",
                 fixed = TRUE)
  })

  test_that(paste(nm, "fetch rejects an invalid table name"), {
    expect_error(capture_fetch_sql(fx$f, table = "x; DROP TABLE y"),
                 "invalid characters")
  })
}
