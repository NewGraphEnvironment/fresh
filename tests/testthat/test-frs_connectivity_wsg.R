# The connectivity passes run per job against a habitat table that may hold
# several watershed groups (one shared `to_habitat`), with only the job's own
# streams table. `id_segment` is unique only within a group, so every habitat
# join has to match `watershed_group_code` too, and every UPDATE has to be
# confined to the groups present in `table` (fresh#242).
#
# Each test asserts that the other group's colliding rows are untouched, or
# that its flags neither rescue nor condemn this group's, or both.
#
# Where a block asserts an expected keep AND an expected strip on this group,
# neither a no-op nor a strip-everything mutant passes it. Not every block can:
# the four that pin a clustering CTE turn on one segment's outcome, and so does
# the lake one, because the mechanism each isolates is a single cluster boundary
# moving. The keep-and-strip pairs live in the four blocks above them, which
# share their fixtures. Do not read the weaker blocks as covering a no-op.
#
# The fixture is tests/testthat/helper-synthetic.R. Segments with
# `wscode = "100"` are all mutually "upstream" under the 4-arg
# `fwa_upstream(a, a, b, b)`, which is TRUE whenever `b <@ a`, equality
# included — so a segment that must be strippable goes on a separate river
# (`wscode = "200"`), which is not a descendant of `100`.

.cwb_run <- function(conn, species = "BT", distance_max = 3000,
                     spawn_connected = NULL, lake_adjacent = FALSE,
                     verbose = FALSE) {
  .frs_connected_waterbody(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    species = species,
    waterbody_poly = "whse_basemapping.fwa_lakes_poly",
    waterbody_ha_min = 1, bridge_gradient = 0.05,
    distance_max = distance_max, spawn_connected = spawn_connected,
    lake_adjacent = lake_adjacent, verbose = verbose)
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

.dfl_run <- function(conn, max_distance = 1500, verbose = FALSE) {
  .frs_distance_filter(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    label_cluster = "spawning", label_connect = "rearing", species = "BT",
    max_distance = max_distance, verbose = verbose)
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
#
# `ORDER BY` on the group pick as well as the pair: an unordered `LIMIT 1` takes
# whatever row the scan reaches first, which moves with heap order, so a failure
# could not be re-run against the pair that produced it.
.cds_pick <- function(conn) {
  d <- DBI::dbGetQuery(conn, "
    WITH g AS (
      SELECT min(watershed_group_code) AS w
      FROM whse_basemapping.fwa_stream_networks_sp),
    cand AS (
      SELECT blue_line_key, wscode_ltree
      FROM whse_basemapping.fwa_stream_networks_sp, g
      WHERE watershed_group_code = g.w
        AND blue_line_key = watershed_key
        AND wscode_ltree IS NOT NULL AND localcode_ltree IS NOT NULL
        AND NOT wscode_ltree <@ '999'
      GROUP BY 1, 2
      HAVING count(*) BETWEEN 3 AND 8)
    SELECT g.w AS wsg, a.blue_line_key AS valid, b.blue_line_key AS invalid
    FROM cand a
    INNER JOIN cand b ON a.blue_line_key < b.blue_line_key
      AND NOT a.wscode_ltree <@ b.wscode_ltree
      AND NOT b.wscode_ltree <@ a.wscode_ltree
    CROSS JOIN g
    ORDER BY 2, 3
    LIMIT 1")
  if (nrow(d) == 0) return(NULL)
  list(wsg = d$wsg[1], valid = d$valid[1], invalid = d$invalid[1])
}

# Copy both streams into the working table, then flag habitat so that the
# `valid` stream carries label_connect on its lowest segment and label_cluster
# just above it, while every segment of the `invalid` stream above its lowest
# carries label_cluster and nothing carries label_connect.
#
# The insert repeats `.cds_pick()`'s own watershed-group and mainstem
# predicates. Without them a blue line crossing a group boundary would
# contribute segments the candidate query never counted, all labelled 'TEST' —
# one population defined twice with different predicates.
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
    WHERE blue_line_key IN (%d, %d)
      AND watershed_group_code = '%s'
      AND blue_line_key = watershed_key",
    blks[["valid"]], blks[["invalid"]], blks[["wsg"]]))
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


# --- verbose counts ---
#
# Every test above passes verbose = FALSE, so none of them executes the
# before/after count queries. Those are aggregates with no join to carry the
# group, so they take `.frs_wsg_in()` instead; unscoped they report the whole
# shared habitat table as the job's own progress. Eight call sites across five
# functions, each its own sprintf() argument list; the four reached from here are
# exercised below. The other four are `frs_habitat_classify()`'s, which writes the
# shared table rather than reading it, and whose count the first pass at this
# missed entirely.

test_that("the verbose progress lines count this job's groups, not the table's", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  say <- function(expr) paste(utils::capture.output(expr), collapse = " ")

  # frs_cluster(): TEST has two rearing rows, one cluster valid and one not;
  # OTHR adds three more rearing rows on colliding ids. Unscoped this reads
  # "(4 rearing remaining)".
  .bkt_fixture(conn, rbind(
    .bkt_seg(1, 2000, spawn = TRUE),
    .bkt_seg(2, 1000, rear = TRUE),
    .bkt_seg(3, 1000, rear = TRUE, blk = 4L, wscode = "400", y = 20000)))
  .bkt_habitat_add(conn, rbind(.bkt_seg(1, 0, rear = TRUE),
                               .bkt_seg(2, 0, rear = TRUE),
                               .bkt_seg(3, 0, rear = TRUE)))
  expect_match(
    say(frs_cluster(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
      label_cluster = "rearing", label_connect = "spawning", species = "BT",
      direction = "upstream", confluence_m = 10, verbose = TRUE)),
    "1 disconnected removed \\(1 rearing remaining", fixed = FALSE)

  # .frs_distance_filter(): TEST has two spawning rows, one beyond the cap;
  # OTHR adds two more. Unscoped this reads "(2 spawning remaining)".
  .bkt_fixture(conn, .dfl_segs())
  .bkt_habitat_add(conn, rbind(.bkt_seg(1, 0, spawn = TRUE),
                               .bkt_seg(3, 0, spawn = TRUE)))
  expect_match(say(.dfl_run(conn, verbose = TRUE)),
               "1 beyond 1500m removed \\(1 spawning remaining")

  # .frs_connected_waterbody(): TEST has two spawning rows, one stripped;
  # OTHR adds one. Unscoped this reads "3 -> 2".
  .bkt_fixture(conn, rbind(
    .bkt_seg(1, 0, spawn = TRUE),
    .bkt_seg(2, 1000, wbk = 11, rear = TRUE),
    .bkt_seg(3, 0, spawn = TRUE, blk = 2L, wscode = "200", y = 5000)))
  .bkt_habitat_add(conn, .bkt_seg(3, 0, spawn = TRUE))
  expect_match(say(.cwb_run(conn, verbose = TRUE)),
               "connected waterbody 2 -> 1")

  # .frs_bucket_connected(): TEST has one lake row, disconnected; OTHR adds
  # one. Unscoped this reads "2 -> 1". Its count had the same gap from #240.
  .bkt_fixture(conn, rbind(
    .bkt_seg(1, 1000, spawn = TRUE),
    .bkt_seg(2, 0, wbk = 22, lake = TRUE, blk = 2L, wscode = "200", y = 5000)))
  .bkt_habitat_add(conn, .bkt_seg(2, 0, lake = TRUE))
  expect_match(
    say(.frs_bucket_connected(conn, "pg_temp.bkt_streams",
      "pg_temp.bkt_habitat", species = "BT", column = "lake_rearing",
      distance_max = 1e6, verbose = TRUE)),
    "lake_rearing connected to spawning within 1e\\+06 m: 1 -> 0")
})


# --- The axis every fixture above holds fixed ---
#
# In each test above, the other group's flag AGREES with this group's on the
# colliding id, so dropping a clustering-CTE predicate only ever duplicates a
# row the CTE already holds — and a duplicate changes nothing, which is why the
# mutation sweep found three of those predicates uncatchable and why the first
# write-up of it called them defence in depth. That reasoning was wrong. When
# the other group says `label_cluster = TRUE` on an id whose own group says
# FALSE, the CTE *gains* a segment: clusters merge, `cluster_minimums` moves,
# and this group's answer changes. These two tests hold that axis instead.

test_that("another group's rearing on an id this group calls FALSE does not move the cluster minimum", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # One mainstem on a multi-label wscode, so the empty-`subpath` confluence
  # boost is not in play. Spawning at drm 0; the rearing segment under test at
  # drm 2000, whose own cluster minimum is 2000 m up and so 1000 m short of
  # spawning under a 500 m cap. Segment 3 sits between them and is NOT rearing
  # for TEST.
  w <- "100.100000"
  segs <- rbind(.bkt_seg(1, 0, spawn = TRUE, wscode = w),
                .bkt_seg(3, 1000, wscode = w),
                .bkt_seg(2, 2000, rear = TRUE, wscode = w))
  .bkt_fixture(conn, segs)
  # OTHR calls id 3 rearing. Without the group on the tmp_clusters join that
  # pulls segment 3 into TEST's cluster, dropping the minimum to drm 1000,
  # from where the trace does reach spawning inside the cap.
  .bkt_habitat_add(conn, .bkt_seg(3, 1000, rear = TRUE))
  frs_cluster(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    label_cluster = "rearing", label_connect = "spawning", species = "BT",
    direction = "both", bridge_gradient = 0.05, bridge_distance = 500,
    confluence_m = 10, verbose = FALSE)

  expect_false(.bkt_flags(conn, "rearing")[["2"]])
})

test_that("the same holds for the upstream direction's clustering CTE", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Same mechanism, the other direction, and here the discriminator is the
  # same-blue-line measure rather than a trace distance. Spawning sits at drm
  # 1500, BELOW the rearing segment's own cluster minimum of 2000, so nothing
  # is upstream of the cluster. Segment 3 is adjacent to it and not rearing for
  # TEST; pulling it in drops the minimum to 1000, and drm 1500 is then above.
  #
  # The spawning row is placed off the line (y = 50) so it does not sit between
  # the two rearing segments geometrically — only rearing rows are clustered,
  # so its geometry is immaterial, and this keeps 2 and 3 adjacent.
  segs <- rbind(.bkt_seg(3, 1000),
                .bkt_seg(2, 2000, rear = TRUE),
                .bkt_seg(1, 1500, len = 100, spawn = TRUE, y = 50))
  .bkt_fixture(conn, segs)
  .bkt_habitat_add(conn, .bkt_seg(3, 1000, rear = TRUE))
  frs_cluster(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    label_cluster = "rearing", label_connect = "spawning", species = "BT",
    direction = "upstream", confluence_m = 10, verbose = FALSE)

  expect_false(.bkt_flags(conn, "rearing")[["2"]])
})

test_that("species = NULL resolves only the species in this job's groups", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Asserted on the progress lines, not on the flags. Once every pass is
  # group-scoped, a species that exists only in another group matches nothing
  # and writes nothing, so the final state is identical whether or not the
  # resolution is scoped — the first version of this test could not fail, which
  # review round 3 measured. What the scoping changes is which species are
  # processed at all, and the visible trace of that is one line per species.
  segs <- rbind(.bkt_seg(1, 2000, spawn = TRUE),
                .bkt_seg(2, 1000, rear = TRUE),
                .bkt_seg(3, 1000, rear = TRUE, blk = 4L, wscode = "400",
                         y = 20000))
  .bkt_fixture(conn, segs, species_other = character(0))
  DBI::dbExecute(conn, "INSERT INTO pg_temp.bkt_habitat VALUES
    (2, 'OTHR', 'CH', TRUE, FALSE, TRUE, FALSE, FALSE)")
  out <- paste(utils::capture.output(
    frs_cluster(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
      label_cluster = "rearing", label_connect = "spawning", species = NULL,
      direction = "upstream", confluence_m = 10, verbose = TRUE)),
    collapse = " ")

  expect_match(out, "BT:", fixed = TRUE)          # in this job's group
  expect_false(grepl("CH:", out, fixed = TRUE))   # only in the other group
  own <- .bkt_flags(conn, "rearing")
  expect_true(own[["2"]])    # and BT really was processed: kept
  expect_false(own[["3"]])   # and stripped
  expect_true(DBI::dbGetQuery(conn, "SELECT rearing FROM pg_temp.bkt_habitat
    WHERE species_code = 'CH' AND watershed_group_code = 'OTHR'")$rearing)
})


test_that("the same holds for the downstream direction's clustering CTE", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  blks <- .cds_pick(conn)
  skip_if(is.null(blks), "no two suitable mainstem blue lines in this database")
  ids <- .cds_fixture(conn, blks)
  b <- ids$b
  skip_if(length(b) < 3, "the invalid stream has fewer than three segments")
  # Re-flag: label_connect on the invalid stream's LOWEST segment, nothing on
  # its second, label_cluster from its third up. The cluster minimum is then
  # the third segment, and the second segment's own length is the gap the trace
  # has to cross to reach the connection.
  DBI::dbExecute(conn, sprintf(
    "UPDATE pg_temp.bkt_habitat SET rearing = FALSE, spawning = FALSE
     WHERE species_code = 'BT' AND id_segment IN (%s)",
    paste(b, collapse = ", ")))
  DBI::dbExecute(conn, sprintf(
    "UPDATE pg_temp.bkt_habitat SET spawning = TRUE
     WHERE species_code = 'BT' AND id_segment = %d", b[1]))
  DBI::dbExecute(conn, sprintf(
    "UPDATE pg_temp.bkt_habitat SET rearing = TRUE
     WHERE species_code = 'BT' AND id_segment IN (%s)",
    paste(b[-(1:2)], collapse = ", ")))
  # Cap at exactly the second segment's length: the trace from the third
  # segment reaches the second at distance 0 and the first at that length,
  # which `dist_to_cluster < cap` excludes.
  cap <- DBI::dbGetQuery(conn, sprintf(
    "SELECT length_metre FROM pg_temp.bkt_streams WHERE id_segment = %d",
    b[2]))$length_metre
  skip_if(!length(cap) || !is.finite(cap) || cap <= 0, "no usable segment length")
  # The gradient threshold comes from the data, not a constant. At a fixed
  # `bridge_gradient = 1` a real segment of gradient >= 1 would tie
  # `nearest_barrier` with `nearest_connect`, invalidating the cluster under
  # the defect as well — so the assertion would have held for the wrong reason.
  gmax <- DBI::dbGetQuery(conn,
    "SELECT max(gradient) AS g FROM pg_temp.bkt_streams")$g
  bg <- if (length(gmax) && is.finite(gmax)) gmax + 1 else 1
  # OTHR calls the second segment rearing. Without the group on the clustering
  # CTE it joins TEST's cluster, dropping the minimum one segment and putting
  # the connection within reach.
  .bkt_habitat_add(conn, .bkt_seg(b[2], 0, rear = TRUE))
  frs_cluster(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    label_cluster = "rearing", label_connect = "spawning", species = "BT",
    direction = "downstream", bridge_gradient = bg, bridge_distance = cap,
    verbose = FALSE)

  expect_false(.bkt_flags(conn, "rearing")[[as.character(b[3])]])
})


test_that("another group's spawning does not lend lake adjacency to this group's cluster", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # The fourth site the mutation sweep could not catch, and the reason the
  # first write-up called it unobservable: that argument reasoned only about
  # the wrongly-added stream's own row, which holds for lake_adjacent = FALSE.
  # Under the DEFAULT, lake_adjacent = TRUE, `clustered` / `cluster_geoms` /
  # `valid_clusters` credit a whole cluster for touching the lake, so the added
  # stream lends its adjacency to the rest of its cluster.
  #
  # The geometry runs radially outward from the lake's centroid through a
  # boundary vertex, and is then CHECKED rather than assumed: a line 500 m east
  # of one vertex can sit back inside the polygon, which is how the first
  # version of this fixture quietly credited the segment it meant to exclude.
  # Search for a lake whose shape makes the construction work, rather than
  # taking the first and skipping when it does not: the inner segment has to
  # land within 2 m of a qualifying lake and the outer two outside every one of
  # them, and a radial line from a concave lake can re-enter it.
  lk <- DBI::dbGetQuery(conn, "
    WITH cand AS (
      SELECT ST_StartPoint(ST_ExteriorRing(ST_GeometryN(geom, 1))) AS b,
             ST_Centroid(geom) AS c
      FROM whse_basemapping.fwa_lakes_poly
      WHERE area_ha >= 10 ORDER BY waterbody_key LIMIT 40),
    u AS (
      SELECT ST_X(b) AS bx, ST_Y(b) AS by,
             (ST_X(b) - ST_X(c)) / NULLIF(ST_Distance(b, c), 0) AS ux,
             (ST_Y(b) - ST_Y(c)) / NULLIF(ST_Distance(b, c), 0) AS uy
      FROM cand WHERE ST_Distance(b, c) > 0),
    lines AS (
      SELECT u.*,
        ST_SetSRID(ST_MakeLine(
          ST_MakePoint(bx, by), ST_MakePoint(bx + ux * 500, by + uy * 500)), 3005) AS inner_l,
        ST_SetSRID(ST_MakeLine(
          ST_MakePoint(bx + ux * 500, by + uy * 500),
          ST_MakePoint(bx + ux * 1500, by + uy * 1500)), 3005) AS outer_l,
        ST_SetSRID(ST_MakeLine(
          ST_MakePoint(bx + ux * 30000, by + uy * 30000),
          ST_MakePoint(bx + ux * 31000, by + uy * 31000)), 3005) AS far_l
      FROM u)
    SELECT bx, by, ux, uy FROM lines
    WHERE EXISTS (SELECT 1 FROM whse_basemapping.fwa_lakes_poly lp
                  WHERE lp.area_ha >= 10 AND ST_DWithin(inner_l, lp.geom, 2))
      AND NOT EXISTS (SELECT 1 FROM whse_basemapping.fwa_lakes_poly lp
                      WHERE lp.area_ha >= 10 AND ST_DWithin(outer_l, lp.geom, 2))
      AND NOT EXISTS (SELECT 1 FROM whse_basemapping.fwa_lakes_poly lp
                      WHERE lp.area_ha >= 10 AND ST_DWithin(far_l, lp.geom, 2))
    LIMIT 1")
  skip_if(nrow(lk) == 0,
          "no FWA lake of 10 ha or more whose shape admits this construction")

  .bkt_tables_create(conn)
  # Three segments on one wscode, so each is upstream of the others. Geometry
  # need not agree with the measures: only the clustering and the 2 m
  # adjacency test read it.
  #   4  rearing, at drm 0 so nothing is below it and the Phase 1 trace is empty
  #   6  from the boundary vertex outward, so within 2 m of the lake —
  #      spawning only in the OTHER group
  #   5  further out and adjacent to 6, spawning in THIS group
  pt <- function(d) c(lk$bx + lk$ux * d, lk$by + lk$uy * d)
  add <- function(id, drm, d0, d1, spawn, rear) {
    a <- pt(d0); b <- pt(d1)
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO pg_temp.bkt_streams VALUES (%d, %d, 1, 1, %s, 1000, 0.01,
         '100'::ltree, '100'::ltree, NULL, 'TEST', 10, 1000,
         ST_SetSRID(ST_MakeLine(ST_MakePoint(%.6f, %.6f),
                                ST_MakePoint(%.6f, %.6f)), 3005))",
      id, id, drm, a[1], a[2], b[1], b[2]))
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO pg_temp.bkt_habitat VALUES (%d, 'TEST', 'BT', TRUE, %s, %s,
         FALSE, FALSE)", id, spawn, rear))
  }
  add(4, 0, 30000, 31000, "FALSE", "TRUE")
  add(6, 1000, 0, 500, "FALSE", "FALSE")
  add(5, 2000, 500, 1500, "TRUE", "FALSE")

  # The fixture only tests what it claims if 6 is adjacent to a qualifying lake
  # and 5 is not. Both are measured against every lake, not just the one above.
  # Asserted, not skipped: the search above chose this lake precisely because
  # these hold, so a disagreement here means the search and the build differ.
  near <- function(id) DBI::dbGetQuery(conn, sprintf(
    "SELECT EXISTS (
       SELECT 1 FROM whse_basemapping.fwa_lakes_poly lp
       WHERE lp.area_ha >= 10
         AND ST_DWithin((SELECT geom FROM pg_temp.bkt_streams
                         WHERE id_segment = %d), lp.geom, 2)) AS v", id))$v
  expect_true(near(6))     # within 2 m, so it can lend adjacency
  expect_false(near(5))    # outside, so its own cluster cannot qualify
  expect_false(near(4))
  adj <- DBI::dbGetQuery(conn, "
    SELECT ST_DWithin(a.geom, b.geom, 1) AS v FROM pg_temp.bkt_streams a,
      pg_temp.bkt_streams b WHERE a.id_segment = 5 AND b.id_segment = 6")$v
  expect_true(isTRUE(adj))   # or 6 cannot lend 5 anything

  .bkt_habitat_add(conn, .bkt_seg(6, 1000, spawn = TRUE))
  .frs_connected_waterbody(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    species = "BT", waterbody_poly = "whse_basemapping.fwa_lakes_poly",
    waterbody_ha_min = 10, bridge_gradient = 0.05, distance_max = 1,
    spawn_connected = NULL, lake_adjacent = TRUE, verbose = FALSE)

  # 5 is 500 m out, so its own cluster never qualifies.
  expect_false(.bkt_flags(conn, "spawning")[["5"]])
})
