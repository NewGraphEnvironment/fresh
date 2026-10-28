# A synthetic stream network in pg_temp, shared by the habitat-connectivity
# tests (fresh#240, fresh#242). testthat evaluates each test file in its own
# environment, so a fixture two files need lives here rather than in either.
#
# These tests need a connection with the fwapg functions (FWA_Upstream,
# FWA_Downstream) but no FWA rows: the predicates are pure, so a network made
# up out of whole cloth traverses correctly.

# Segment spec helper: one row per segment. Each is a `len` m segment on a
# straight line, its geometry running x = x0 + drm .. x0 + drm + len at y = `y`,
# so straight-line and network distance agree along one blue_line_key.
.bkt_seg <- function(id, drm, wbk = NA, spawn = FALSE, lake = FALSE,
                     wet = FALSE, blk = 1L, wscode = "100", y = 0,
                     len = 1000, x0 = 0, gradient = 0.01, rear = FALSE,
                     access = TRUE, cw = 10, edge = 1000L) {
  data.frame(id = id, drm = drm, wbk = wbk, spawn = spawn, lake = lake,
             wet = wet, blk = blk, wscode = wscode, y = y, len = len,
             x0 = x0, gradient = gradient, rear = rear, access = access,
             cw = cw, edge = edge)
}

# Empty pg_temp.bkt_streams + pg_temp.bkt_habitat. One DDL, so a fixture built
# from real FWA rows (test-frs_connectivity_wsg.R, where the trace reads the
# real network) has the same table shape as a spec-built one.
.bkt_tables_create <- function(conn) {
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
      channel_width double precision, edge_type integer,
      geom geometry(LineString, 3005))")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE bkt_habitat (
      id_segment integer, watershed_group_code text, species_code text,
      accessible boolean, spawning boolean, rearing boolean,
      lake_rearing boolean, wetland_rearing boolean)")
  invisible(conn)
}

# Build pg_temp.bkt_streams + pg_temp.bkt_habitat from a segment spec.
# `scale` shrinks the geometry but not length_metre: at 0.01 every segment is
# within a few metres of every other, so a straight-line prefilter passes
# everything and only the network-distance cap can decide.
#
# Habitat rows are written for `species` and for every code in
# `species_other`. `spawning` and `rearing` are set only on `species`, so a
# test can assert a pass left another species' habitat alone; the bucket flags
# and `accessible` are set on both, which is what makes
# "wetland filter leaves lake_rearing and other species alone" able to fail.
# `wsg` names the group the rows belong to; .bkt_habitat_add() adds a second
# group's rows on top.
.bkt_fixture <- function(conn, segs, species = "BT", scale = 1,
                         species_other = "CO", wsg = "TEST") {
  .bkt_tables_create(conn)
  for (i in seq_len(nrow(segs))) {
    r <- segs[i, ]
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO pg_temp.bkt_streams VALUES (%d, %d, %d, %d, %s, %s, %s,
         '%s'::ltree, '%s'::ltree, %s, '%s', %s, %d,
         ST_SetSRID(ST_MakeLine(ST_MakePoint(%s, %s), ST_MakePoint(%s, %s)), 3005))",
      r$id, r$id, r$blk, r$blk, r$drm, r$len, r$gradient,
      r$wscode, r$wscode,
      if (is.na(r$wbk)) "NULL" else r$wbk, wsg, r$cw, r$edge,
      (r$x0 + r$drm) * scale, r$y * scale,
      (r$x0 + r$drm + r$len) * scale, r$y * scale))
    for (sp in unique(c(species, species_other))) {
      own <- sp == species
      DBI::dbExecute(conn, sprintf(
        "INSERT INTO pg_temp.bkt_habitat VALUES (%d, '%s', '%s', %s,
           %s, %s, %s, %s)",
        r$id, wsg, sp, r$access,
        own && r$spawn, own && r$rear, r$lake, r$wet))
    }
  }
}

# Add another watershed group's habitat rows, reusing `id_segment` values the
# fixture's own group already uses. `segs` is a spec whose `id` values collide
# on purpose; nothing is added to bkt_streams, which is the point — the other
# group's streams live in its own working table, not this job's.
.bkt_habitat_add <- function(conn, segs, species = "BT", wsg = "OTHR") {
  for (i in seq_len(nrow(segs))) {
    r <- segs[i, ]
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO pg_temp.bkt_habitat VALUES (%d, '%s', '%s', %s, %s, %s,
         %s, %s)",
      r$id, wsg, species, r$access, r$spawn, r$rear, r$lake, r$wet))
  }
}

# One species' flag column, named by id_segment, for one group.
.bkt_flags <- function(conn, column = "lake_rearing", species = "BT",
                       wsg = "TEST") {
  d <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, %s AS flag FROM pg_temp.bkt_habitat
     WHERE species_code = '%s' AND watershed_group_code = '%s'
     ORDER BY id_segment", column, species, wsg))
  stats::setNames(d$flag, d$id_segment)
}
