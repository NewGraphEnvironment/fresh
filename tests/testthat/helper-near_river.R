# Synthetic network for the near_river walk (#259), in pg_temp. Needs a
# connection with the fwapg functions (FWA_Downstream) but no FWA rows.
#
# Each segment runs x = x0 .. x0 + len at height y (default 0), or along
# `geom` (WKT, downstream end first) where given, so straight-line and
# network distance agree along the path the fixtures lay out. `scale`
# shrinks the geometry but not length_metre: at 0.01 the straight-line
# prefilter passes everything and only the network distance decides.

.nr_seg <- function(id, blk, ws, lc = ws, drm, len, edge = 1000L, wbk = NA,
                    mad = NA, x0 = drm, cw = 1, gradient = 0.01,
                    wsg = "TEST", y = 0, wk = blk, geom = NA_character_) {
  data.frame(id = id, blk = blk, ws = ws, lc = lc, drm = drm, len = len,
             edge = edge, wbk = wbk, mad = mad, x0 = x0, cw = cw,
             gradient = gradient, wsg = wsg, y = y, wk = wk, geom = geom)
}

.nr_fixture <- function(conn, segs, tbl = "pg_temp.nr_streams", scale = 1) {
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE %s (
      id_segment integer, linear_feature_id bigint,
      blue_line_key integer, watershed_key integer,
      downstream_route_measure double precision,
      length_metre double precision, gradient double precision,
      channel_width double precision, mad_m3s double precision,
      edge_type integer, wscode_ltree ltree, localcode_ltree ltree,
      waterbody_key integer, watershed_group_code character varying(4),
      geom geometry(LineString, 3005))", tbl))
  num <- function(x) if (is.na(x)) "NULL" else format(x, scientific = FALSE)
  for (i in seq_len(nrow(segs))) {
    r <- segs[i, ]
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO %s VALUES (%d, %d, %d, %d, %s, %s, %s, %s, %s, %d,
         '%s'::ltree, %s, %s, '%s', %s)",
      tbl, r$id, r$id, r$blk, r$wk, num(r$drm), num(r$len), num(r$gradient),
      num(r$cw), num(r$mad), r$edge, r$ws,
      if (is.na(r$lc)) "NULL" else sprintf("'%s'::ltree", r$lc),
      num(r$wbk), r$wsg,
      if (!is.na(r$geom)) {
        sprintf("ST_Scale(ST_GeomFromText('%s', 3005), %s, %s)", r$geom,
                num(scale), num(scale))
      } else {
        sprintf(
          "ST_SetSRID(ST_MakeLine(ST_MakePoint(%s, %s), ST_MakePoint(%s, %s)), 3005)",
          num(r$x0 * scale), num(r$y * scale), num((r$x0 + r$len) * scale),
          num(r$y * scale))
      }))
  }
  invisible(tbl)
}

# A river (blue_line_key 1, wscode 100) drawn as polygon 7 at 5 m3/s, and a
# tributary (blue_line_key 2, wscode 100.500) entering it at x = 2000 by a
# 100 m connector. Bank distances at 3 m3/s from each tributary row's
# downstream end: t1 0, t2 400, t3 900, t4 1900, t5 2900 (centreline + 100).
.nr_tributary <- function(t2_mad = 0.2) {
  rbind(
    .nr_seg(1, 1, "100", "100.400", 0, 1000, 1250L, 7, 5),
    .nr_seg(2, 1, "100", "100.400", 1000, 1000, 1250L, 7, 5),
    .nr_seg(3, 1, "100", "100.600", 2000, 1000, 1250L, 7, 5, x0 = 9000),
    .nr_seg(10, 2, "100.500", drm = 0, len = 100, edge = 1450L, wbk = 7,
            mad = 0.2, x0 = 2000),
    .nr_seg(11, 2, "100.500", drm = 100, len = 400, mad = 0.2, x0 = 2100),
    .nr_seg(12, 2, "100.500", drm = 500, len = 500, mad = t2_mad, x0 = 2500),
    .nr_seg(13, 2, "100.500", drm = 1000, len = 1000, mad = 0.2, x0 = 3000),
    .nr_seg(14, 2, "100.500", drm = 2000, len = 1000, mad = 0.2, x0 = 4000),
    .nr_seg(15, 2, "100.500", drm = 3000, len = 1000, x0 = 5000))
}

# A small river (blue_line_key 2) drawn as polygon 5 at 1 m3/s, entering
# polygon 7 by a 100 m connector, and a sub-tributary (blue_line_key 3)
# entering polygon 5 by a 50 m connector. From u1's downstream end: polygon
# 5's bank at 0, polygon 7's bank at 550 (polygon 5's connector stays).
.nr_passthrough <- function() {
  rbind(
    .nr_seg(1, 1, "100", "100.400", 0, 1000, 1250L, 7, 5),
    .nr_seg(20, 2, "100.500", drm = 0, len = 100, edge = 1450L, wbk = 7,
            mad = 1, x0 = 1000),
    .nr_seg(21, 2, "100.500", drm = 100, len = 500, edge = 1250L, wbk = 5,
            mad = 1, x0 = 1100),
    .nr_seg(30, 3, "100.500.300", drm = 0, len = 50, edge = 1450L, wbk = 5,
            mad = 0.1, x0 = 1600),
    .nr_seg(31, 3, "100.500.300", drm = 50, len = 500, mad = 0.1, x0 = 1650))
}

.nr_dist <- function(conn, to = "pg_temp.nr_near", q = 3, d = NULL) {
  d <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, dist_m FROM %s WHERE discharge_min = %s%s
     AND watershed_group_code = 'TEST' ORDER BY id_segment", to, q,
    if (is.null(d)) "" else sprintf(" AND distance_max = %s", d)))
  stats::setNames(d$dist_m, d$id_segment)
}

# A tributary (blue_line_key 2, at y = 100) whose connector across polygon
# 7 is a side line (blue_line_key 99, 100 m), which the walk drops: from
# t1's downstream end the walk jumps 100 m to the river's centreline.
# Bank distances: t1 0, t2 400 (centreline 100 and 500).
.nr_sideline <- function() {
  rbind(
    .nr_seg(1, 1, "100", "100.400", 0, 1000, 1250L, 7, 5),
    .nr_seg(2, 1, "100", "100.400", 1000, 1000, 1250L, 7, 5),
    .nr_seg(40, 99, "100.500", NA, drm = 0, len = 100, edge = 1450L, wbk = 7,
            mad = 0.2, x0 = 1500, wk = 2),
    .nr_seg(41, 2, "100.500", drm = 100, len = 400, mad = 0.2, x0 = 1500,
            y = 100),
    .nr_seg(42, 2, "100.500", drm = 500, len = 500, mad = 0.2, x0 = 1900,
            y = 100))
}

# A tributary whose mouth is 2 km from the only river row on the table:
# the river between them is outside the table. t1 2000, t2 2500.
.nr_offtable <- function() {
  rbind(
    .nr_seg(1, 1, "100", "100.400", 0, 1000, 1250L, 7, 5),
    .nr_seg(51, 2, "100.500", drm = 0, len = 500, mad = 0.2, x0 = 3000),
    .nr_seg(52, 2, "100.500", drm = 500, len = 500, mad = 0.2, x0 = 3500))
}

# Polygons for the bank rule, in place of FWA's: one box per waterbody_key.
# Point the walk at them with
# local_mocked_bindings(.frs_near_river_polygons = function() "pg_temp.nr_polys").
.nr_polys <- function(conn, boxes) {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_polys")
  DBI::dbExecute(conn, "CREATE TABLE pg_temp.nr_polys (
    waterbody_key integer, geom geometry(Polygon, 3005))")
  for (b in boxes) {
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO pg_temp.nr_polys VALUES (%d, ST_MakeEnvelope(%s, %s, %s, %s, 3005))",
      b$wbk, b$x0, b$y0, b$x1, b$y1))
  }
  invisible("pg_temp.nr_polys")
}
