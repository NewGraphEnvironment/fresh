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

# -- frs_point_snap() input handling (mocked, no DB) ---------------------------

# Capture the snap SQL and the temp-table payload without a database
local_snap_mocks <- function(env = parent.frame()) {
  calls <- new.env()
  calls$sql <- character(0)
  calls$exec <- character(0)
  calls$written <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      calls$sql <- c(calls$sql, sql)
      sf::st_sf(id_point = integer(0),
                geom = sf::st_sfc(crs = 3005))
    },
    .frs_db_execute = function(conn, sql) {
      calls$exec <- c(calls$exec, sql)
      0L
    },
    .frs_db_write_temp = function(conn, df) {
      calls$written <- df
      "frs_tmp_mock"
    },
    .env = env
  )
  calls
}

test_that("the pre-0.40.0 x/y call errors with a migration hint", {
  expect_error(frs_point_snap("mock", x = -126.5, y = 54.5),
               "now takes a dataset")
  expect_error(frs_point_snap("mock", -126.5, 54.5), "now takes a dataset")
  expect_error(frs_point_snap("mock"), "now takes a dataset")
})

test_that("unknown arguments are rejected", {
  expect_error(
    frs_point_snap("mock", data.frame(x = 1, y = 1), tolerence = 5),
    "unused arguments: tolerence")
})

test_that("scalar options are validated", {
  pts <- data.frame(x = 1, y = 1)
  expect_error(frs_point_snap("mock", pts, tolerance = "a"),
               "tolerance must be a single numeric")
  expect_error(frs_point_snap("mock", pts, tolerance = NA),
               "tolerance must be a single numeric")
  expect_error(frs_point_snap("mock", pts, tolerance = 0),
               "tolerance must be positive")
  expect_error(frs_point_snap("mock", pts, num_features = c(1, 2)),
               "num_features must be a single numeric")
  expect_error(frs_point_snap("mock", pts, num_features = 0),
               "num_features must be a finite number of at least 1")
  expect_error(frs_point_snap("mock", pts, num_features = Inf),
               "num_features must be a finite number of at least 1")
  expect_error(frs_point_snap("mock", pts, stream_order_min = "a"),
               "stream_order_min must be a single numeric")
  expect_error(frs_point_snap("mock", pts, srid = NA),
               "srid must be a single numeric")
  expect_error(frs_point_snap("mock", pts, to = "bad name"),
               "invalid characters")
})

test_that("points must be a data frame, sf or table name", {
  expect_error(frs_point_snap("mock", list(x = 1, y = 1)),
               "points must be a data frame, an sf object or a table name")
})

test_that("data frame input needs its coordinate columns", {
  expect_error(frs_point_snap("mock", data.frame(lon = 1, lat = 1)),
               "points must have columns x and y")
  expect_error(
    frs_point_snap("mock", data.frame(x = "a", y = 1)),
    "x and y must be numeric")
  expect_error(frs_point_snap("mock", data.frame(x = numeric(0),
                                                 y = numeric(0))),
               "points has no rows")
})

test_that("col_id must exist, be unique, non-missing and not collide", {
  pts <- data.frame(site = c("a", "b"), x = 1:2, y = 1:2)
  expect_error(frs_point_snap("mock", pts, col_id = "nope"),
               "col_id 'nope' is not a column of points")
  expect_error(frs_point_snap("mock", transform(pts, site = c("a", "a")),
                              col_id = "site"),
               "col_id 'site' must be unique and non-missing")
  expect_error(frs_point_snap("mock", transform(pts, site = c("a", NA)),
                              col_id = "site"),
               "col_id 'site' must be unique and non-missing")
  expect_error(
    frs_point_snap("mock", transform(pts, blue_line_key = 1:2),
                   col_id = "blue_line_key"),
    "collides with an output column")
  expect_error(frs_point_snap("mock", pts, col_id = "si te"),
               "col_id must be a single column name")
})

test_that("col_blk must be a numeric column of points", {
  expect_error(
    frs_point_snap("mock", data.frame(x = 1, y = 1), col_blk = "blk"),
    "col_blk 'blk' is not a column of points")
  expect_error(
    frs_point_snap("mock", data.frame(x = 1, y = 1, blk = "360873822"),
                   col_blk = "blk"),
    "col_blk 'blk' must be numeric")

  expect_error(
    frs_point_snap("mock", data.frame(x = 1:3, y = 1:3, blk = c(1, Inf, 1e20)),
                   col_blk = "blk"),
    "col_blk 'blk' has values that are not a blue_line_key \\(id: 2, 3\\)")

  calls <- local_snap_mocks()
  frs_point_snap("mock", data.frame(x = 1:2, y = 1:2, blk = NA),
                 col_blk = "blk")
  expect_type(calls$written$hint, "double")
})

test_that("a data frame travels as one temp table and one query", {
  calls <- local_snap_mocks()
  pts <- data.frame(site = c("a", "b", "c"), x = c(1, NA, 3),
                    y = c(4, 5, 6), blk = c(10, NA, 30))
  frs_point_snap("mock", pts, col_id = "site", col_blk = "blk",
                 srid = 26909)
  expect_length(calls$sql, 1L)
  expect_identical(names(calls$written), c("id", "x", "y", "hint"))
  expect_identical(calls$written$id, c("a", "b", "c"))
  expect_identical(calls$written$hint, c(10, NA, 30))
  expect_match(calls$sql, "ST_MakePoint(t.x, t.y), 26909)", fixed = TRUE)
  expect_match(calls$sql, "t.x IS NOT NULL AND t.y IS NOT NULL",
               fixed = TRUE)
  expect_match(calls$sql, "FROM frs_tmp_mock t", fixed = TRUE)
  expect_match(calls$sql, 'c.id AS "site"', fixed = TRUE)
  expect_match(calls$sql, "(p.hint IS NULL OR s.blue_line_key = p.hint)",
               fixed = TRUE)
  # temp table dropped on exit
  expect_true(any(grepl("DROP TABLE IF EXISTS frs_tmp_mock", calls$exec)))
})

test_that("out-of-range lon/lat drop with a message instead of failing", {
  calls <- local_snap_mocks()
  pts <- data.frame(site = c("ok", "swapped"), x = c(-126.5, 54.5),
                    y = c(54.5, -126.5))
  expect_message(frs_point_snap("mock", pts, col_id = "site"),
                 "1 point\\(s\\) with lon/lat out of range dropped \\(id: swapped\\)")
  expect_identical(calls$written$x, c(-126.5, NA))
  expect_identical(calls$written$y, c(54.5, NA))

  # Any geographic CRS, and sf input in one (NAD83 here)
  calls <- local_snap_mocks()
  expect_message(frs_point_snap("mock", pts, col_id = "site", srid = 4269),
                 "id: swapped")
  calls <- local_snap_mocks()
  pts_sf <- sf::st_as_sf(pts, coords = c("x", "y"), crs = 4617,
                         na.fail = FALSE)
  expect_message(frs_point_snap("mock", pts_sf, col_id = "site"),
                 "id: swapped")
  expect_identical(calls$written$x, c(-126.5, NA))

  # Projected coordinates are not lon/lat
  calls <- local_snap_mocks()
  expect_no_message(frs_point_snap("mock", data.frame(x = 1e6, y = 1e6),
                                   srid = 3005))
  expect_identical(calls$written$x, 1e6)
})

test_that("an integer64 tolerance renders as its value", {
  skip_if_not_installed("bit64")
  calls <- local_snap_mocks()
  frs_point_snap("mock", data.frame(x = 1, y = 1),
                 tolerance = bit64::as.integer64(150))
  expect_match(calls$sql, "p.geom, 150)", fixed = TRUE)
})

test_that("to cannot be the points table", {
  expect_error(
    frs_point_snap("mock", "working.pts", col_id = "id",
                   to = "Working.PTS"),
    "to must differ from the points table and the network table")
  expect_error(
    frs_point_snap("mock", data.frame(x = 1, y = 1),
                   to = "whse_basemapping.FWA_stream_networks_sp"),
    "to must differ from the points table and the network table")
  withr::local_options(fresh.tbl_network = "net.channels")
  expect_error(
    frs_point_snap("mock", data.frame(x = 1, y = 1), to = "net.channels"),
    "to must differ")
})

test_that("without col_id rows are numbered in id_point", {
  calls <- local_snap_mocks()
  frs_point_snap("mock", data.frame(x = c(1, 2), y = c(3, 4)))
  expect_identical(calls$written$id, 1:2)
  expect_match(calls$sql, 'c.id AS "id_point"', fixed = TRUE)
})

test_that("sf input takes the CRS and coordinates from the geometry", {
  calls <- local_snap_mocks()
  pts <- sf::st_sf(
    site = c("a", "b"),
    geometry = sf::st_sfc(sf::st_point(c(-126.5, 54.5)), sf::st_point(),
                          crs = 4326))
  frs_point_snap("mock", pts, col_id = "site", srid = 3005)
  expect_identical(calls$written$x, c(-126.5, NA))
  expect_identical(calls$written$y, c(54.5, NA))
  expect_match(calls$sql, "ST_MakePoint(t.x, t.y), 4326)", fixed = TRUE)
})

test_that("sf input must be POINT with an EPSG CRS", {
  line <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(0, 0), c(1, 1))), crs = 3005))
  expect_error(frs_point_snap("mock", line), "POINT geometry")
  no_crs <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(0, 0))))
  expect_error(frs_point_snap("mock", no_crs), "no EPSG code")
})

test_that("table input checks ids and SRID in one query, then snaps", {
  calls <- local_snap_mocks()
  checks <- character(0)
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      checks <<- c(checks, sql)
      data.frame(n = 5, n_id = 5, n_srid0 = 0)
    },
    .package = "DBI"
  )
  frs_point_snap("mock", "whse_fish.pscis_assessment_svw",
                 col_id = "stream_crossing_id", col_blk = "blk",
                 num_features = 5, to = "working.snapped")
  expect_length(checks, 1L)
  expect_match(checks, 'count(DISTINCT t."stream_crossing_id")',
               fixed = TRUE)
  expect_null(calls$written)
  expect_length(calls$sql, 0L)
  create <- grep("CREATE TABLE working.snapped AS", calls$exec, value = TRUE)
  expect_length(create, 1L)
  expect_match(create, 'ST_GeometryN(t."geom", 1), 3005)', fixed = TRUE)
  expect_match(create, 't."blk"::bigint AS hint', fixed = TRUE)
  expect_match(create, "FROM whse_fish.pscis_assessment_svw t", fixed = TRUE)
  expect_true(any(grepl("DROP TABLE IF EXISTS working.snapped",
                        calls$exec)))
})

test_that("table input requires col_id and rejects bad ids or SRID 0", {
  expect_error(frs_point_snap("mock", "working.pts"),
               "col_id is required for a table")
  local_snap_mocks()
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      data.frame(n = 5, n_id = 4, n_srid0 = 0)
    },
    .package = "DBI"
  )
  expect_error(frs_point_snap("mock", "working.pts", col_id = "id"),
               "col_id 'id' must be unique and non-missing")
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      data.frame(n = 5, n_id = 5, n_srid0 = 2)
    },
    .package = "DBI"
  )
  expect_error(frs_point_snap("mock", "working.pts", col_id = "id"),
               "SRID 0")
})
# -- live DB tests -------------------------------------------------------------

# Three sites 170-280 m off their nearest streams (Bulkley area)
sites <- data.frame(
  site = c("a", "b", "c"),
  x = c(-126.5, -126.6, -126.7),
  y = c(54.5, 54.6, 54.4)
)

test_that("one call snaps a dataset and returns its watershed group", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  snapped <- frs_point_snap(conn, sites, col_id = "site", tolerance = 1000)
  expect_s3_class(snapped, "sf")
  expect_equal(sf::st_crs(snapped)$epsg, 3005L)
  expect_setequal(snapped$site, sites$site)
  expect_false(anyNA(snapped$watershed_group_code))
  expect_false(anyNA(snapped$wscode_ltree))
  expect_true(all(snapped$distance_to_stream <= 1000))
  expect_equal(snapped$downstream_route_measure,
               round(snapped$downstream_route_measure))
  expect_false("candidate_rank" %in% names(snapped))

  # sf input lands on the same positions
  sites_sf <- sf::st_as_sf(sites, coords = c("x", "y"), crs = 4326)
  snapped_sf <- frs_point_snap(conn, sites_sf, col_id = "site",
                               tolerance = 1000)
  expect_equal(snapped_sf$blue_line_key, snapped$blue_line_key)
  expect_equal(snapped_sf$downstream_route_measure,
               snapped$downstream_route_measure)

  # A point already on a stream snaps back to itself at the 100 m default
  on_stream <- sf::st_transform(snapped[1, "site"], 4326)
  resnap <- frs_point_snap(conn, on_stream, col_id = "site")
  expect_equal(resnap$blue_line_key, snapped$blue_line_key[1])
  expect_lt(resnap$distance_to_stream, 1)
})

test_that("a per-row blue_line_key hint constrains only its own row", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  free <- frs_point_snap(conn, sites, col_id = "site", tolerance = 1000)
  blk_b <- free$blue_line_key[free$site == "b"]
  hinted <- transform(sites, blk = c(blk_b, NA, NA))
  snapped <- frs_point_snap(conn, hinted, col_id = "site", col_blk = "blk",
                            tolerance = 50000)
  expect_equal(snapped$blue_line_key[snapped$site == "a"], blk_b)
  expect_equal(snapped$blue_line_key[snapped$site == "b"], blk_b)
  expect_equal(snapped$blue_line_key[snapped$site == "c"],
               free$blue_line_key[free$site == "c"])

  # An all-NA hint column (logical in R) leaves every row unconstrained
  no_hint <- frs_point_snap(conn, transform(sites, blk = NA), col_id = "site",
                            col_blk = "blk", tolerance = 1000)
  expect_equal(no_hint$blue_line_key, free$blue_line_key)
})

test_that("tolerance drops far points and an all-far input returns 0 rows", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  near <- frs_point_snap(conn, sites[1, ], col_id = "site")
  expect_equal(nrow(near), 0L)
  far <- frs_point_snap(conn, sites[1, ], col_id = "site", tolerance = 5000)
  expect_equal(nrow(far), 1L)

  # Open Pacific, nowhere near a stream
  none <- frs_point_snap(conn, data.frame(x = -140, y = 50))
  expect_s3_class(none, "data.frame")
  expect_equal(nrow(none), 0L)
})

test_that("num_features returns ranked candidates per point", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  multi <- frs_point_snap(conn, sites, col_id = "site", tolerance = 1000,
                          num_features = 3)
  expect_true("candidate_rank" %in% names(multi))
  per_site <- split(sf::st_drop_geometry(multi), multi$site)
  for (d in per_site) {
    expect_lte(nrow(d), 3L)
    expect_equal(d$candidate_rank, seq_len(nrow(d)))
    expect_false(is.unsorted(d$distance_to_stream))
  }
})

test_that("a table input writes the snap to `to`", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_snap_pts")
    .frs_test_drop(conn, "working.test_snap_out")
    DBI::dbDisconnect(conn)
  })

  .frs_test_drop(conn, "working.test_snap_pts")
  DBI::dbExecute(conn, paste(
    "CREATE TABLE working.test_snap_pts AS",
    "SELECT v.site_id, ST_Multi(ST_Transform(",
    "  ST_SetSRID(ST_MakePoint(v.x, v.y), 4326), 3005)) AS geom",
    "FROM (VALUES (1, -126.5, 54.5), (2, -126.6, 54.6), (3, -126.7, 54.4))",
    "  v(site_id, x, y)"))

  res <- frs_point_snap(conn, "working.test_snap_pts", col_id = "site_id",
                        tolerance = 1000, to = "working.test_snap_out")
  expect_identical(res, conn)
  out <- DBI::dbGetQuery(conn, paste(
    "SELECT site_id, blue_line_key, downstream_route_measure,",
    "watershed_group_code FROM working.test_snap_out ORDER BY site_id"))
  expect_equal(out$site_id, 1:3)

  from_df <- frs_point_snap(conn, sites, col_id = "site", tolerance = 1000)
  expect_equal(out$blue_line_key, from_df$blue_line_key)
  expect_equal(out$downstream_route_measure,
               from_df$downstream_route_measure)
})
