# Lake / wetland buckets: area-only predicate and connection to spawning
# (fresh#240). Integration tests run on a synthetic network in pg_temp, so
# they need a connection with the fwapg functions (FWA_Downstream) but no
# FWA rows, except the predicate test, which reads one real lake polygon.

# Build pg_temp streams + habitat tables from a segment spec. Each row is a
# 1000 m segment on a straight line: `drm` is its downstream route measure,
# its geometry runs x = drm .. drm + len at y = `y`, so straight-line and
# network distance agree along one blue_line_key. `scale` shrinks the
# geometry but not length_metre: at 0.01 every segment is within a few
# metres of every other, so the straight-line prefilter passes everything
# and only the network-distance cap can decide.
.bkt_fixture <- function(conn, segs, species = "BT", scale = 1) {
  for (t in c("pg_temp.bkt_streams", "pg_temp.bkt_habitat")) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
  }
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE bkt_streams (
      id_segment integer, linear_feature_id bigint,
      blue_line_key integer, watershed_key integer,
      downstream_route_measure double precision,
      length_metre double precision, gradient double precision,
      wscode_ltree ltree, localcode_ltree ltree,
      waterbody_key integer, watershed_group_code text,
      geom geometry(LineString, 3005))")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE bkt_habitat (
      id_segment integer, watershed_group_code text, species_code text,
      accessible boolean, spawning boolean, rearing boolean,
      lake_rearing boolean, wetland_rearing boolean)")
  for (i in seq_len(nrow(segs))) {
    r <- segs[i, ]
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO pg_temp.bkt_streams VALUES (%d, %d, %d, %d, %s, %s, 0.01,
         '%s'::ltree, '%s'::ltree, %s, 'TEST',
         ST_SetSRID(ST_MakeLine(ST_MakePoint(%s, %s), ST_MakePoint(%s, %s)), 3005))",
      r$id, r$id, r$blk, r$blk, r$drm, r$len, r$wscode, r$wscode,
      if (is.na(r$wbk)) "NULL" else r$wbk,
      (r$x0 + r$drm) * scale, r$y * scale,
      (r$x0 + r$drm + r$len) * scale, r$y * scale))
    for (sp in unique(c(species, "CO"))) {
      own <- sp == species
      DBI::dbExecute(conn, sprintf(
        "INSERT INTO pg_temp.bkt_habitat VALUES (%d, 'TEST', '%s', TRUE,
           %s, FALSE, %s, %s)",
        r$id, sp, own && r$spawn, r$lake, r$wet))
    }
  }
}

# Segment spec helper: one row per segment
.bkt_seg <- function(id, drm, wbk = NA, spawn = FALSE, lake = FALSE,
                     wet = FALSE, blk = 1L, wscode = "100", y = 0,
                     len = 1000, x0 = 0) {
  data.frame(id = id, drm = drm, wbk = wbk, spawn = spawn, lake = lake,
             wet = wet, blk = blk, wscode = wscode, y = y, len = len,
             x0 = x0)
}

.bkt_flags <- function(conn, column = "lake_rearing", species = "BT") {
  d <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, %s AS flag FROM pg_temp.bkt_habitat
     WHERE species_code = '%s' ORDER BY id_segment", column, species))
  stats::setNames(d$flag, d$id_segment)
}

.bkt_run <- function(conn, distance_max, column = "lake_rearing") {
  .frs_bucket_connected(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    species = "BT", column = column, distance_max = distance_max,
    verbose = FALSE)
}

# Spawning 1000-2000, gap 2000-3000, lake (two lines) 3000-5000
.bkt_lake_above_spawning <- function() {
  rbind(.bkt_seg(1, 1000, spawn = TRUE), .bkt_seg(2, 2000),
        .bkt_seg(3, 3000, wbk = 11, lake = TRUE),
        .bkt_seg(4, 4000, wbk = 11, lake = TRUE))
}

# Lake (two lines) 1000-3000, gap 3000-4000, spawning 4000-5000
.bkt_lake_below_spawning <- function() {
  rbind(.bkt_seg(1, 1000, wbk = 11, lake = TRUE),
        .bkt_seg(2, 2000, wbk = 11, lake = TRUE),
        .bkt_seg(3, 3000), .bkt_seg(4, 4000, spawn = TRUE))
}

test_that("lake with spawning downstream within distance keeps its bucket", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .bkt_fixture(conn, .bkt_lake_above_spawning())
  .bkt_run(conn, 3000)
  # Both lines of the polygon keep it
  expect_equal(unname(.bkt_flags(conn)[c("3", "4")]), c(TRUE, TRUE))
})

test_that("lake with spawning downstream beyond distance loses its bucket", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .bkt_fixture(conn, .bkt_lake_above_spawning())
  # Spawning starts 1000 m below the outlet
  .bkt_run(conn, 500)
  expect_equal(unname(.bkt_flags(conn)[c("3", "4")]), c(FALSE, FALSE))
})

test_that("lake with spawning upstream within distance keeps its bucket", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .bkt_fixture(conn, .bkt_lake_below_spawning())
  .bkt_run(conn, 3000)
  expect_equal(unname(.bkt_flags(conn)[c("1", "2")]), c(TRUE, TRUE))
})

test_that("lake with spawning upstream beyond distance loses its bucket", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .bkt_fixture(conn, .bkt_lake_below_spawning())
  .bkt_run(conn, 500)
  expect_equal(unname(.bkt_flags(conn)[c("1", "2")]), c(FALSE, FALSE))
})

test_that("the network-distance cap decides when straight-line distance is short", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Folded geometry: the prefilter passes everything, so these results
  # come from the cumulative-length cap alone.
  for (fx in list(above = .bkt_lake_above_spawning,
                  below = .bkt_lake_below_spawning)) {
    lake <- if (identical(fx, .bkt_lake_above_spawning)) c("3", "4") else c("1", "2")
    .bkt_fixture(conn, fx(), scale = 0.01)
    .bkt_run(conn, 500)
    expect_equal(unname(.bkt_flags(conn)[lake]), c(FALSE, FALSE))
    .bkt_fixture(conn, fx(), scale = 0.01)
    .bkt_run(conn, 3000)
    expect_equal(unname(.bkt_flags(conn)[lake]), c(TRUE, TRUE))
  }
})

# Origin choice. Each test sets D between the true distance and the true
# distance plus one segment, so a trace started from the wrong point (the
# top of the lake, the top of a spawning cluster, a tributary instead of
# its parent, one outflow instead of both) lands beyond D and fails.

test_that("the outlet trace starts at the polygon's lowest line", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Spawning starts 1000 m below the outlet; from the lake's top line it
  # would be 2000 m.
  .bkt_fixture(conn, .bkt_lake_above_spawning())
  .bkt_run(conn, 1500)
  expect_equal(unname(.bkt_flags(conn)[c("3", "4")]), c(TRUE, TRUE))
})

test_that("the spawning trace starts at the cluster's lowest segment", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Lake 1000-3000, gap 3000-4000, a two-segment spawning cluster
  # 4000-6000: 1000 m from its bottom, 2000 m from its top segment.
  segs <- rbind(.bkt_seg(1, 1000, wbk = 11, lake = TRUE),
                .bkt_seg(2, 2000, wbk = 11, lake = TRUE),
                .bkt_seg(3, 3000), .bkt_seg(4, 4000, spawn = TRUE),
                .bkt_seg(5, 5000, spawn = TRUE))
  .bkt_fixture(conn, segs)
  .bkt_run(conn, 1500)
  expect_equal(unname(.bkt_flags(conn)[c("1", "2")]), c(TRUE, TRUE))
})

test_that("a cluster spanning a confluence is traced from the parent stream", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Spawning on the mainstem 4000-5000 and on a tributary (100.500000)
  # joining at its top: one cluster. From the mainstem segment the lake
  # is 1000 m down; from the tributary, 2000 m.
  segs <- rbind(.bkt_seg(1, 1000, wbk = 11, lake = TRUE),
                .bkt_seg(2, 2000, wbk = 11, lake = TRUE),
                .bkt_seg(3, 3000), .bkt_seg(4, 4000, spawn = TRUE),
                .bkt_seg(5, 0, spawn = TRUE, blk = 2L, wscode = "100.500000",
                         x0 = 5000))
  .bkt_fixture(conn, segs)
  .bkt_run(conn, 1500)
  expect_equal(unname(.bkt_flags(conn)[c("1", "2")]), c(TRUE, TRUE))
})

test_that("a polygon with two outflows is traced from both", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Wetland 66 has a line on blk 1 (wscode 100, nothing below) and one on
  # blk 3 (wscode 200) with spawning just below it. Only the blk 3 outlet
  # reaches spawning, and it is not the shallower code.
  segs <- rbind(.bkt_seg(1, 3000, wbk = 66, wet = TRUE),
    .bkt_seg(2, 1000, wbk = 66, wet = TRUE, blk = 3L, wscode = "200",
             y = 5000),
    .bkt_seg(3, 0, spawn = TRUE, blk = 3L, wscode = "200", y = 5000))
  .bkt_fixture(conn, segs)
  .bkt_run(conn, 500, column = "wetland_rearing")
  expect_equal(unname(.bkt_flags(conn, "wetland_rearing")[c("1", "2")]),
               c(TRUE, TRUE))
})

test_that("a disconnected lake loses its bucket, a connected one keeps it", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Lake 22 on a separate river (wscode 200) with no spawning on it
  segs <- rbind(.bkt_lake_above_spawning(),
    .bkt_seg(5, 0, wbk = 22, lake = TRUE, blk = 2L, wscode = "200",
             y = 5000),
    .bkt_seg(6, 1000, wbk = 22, lake = TRUE, blk = 2L, wscode = "200",
             y = 5000))
  .bkt_fixture(conn, segs)
  .bkt_run(conn, 1e6)
  f <- .bkt_flags(conn)
  expect_equal(unname(f[c("5", "6")]), c(FALSE, FALSE))
  expect_equal(unname(f[c("3", "4")]), c(TRUE, TRUE))
})

test_that("spawning on the polygon's own line connects at any distance", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  segs <- rbind(.bkt_seg(1, 1000, wbk = 11, lake = TRUE, spawn = TRUE),
                .bkt_seg(2, 2000, wbk = 11, lake = TRUE))
  .bkt_fixture(conn, segs)
  .bkt_run(conn, 1)
  expect_equal(unname(.bkt_flags(conn)), c(TRUE, TRUE))
})

test_that("another watershed group's rows sharing an id_segment are never read or cleared", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # TEST: spawning on blk 1, lake 22 disconnected on blk 2 (ids 2, 3)
  segs <- rbind(.bkt_seg(1, 1000, spawn = TRUE),
    .bkt_seg(2, 0, wbk = 22, lake = TRUE, blk = 2L, wscode = "200", y = 5000),
    .bkt_seg(3, 1000, wbk = 22, lake = TRUE, blk = 2L, wscode = "200",
             y = 5000))
  .bkt_fixture(conn, segs)
  # OTHR rows reuse ids 2 and 3 in a shared habitat table: spawning on 2
  # (must not connect TEST's lake), lake bucket on 3 (must not be cleared)
  DBI::dbExecute(conn, "INSERT INTO pg_temp.bkt_habitat VALUES
    (2, 'OTHR', 'BT', TRUE, TRUE, FALSE, FALSE, FALSE),
    (3, 'OTHR', 'BT', TRUE, FALSE, FALSE, TRUE, FALSE)")
  .bkt_run(conn, 1e6)
  got <- DBI::dbGetQuery(conn, "
    SELECT watershed_group_code AS wsg, id_segment, lake_rearing
    FROM pg_temp.bkt_habitat WHERE species_code = 'BT' AND id_segment IN (2, 3)
    ORDER BY 1, 2")
  expect_equal(got$lake_rearing[got$wsg == "TEST"], c(FALSE, FALSE))
  expect_equal(got$lake_rearing[got$wsg == "OTHR" & got$id_segment == 3], TRUE)
})

test_that("spawning on a sibling tributary does not connect; downstream of it does", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Mainstem (wscode 100) below both confluences carries lake 44; tributary
  # A (100.300000) carries lake 55; tributary B (100.600000) spawning.
  segs <- rbind(
    .bkt_seg(1, 0, wbk = 44, lake = TRUE),
    .bkt_seg(2, 0, wbk = 55, lake = TRUE, blk = 2L, wscode = "100.300000",
             y = 100),
    .bkt_seg(3, 0, spawn = TRUE, blk = 3L, wscode = "100.600000", y = 200))
  .bkt_fixture(conn, segs)
  .bkt_run(conn, 1e6)
  f <- .bkt_flags(conn)
  expect_false(f[["2"]])
  expect_true(f[["1"]])
})

test_that("wetland filter leaves lake_rearing and other species alone", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # A disconnected polygon flagged in both buckets, for BT and CO
  segs <- rbind(.bkt_seg(1, 1000, spawn = TRUE),
    .bkt_seg(2, 0, wbk = 33, lake = TRUE, wet = TRUE, blk = 2L,
             wscode = "200", y = 5000))
  .bkt_fixture(conn, segs)
  .bkt_run(conn, 1e6, column = "wetland_rearing")
  expect_false(.bkt_flags(conn, "wetland_rearing")[["2"]])
  expect_true(.bkt_flags(conn, "lake_rearing")[["2"]])
  expect_true(.bkt_flags(conn, "wetland_rearing", species = "CO")[["2"]])
})

test_that(".frs_run_connectivity filters a bucket only when its rule opts in", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  segs <- rbind(.bkt_seg(1, 1000, spawn = TRUE),
    .bkt_seg(2, 0, wbk = 22, lake = TRUE, wet = TRUE, blk = 2L,
             wscode = "200", y = 5000))
  pf <- data.frame(species_code = "BT", cluster_rearing = FALSE,
                   cluster_spawning = FALSE)
  run <- function(rear_rules) {
    .bkt_fixture(conn, segs)
    .frs_run_connectivity(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
      species = "BT", params = list(BT = list(rules = list(rear = rear_rules))),
      params_fresh = pf, verbose = FALSE)
    c(lake = .bkt_flags(conn)[["2"]],
      wet = .bkt_flags(conn, "wetland_rearing")[["2"]])
  }
  # No requires_connected: unchanged
  expect_equal(run(list(list(waterbody_type = "L", lake_ha_min = 10),
                        list(waterbody_type = "W"))),
               c(lake = TRUE, wet = TRUE))
  # Lake rule opts in, wetland rule does not
  expect_equal(run(list(
    list(waterbody_type = "L", requires_connected = "spawning",
         connected_distance_max = 3000),
    list(waterbody_type = "W"))),
    c(lake = FALSE, wet = TRUE))
})

test_that("a lake on a sub-threshold inflow is in the bucket under cw and mad", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  wbk <- DBI::dbGetQuery(conn,
    "SELECT waterbody_key FROM whse_basemapping.fwa_lakes_poly
     WHERE area_ha >= 50 ORDER BY waterbody_key LIMIT 1")$waterbody_key
  skip_if(length(wbk) == 0, "no FWA lakes loaded")
  DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE bkt_pred AS
     SELECT %s::integer AS waterbody_key, 0.1::double precision AS channel_width,
            0.0001::double precision AS mad_m3s", wbk))
  on.exit(DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.bkt_pred"),
          add = TRUE, after = FALSE)
  sp <- list(species_code = "BT", params_sp = list(
    ranges = list(rear = list(channel_width = c(1.5, 9999),
                              mad_m3s = c(0.021, 9999),
                              gradient = c(0, 0.1))),
    rules = list(rear = list(list(waterbody_type = "L", lake_ha_min = 50)))))
  for (model in c("cw", "mad")) {
    pred <- frs_habitat_predicates(sp, model = model)$lake_rear
    got <- DBI::dbGetQuery(conn, sprintf(
      "SELECT (%s) AS v FROM pg_temp.bkt_pred s", pred))$v
    expect_true(got, info = model)
  }
})
