# Synthetic network for the near_river walk (#259), in pg_temp. Needs a
# connection with the fwapg functions (FWA_Downstream) but no FWA rows.
#
# Each segment runs x = x0 .. x0 + len at y = 0, so straight-line and
# network distance agree along the path the fixtures lay out. `scale`
# shrinks the geometry but not length_metre: at 0.01 the straight-line
# prefilter passes everything and only the network distance decides.

.nr_seg <- function(id, blk, ws, lc = ws, drm, len, edge = 1000L, wbk = NA,
                    mad = NA, x0 = drm, cw = 1, gradient = 0.01,
                    wsg = "TEST") {
  data.frame(id = id, blk = blk, ws = ws, lc = lc, drm = drm, len = len,
             edge = edge, wbk = wbk, mad = mad, x0 = x0, cw = cw,
             gradient = gradient, wsg = wsg)
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
         '%s'::ltree, '%s'::ltree, %s, '%s',
         ST_SetSRID(ST_MakeLine(ST_MakePoint(%s, 0), ST_MakePoint(%s, 0)), 3005))",
      tbl, r$id, r$id, r$blk, r$blk, num(r$drm), num(r$len), num(r$gradient),
      num(r$cw), num(r$mad), r$edge, r$ws, r$lc, num(r$wbk), r$wsg,
      num(r$x0 * scale), num((r$x0 + r$len) * scale)))
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

.nr_dist <- function(conn, to = "pg_temp.nr_near", q = 3) {
  d <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, dist_m FROM %s WHERE discharge_min = %s
     AND watershed_group_code = 'TEST' ORDER BY id_segment", to, q))
  stats::setNames(d$dist_m, d$id_segment)
}
