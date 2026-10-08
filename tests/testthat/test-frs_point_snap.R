# -- .frs_point_snap_sql() shape (no DB) --------------------------------------

pts_sql <- "SELECT p.id, p.geom FROM pts_src p"

# The per-point lateral (filters must sit before its LIMIT) and the final
# SELECT (what the caller gets back). Asserting against the whole string
# would pass on a name that only appears in the other half.
sql_lateral <- function(sql) {
  out <- regmatches(sql, regexpr("CROSS JOIN LATERAL.*\\) s\n", sql))
  expect_length(out, 1L)
  out
}
sql_select <- function(sql) {
  out <- regmatches(sql, regexpr("\nSELECT\n.*$", sql))
  expect_length(out, 1L)
  out
}

test_that("snap SQL is one lateral KNN query within tolerance", {
  sql <- .frs_point_snap_sql(pts_sql, col_id = "id_point")
  lateral <- sql_lateral(sql)
  expect_match(lateral, "ST_DWithin\\(s\\.geom, p\\.geom, 100\\)")
  expect_match(lateral,
               "ORDER BY s\\.geom <-> p\\.geom, s\\.linear_feature_id")
  expect_match(lateral, "LIMIT 1\\b")
  expect_match(lateral, "whse_basemapping.fwa_stream_networks_sp s")
  expect_no_match(sql, "fwa_indexpoint")
})

test_that("snap SQL applies the snap guards", {
  lateral <- sql_lateral(.frs_point_snap_sql(pts_sql, col_id = "id_point"))
  expect_match(lateral, "s.localcode_ltree IS NOT NULL", fixed = TRUE)
  expect_match(lateral, "NOT s.wscode_ltree <@ '999'", fixed = TRUE)
  expect_match(lateral, "s.edge_type NOT IN (1425)", fixed = TRUE)

  sql <- .frs_point_snap_sql(pts_sql, col_id = "id_point",
                             exclude_edge_types = NULL)
  expect_no_match(sql, "edge_type")
})

test_that("snap SQL projects the network position and watershed group", {
  sql <- .frs_point_snap_sql(pts_sql, col_id = "id_point")
  select <- sql_select(sql)
  cols_out <- c("linear_feature_id", "blue_line_key",
                "downstream_route_measure", "watershed_group_code",
                "wscode_ltree", "localcode_ltree", "gnis_name",
                "distance_to_stream", "geom")
  for (col in cols_out) {
    expect_match(select, paste0("  c.", col, ",?\n"))
  }
  expect_match(select, 'c.id AS "id_point"', fixed = TRUE)
  expect_match(sql_lateral(sql), "CEIL\\(GREATEST.*FLOOR\\(LEAST")
})

test_that("hint and stream order filters land in the lateral", {
  sql <- .frs_point_snap_sql(pts_sql, col_id = "id_point")
  expect_no_match(sql, "p.hint")
  expect_no_match(sql, "stream_order >=")

  lateral <- sql_lateral(.frs_point_snap_sql(
    pts_sql, col_id = "id_point", has_hint = TRUE, stream_order_min = 4))
  expect_match(lateral, "(p.hint IS NULL OR s.blue_line_key = p.hint)",
               fixed = TRUE)
  expect_match(lateral, "s.stream_order >= 4", fixed = TRUE)
})

test_that("candidate_rank only when num_features > 1, outside the lateral", {
  sql <- .frs_point_snap_sql(pts_sql, col_id = "id_point")
  expect_no_match(sql, "candidate_rank")

  sql <- .frs_point_snap_sql(pts_sql, col_id = "id_point", num_features = 3)
  lateral <- sql_lateral(sql)
  expect_match(lateral, "LIMIT 3\\b")
  expect_match(sql_select(sql), paste0(
    "row_number\\(\\) OVER \\(PARTITION BY c\\.id ",
    "ORDER BY c\\.distance_to_stream, c\\.linear_feature_id\\) ",
    "AS candidate_rank"))
  expect_no_match(lateral, "row_number")
})

test_that("snap SQL reads table and columns from .frs_opt()", {
  withr::local_options(fresh.tbl_network = "net.channels",
                       fresh.blk_col = "channel_key")
  lateral <- sql_lateral(
    .frs_point_snap_sql(pts_sql, col_id = "id_point", has_hint = TRUE))
  expect_match(lateral, "net.channels s", fixed = TRUE)
  expect_match(lateral, "s.channel_key AS blue_line_key", fixed = TRUE)
  expect_match(lateral, "s.channel_key = p.hint", fixed = TRUE)
})

test_that("tolerance renders locale-safe", {
  withr::local_options(OutDec = ",")
  lateral <- sql_lateral(
    .frs_point_snap_sql(pts_sql, col_id = "id_point", tolerance = 150.5))
  expect_match(lateral, "p.geom, 150.5)", fixed = TRUE)
})

# -- .frs_db_write_temp() ------------------------------------------------------

test_that(".frs_db_write_temp writes a temporary table with a unique name", {
  calls <- list()
  local_mocked_bindings(
    dbWriteTable = function(conn, name, value, ...) {
      calls[[length(calls) + 1L]] <<- list(name = name, args = list(...))
      TRUE
    },
    .package = "DBI"
  )
  df <- data.frame(id = 1:2, x = c(1, 2), y = c(3, 4))
  a <- .frs_db_write_temp("mock", df)
  b <- .frs_db_write_temp("mock", df)
  expect_match(a, "^frs_tmp_[a-z0-9_]+$")
  expect_false(identical(a, b))
  expect_true(calls[[1]]$args$temporary)
  expect_identical(calls[[1]]$name, a)
})

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
