# The connectivity passes run per job against a habitat table that may hold
# several watershed groups (one shared `to_habitat`), with only the job's own
# streams table. `id_segment` is unique only within a group, so every habitat
# join has to match `watershed_group_code` too, and every UPDATE has to be
# confined to the groups present in `table` (fresh#242).
#
# Each test asserts in both directions: the other group's colliding rows are
# untouched, and the other group's flags neither rescue nor condemn this
# group's. Each also asserts an expected keep AND an expected strip on this
# group, so neither a no-op nor a strip-everything mutant passes.
#
# The fixture is tests/testthat/helper-synthetic.R. Segments with
# `wscode = "100"` are all mutually "upstream" under the 4-arg
# `fwa_upstream(a, a, b, b)`, which is TRUE whenever `b <@ a`, equality
# included — so a segment that must be strippable goes on a separate river
# (`wscode = "200"`), which is not a descendant of `100`.

.cwb_run <- function(conn, species = "BT", distance_max = 3000,
                     spawn_connected = NULL, lake_adjacent = FALSE) {
  .frs_connected_waterbody(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    species = species,
    waterbody_poly = "whse_basemapping.fwa_lakes_poly",
    waterbody_ha_min = 1, bridge_gradient = 0.05,
    distance_max = distance_max, spawn_connected = spawn_connected,
    lake_adjacent = lake_adjacent, verbose = FALSE)
}

test_that("connected_waterbody never clears another group's spawning rows", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # TEST: rearing lake 11 on the mainstem, spawning on the mainstem below it
  # (kept), spawning on a separate river (stripped: not under wscode 100 and
  # no trace reaches it).
  segs <- rbind(
    .bkt_seg(1, 0, spawn = TRUE),
    .bkt_seg(2, 1000, wbk = 11, rear = TRUE),
    .bkt_seg(3, 0, spawn = TRUE, blk = 2L, wscode = "200", y = 5000))
  .bkt_fixture(conn, segs)
  # OTHR reuses id 3 with spawning TRUE. Its own streams live in another job's
  # table, so nothing here may touch it — today the subtractive UPDATE has no
  # group scope at all and wipes it.
  .bkt_habitat_add(conn, .bkt_seg(3, 0, spawn = TRUE))
  .cwb_run(conn)

  own <- .bkt_flags(conn, "spawning")
  expect_true(own[["1"]])                    # kept: upstream of rearing
  expect_false(own[["3"]])                   # stripped: neither phase reaches it
  expect_true(.bkt_flags(conn, "spawning", wsg = "OTHR")[["3"]])
})

test_that("connected_waterbody takes no trace origin from another group's rearing", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # TEST: rearing lake 11 on the mainstem with spawning above it (kept).
  # Lake 22 sits on a separate river with spawning just below it and is NOT
  # rearing for TEST, so that spawning must be stripped.
  segs <- rbind(
    .bkt_seg(1, 1000, wbk = 11, rear = TRUE),
    .bkt_seg(2, 2000, spawn = TRUE),
    .bkt_seg(3, 1000, wbk = 22, blk = 2L, wscode = "200", y = 5000),
    .bkt_seg(4, 0, spawn = TRUE, blk = 2L, wscode = "200", y = 5000))
  .bkt_fixture(conn, segs)
  # OTHR calls id 3 rearing. Today that makes lake 22 a Phase 1 trace origin
  # (and a `rearing_segs` row), which rescues TEST's id 4.
  .bkt_habitat_add(conn, .bkt_seg(3, 1000, rear = TRUE))
  .cwb_run(conn)

  own <- .bkt_flags(conn, "spawning")
  expect_true(own[["2"]])                    # kept: upstream of TEST rearing
  expect_false(own[["4"]])                   # stripped: lake 22 is not rearing here
})

test_that("the additive spawn_connected step promotes no other group's row", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Rearing lake 11, with an accessible non-spawning segment in the downstream
  # trace that meets the permissive spawn_connected thresholds, and one on a
  # separate river that no trace reaches.
  segs <- rbind(
    .bkt_seg(1, 1000, wbk = 11, rear = TRUE),
    .bkt_seg(2, 0),
    .bkt_seg(3, 0, blk = 2L, wscode = "200", y = 5000))
  .bkt_fixture(conn, segs)
  .bkt_habitat_add(conn, .bkt_seg(2, 0))
  .cwb_run(conn, spawn_connected = list(
    gradient_max = 0.05, channel_width_min = 5, edge_types_explicit = 1000))

  own <- .bkt_flags(conn, "spawning")
  expect_true(own[["2"]])                    # promoted: in the trace, meets thresholds
  expect_false(own[["3"]])                   # not promoted: no trace reaches it
  expect_false(.bkt_flags(conn, "spawning", wsg = "OTHR")[["2"]])
})


# --- frs_cluster(direction = "both") ---
#
# Cluster minima sit at drm >= 1000 throughout: below `confluence_m` the
# upstream check also tries `subpath(wscode, 0, -1)`, which on a one-label
# wscode is the empty ltree, and every ltree is its descendant — so the boost
# would validate a cluster from spawning on an unrelated river.

.clb_run <- function(conn, bridge_distance = 10000, species = "BT") {
  frs_cluster(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    label_cluster = "rearing", label_connect = "spawning",
    species = species, direction = "both", bridge_gradient = 0.05,
    bridge_distance = bridge_distance, confluence_m = 10, verbose = FALSE)
}

# One valid cluster and three invalid ones, each isolated on its own river so
# ST_ClusterDBSCAN keeps them apart:
#   A = {2}  valid   — spawning (1) immediately downstream
#   C = {3}  invalid — nothing up or down; (4) is a non-rearing decoy above it
#   D = {5}  invalid — rearing AND spawning on one segment, which is not
#                      upstream of itself under the 8-arg FWA_Upstream
#   E = {6}  invalid — spawning set NULL by the caller below
.clb_segs <- function() {
  rbind(
    .bkt_seg(1, 0, spawn = TRUE),
    .bkt_seg(2, 1000, rear = TRUE),
    .bkt_seg(3, 1000, rear = TRUE, blk = 3L, wscode = "300", y = 10000),
    .bkt_seg(4, 2000, blk = 3L, wscode = "300", y = 10000),
    .bkt_seg(5, 1000, rear = TRUE, spawn = TRUE, blk = 4L, wscode = "400",
             y = 20000),
    .bkt_seg(6, 1000, rear = TRUE, blk = 5L, wscode = "500", y = 30000))
}

test_that("cluster both leaves another group's rows alone and is not rescued by them", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .bkt_fixture(conn, .clb_segs())
  DBI::dbExecute(conn, "UPDATE pg_temp.bkt_habitat SET spawning = NULL
                        WHERE id_segment = 6 AND species_code = 'BT'")
  # OTHR reuses id 3 as rearing (must survive) and id 4 as spawning. Stream 4
  # is upstream of cluster C's minimum, so today that spawning row validates
  # cluster C and TEST's id 3 is kept.
  .bkt_habitat_add(conn, rbind(.bkt_seg(3, 1000, rear = TRUE),
                               .bkt_seg(4, 2000, spawn = TRUE)))
  .clb_run(conn)

  own <- .bkt_flags(conn, "rearing")
  expect_true(own[["2"]])    # valid: spawning downstream within bridge_distance
  expect_false(own[["3"]])   # invalid, and not rescued by OTHR's spawning row
  expect_true(own[["5"]])    # on-spawning segment: protected whatever its cluster
  expect_false(own[["6"]])   # spawning NULL is not protection
  expect_true(.bkt_flags(conn, "rearing", wsg = "OTHR")[["3"]])
})

test_that("another group's rows do not inflate the downstream trace distance", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Spawning at the foot of a 4 km mainstem, rearing at its head: the trace
  # reaches spawning at 2000 m, inside a 2500 m cap.
  segs <- rbind(.bkt_seg(1, 0, spawn = TRUE), .bkt_seg(2, 1000),
                .bkt_seg(3, 2000), .bkt_seg(4, 3000, rear = TRUE))
  .bkt_fixture(conn, segs)
  # OTHR rows on the two intermediate ids carry no flags at all. Today they
  # still duplicate those segments in the trace through a LEFT JOIN on
  # id_segment, so the running length sum reads 4000 m and the cap bites: the
  # bug corrupts this group's own answer, not just the other group's rows.
  .bkt_habitat_add(conn, rbind(.bkt_seg(2, 1000), .bkt_seg(3, 2000)))
  .clb_run(conn, bridge_distance = 2500)

  expect_true(.bkt_flags(conn, "rearing")[["4"]])
})


# --- frs_cluster(direction = "upstream") ---
#
# No phase-1 protection here: upstream mode strips an on-spawning segment in an
# invalid cluster like any other. Cluster D exists so one assertion is decisive
# on its own — cluster C is rescued by the decoy under the current code, which
# masks whether its rows would have been cleared.

test_that("cluster upstream leaves another group's rows alone and is not rescued by them", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  segs <- rbind(
    .bkt_seg(1, 2000, spawn = TRUE),
    .bkt_seg(2, 1000, rear = TRUE),
    .bkt_seg(3, 1000, rear = TRUE, blk = 3L, wscode = "300", y = 10000),
    .bkt_seg(4, 2000, blk = 3L, wscode = "300", y = 10000),
    .bkt_seg(5, 1000, rear = TRUE, blk = 4L, wscode = "400", y = 20000))
  .bkt_fixture(conn, segs)
  # id 4 as spawning: stream 4 is upstream of cluster C, so today it validates
  # that cluster. id 5 as rearing: cluster D is invalid either way, so this is
  # the row the strip reaches today.
  .bkt_habitat_add(conn, rbind(.bkt_seg(4, 2000, spawn = TRUE),
                               .bkt_seg(5, 1000, rear = TRUE)))
  frs_cluster(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    label_cluster = "rearing", label_connect = "spawning", species = "BT",
    direction = "upstream", confluence_m = 10, verbose = FALSE)

  own <- .bkt_flags(conn, "rearing")
  expect_true(own[["2"]])    # valid: spawning upstream on the same blue line
  expect_false(own[["3"]])   # invalid, and not rescued by OTHR's spawning row
  expect_false(own[["5"]])   # invalid
  expect_true(.bkt_flags(conn, "rearing", wsg = "OTHR")[["5"]])
})


# --- .frs_distance_filter() ---
#
# Keeps a `spawning` segment when some `rearing` segment is upstream of it on
# the same blue line at any distance, or within `max_distance` otherwise. A
# segment that must be strippable therefore sits on another blue line, is not
# an ltree descendant of the rearing segment's wscode, and is far away.

.dfl_run <- function(conn, max_distance = 1500) {
  .frs_distance_filter(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    label_cluster = "spawning", label_connect = "rearing", species = "BT",
    max_distance = max_distance, verbose = FALSE)
}

.dfl_segs <- function() {
  rbind(.bkt_seg(1, 1000, rear = TRUE),
        .bkt_seg(2, 2000, spawn = TRUE),
        .bkt_seg(3, 0, spawn = TRUE, blk = 2L, wscode = "200", y = 50000))
}

test_that("distance_filter never clears another group's rows", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .bkt_fixture(conn, .dfl_segs())
  .bkt_habitat_add(conn, .bkt_seg(3, 0, spawn = TRUE))
  .dfl_run(conn)

  own <- .bkt_flags(conn, "spawning")
  expect_true(own[["2"]])    # kept: rearing below it on the same blue line
  expect_false(own[["3"]])   # stripped: 50 km away on another blue line
  expect_true(.bkt_flags(conn, "spawning", wsg = "OTHR")[["3"]])
})

test_that("distance_filter is not rescued by another group's connect rows", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Stream 4 lies 1000 m from segment 3, inside max_distance, but is rearing
  # only in OTHR.
  segs <- rbind(.dfl_segs(),
                .bkt_seg(4, 2000, blk = 3L, wscode = "300", y = 50000))
  .bkt_fixture(conn, segs)
  .bkt_habitat_add(conn, .bkt_seg(4, 2000, rear = TRUE))
  .dfl_run(conn)

  own <- .bkt_flags(conn, "spawning")
  expect_true(own[["2"]])
  expect_false(own[["3"]])
})


# --- frs_cluster(direction = "downstream") ---
#
# This one cannot run on an invented network. Its trace is
# `whse_basemapping.fwa_downstreamtrace(blk, drm)`, which iterates the real
# `fwa_stream_networks_sp`, and `has_connect` matches the traced
# `linear_feature_id` against the working table — so with made-up blue line
# keys the trace returns nothing, every cluster is stripped, and "the pass
# keeps a connected cluster" could not fail. The fixture is therefore built
# from real rows on two mainstem blue lines in different sub-basins, picked at
# run time rather than hardcoded so it survives a different database.
#
# `bridge_gradient = 1` keeps real gradients out of play: the barrier check
# invalidates a cluster whose connection is no nearer than the first steep
# segment, which is a different behaviour under test.

# Two mainstem blue lines with a handful of segments each, neither of them an
# ltree ancestor of the other. That is the condition that matters: a downstream
# trace follows the wscode hierarchy, so it can only meet the other stream if
# that stream's wscode is an ancestor of this one's. Being siblings under one
# sub-basin is fine. The "stripped" assertions below are what would catch a
# pair that turned out to be related after all.
.cds_pick <- function(conn) {
  d <- DBI::dbGetQuery(conn, "
    WITH g AS (
      SELECT watershed_group_code AS w
      FROM whse_basemapping.fwa_stream_networks_sp LIMIT 1),
    cand AS (
      SELECT blue_line_key, wscode_ltree
      FROM whse_basemapping.fwa_stream_networks_sp, g
      WHERE watershed_group_code = g.w
        AND blue_line_key = watershed_key
        AND wscode_ltree IS NOT NULL AND localcode_ltree IS NOT NULL
        AND NOT wscode_ltree <@ '999'
      GROUP BY 1, 2
      HAVING count(*) BETWEEN 3 AND 8)
    SELECT a.blue_line_key AS valid, b.blue_line_key AS invalid
    FROM cand a
    INNER JOIN cand b ON a.blue_line_key < b.blue_line_key
      AND NOT a.wscode_ltree <@ b.wscode_ltree
      AND NOT b.wscode_ltree <@ a.wscode_ltree
    ORDER BY 1, 2
    LIMIT 1")
  if (nrow(d) == 0) return(NULL)
  c(valid = d$valid[1], invalid = d$invalid[1])
}

# Copy both streams into the working table, then flag habitat so that the
# `valid` stream carries label_connect on its lowest segment and label_cluster
# just above it, while every segment of the `invalid` stream above its lowest
# carries label_cluster and nothing carries label_connect.
.cds_fixture <- function(conn, blks, species = "BT") {
  .bkt_tables_create(conn)
  DBI::dbExecute(conn, sprintf("
    INSERT INTO pg_temp.bkt_streams
    SELECT row_number() OVER (ORDER BY blue_line_key, downstream_route_measure),
           linear_feature_id, blue_line_key, watershed_key,
           downstream_route_measure, length_metre, gradient,
           wscode_ltree, localcode_ltree, waterbody_key, 'TEST',
           10, 1000, ST_Force2D(geom)
    FROM whse_basemapping.fwa_stream_networks_sp
    WHERE blue_line_key IN (%d, %d)",
    blks[["valid"]], blks[["invalid"]]))
  segs <- DBI::dbGetQuery(conn, "
    SELECT id_segment, blue_line_key FROM pg_temp.bkt_streams
    ORDER BY blue_line_key, downstream_route_measure")
  a <- segs$id_segment[segs$blue_line_key == blks[["valid"]]]
  b <- segs$id_segment[segs$blue_line_key == blks[["invalid"]]]
  flag <- function(ids, col) {
    if (length(ids) == 0) return(invisible(NULL))
    DBI::dbExecute(conn, sprintf(
      "UPDATE pg_temp.bkt_habitat SET %s = TRUE
       WHERE species_code = '%s' AND id_segment IN (%s)",
      col, species, paste(ids, collapse = ", ")))
  }
  for (i in segs$id_segment) {
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO pg_temp.bkt_habitat VALUES (%d, 'TEST', '%s', TRUE,
         FALSE, FALSE, FALSE, FALSE)", i, species))
  }
  flag(a[1], "spawning")
  flag(a[2], "rearing")
  flag(b[-1], "rearing")
  list(a = a, b = b)
}

.cds_run <- function(conn) {
  frs_cluster(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    label_cluster = "rearing", label_connect = "spawning", species = "BT",
    direction = "downstream", bridge_gradient = 1, bridge_distance = 1e6,
    verbose = FALSE)
}

test_that("cluster downstream never clears another group's rows", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  blks <- .cds_pick(conn)
  skip_if(is.null(blks), "no two suitable mainstem blue lines in this database")
  ids <- .cds_fixture(conn, blks)
  # OTHR reuses one of the invalid stream's clustered ids as rearing.
  .bkt_habitat_add(conn, .bkt_seg(ids$b[2], 0, rear = TRUE))
  .cds_run(conn)

  own <- .bkt_flags(conn, "rearing")
  expect_true(own[[as.character(ids$a[2])]])   # kept: spawning just downstream
  expect_false(own[[as.character(ids$b[2])]])  # stripped: no spawning below
  expect_true(.bkt_flags(conn, "rearing", wsg = "OTHR")[[as.character(ids$b[2])]])
})

test_that("cluster downstream is not rescued by another group's connect rows", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  blks <- .cds_pick(conn)
  skip_if(is.null(blks), "no two suitable mainstem blue lines in this database")
  ids <- .cds_fixture(conn, blks)
  # OTHR calls the invalid stream's lowest segment spawning. That segment is
  # on the trace from the cluster above it, so today has_connect finds it.
  .bkt_habitat_add(conn, .bkt_seg(ids$b[1], 0, spawn = TRUE))
  .cds_run(conn)

  own <- .bkt_flags(conn, "rearing")
  expect_true(own[[as.character(ids$a[2])]])
  expect_false(own[[as.character(ids$b[2])]])
})
