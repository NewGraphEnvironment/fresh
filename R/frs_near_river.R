#' Distance from Each Segment Down to the Nearest River
#'
#' For every segment of a segmented streams table whose own discharge is
#' below a threshold, walks the network downstream and records the
#' distance to the nearest segment carrying at least that discharge. A
#' habitat rule's `near_river` condition reads the result, so a small
#' stream close to a large river can pass a rule whose size test it
#' fails (see [frs_habitat_predicates()]). [frs_habitat_classify()]
#' calls this itself when a rule asks; call it directly to inspect the
#' distances.
#'
#' The walk follows main flow (`blue_line_key = watershed_key`), as the
#' other downstream traces in fresh do, so a side channel starts on the
#' main stem below it.
#'
#' **Where the distance starts and ends.**
#' - It starts at the segment's **downstream end**, so a long segment
#'   whose lower end is within the distance passes whole.
#' - It ends at the bank of the river, not at its centreline. Where a
#'   tributary meets a river drawn as a polygon, its line crosses the
#'   polygon as a connector (FWA edge types 1400 and 1450) to the
#'   centreline. A connector carries the tributary's own small flow, so
#'   it is never a target, and the connector inside the target's polygon
#'   (same `waterbody_key`) is left out of the distance. FWA draws about a
#'   third of connectors as side lines, which the walk does not follow;
#'   the walk then jumps from the tributary's mouth to the centreline, and
#'   that jump is left out too. A connector inside a polygon the walk only
#'   passes through, because that river is too small, stays in the
#'   distance.
#' - Any other jump between consecutive rows of the path is counted at
#'   its straight length: a side channel the walk does not follow, or a
#'   stretch of river outside `table` that the path leaves and re-enters.
#'
#' **Which segments are measured.** Only segments whose own `mad_m3s` is
#' NULL or below `discharge_min` get a row: a river large enough to be a
#' target passes or fails on its own size test, never on its distance to
#' itself. A segment with NULL `mad_m3s` is never a target.
#'
#' **Limits.**
#' - The walk sees only `table`. A working table holds one watershed
#'   group, so a river beyond the group's outlet is not found. The
#'   count of segments whose walk ended within reach (at the outlet, or
#'   the sea) is reported when `verbose`.
#' - A segment with no local watershed code (`localcode_ltree` NULL),
#'   which is most side channels (edge types 1100, 1150, 1350), has no
#'   place in `FWA_Downstream()`'s ordering. It never walks, so it gets
#'   no row and never passes on `near_river`. Their count is reported
#'   when `verbose`.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Schema-qualified segmented streams table with
#'   `id_segment`, `watershed_group_code`, `blue_line_key`,
#'   `watershed_key`, `downstream_route_measure`, `wscode_ltree`,
#'   `localcode_ltree`, `edge_type`, `waterbody_key`, `length_metre`,
#'   `mad_m3s` and `geom`.
#' @param to Character. Schema-qualified output table, created if it does
#'   not exist, with columns `id_segment`, `watershed_group_code`,
#'   `discharge_min` and `dist_m`. Rows for the watershed groups in
#'   `table` are replaced on every call; other groups' rows are kept.
#' @param discharge_min Numeric vector. River discharges to find (m3/s),
#'   each finite, above zero and distinct.
#' @param distance_max Numeric vector, one per `discharge_min`. Farthest
#'   distance (m) to record at that discharge.
#' @param verbose Logical. Print rows written, segments whose walk ended
#'   within reach, segments with no local code, and timing. Default
#'   `TRUE`.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Segments within 1 km of a river carrying 3 m3/s, BULK working table
#' frs_near_river(conn, "working_bulk.streams", "working_bulk.near_river",
#'   discharge_min = 3, distance_max = 1000)
#'
#' DBI::dbGetQuery(conn, "
#'   SELECT count(*) AS n, round(avg(dist_m)) AS mean_m
#'   FROM working_bulk.near_river WHERE discharge_min = 3")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_near_river <- function(conn, table, to, discharge_min, distance_max,
                           verbose = TRUE) {
  .frs_validate_identifier(table, "streams table")
  .frs_validate_identifier(to, "output table")
  ok_num <- function(x) {
    is.numeric(x) && length(x) > 0 && all(is.finite(x)) && all(x > 0)
  }
  if (!ok_num(discharge_min) || anyDuplicated(discharge_min)) {
    stop("discharge_min must be distinct finite numbers above zero",
         call. = FALSE)
  }
  if (!ok_num(distance_max) || length(distance_max) != length(discharge_min)) {
    stop(paste0("distance_max must be finite numbers above zero, one per ",
                "discharge_min"), call. = FALSE)
  }
  cols_need <- c("id_segment", "watershed_group_code", "blue_line_key",
                 "watershed_key", "downstream_route_measure", "wscode_ltree",
                 "localcode_ltree", "edge_type", "waterbody_key",
                 "length_metre", "mad_m3s", "geom")
  cols_have <- names(DBI::dbGetQuery(conn,
    sprintf("SELECT * FROM %s LIMIT 0", table)))
  missing <- setdiff(cols_need, cols_have)
  if (length(missing) > 0) {
    stop(sprintf("%s has no %s column%s (frs_near_river() needs %s)",
                 table, paste(missing, collapse = ", "),
                 if (length(missing) > 1) "s" else "",
                 if ("mad_m3s" %in% missing)
                   "mad_m3s, joined by frs_network_segment() or frs_col_join()"
                 else "the columns frs_network_segment() writes"),
         call. = FALSE)
  }

  t0 <- proc.time()
  walk_tbl <- "pg_temp.frs_near_river_walk"
  on.exit(.frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", walk_tbl)),
          add = TRUE)

  # The straight-line prefilter prunes the join only with a GiST on geom,
  # and the plan needs current statistics (see .frs_bucket_connected()).
  tbl_name <- utils::tail(strsplit(table, ".", fixed = TRUE)[[1]], 1)
  .frs_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS %s_geom_gist_idx ON %s USING gist (geom)",
    tbl_name, table))
  .frs_db_execute(conn, sprintf("ANALYZE %s", table))

  # The longest connector runs a path can subtract, on its own lines (main
  # flow) and as a jump across a side-line connector, so the cap and the
  # prefilter reach every target whose bank distance is within range.
  lens <- DBI::dbGetQuery(conn, sprintf(
    "SELECT coalesce(max(l) FILTER (WHERE main), 0)::double precision AS on_path,
       coalesce(max(l) FILTER (WHERE NOT main), 0)::double precision AS side
     FROM (SELECT blue_line_key = watershed_key AS main,
             sum(length_metre) AS l FROM %s
           WHERE edge_type IN (1400, 1450) AND waterbody_key IS NOT NULL
           GROUP BY waterbody_key, blue_line_key, watershed_key) x", table))
  conn_max <- lens$on_path + lens$side
  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", walk_tbl))
  .frs_db_execute(conn, .frs_near_river_walk_sql(
    table, walk_tbl, discharge_min, distance_max, conn_max,
    entry_max = lens$side))

  .frs_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s (
       id_segment integer,
       watershed_group_code character varying(4),
       discharge_min double precision,
       dist_m double precision)", to))
  to_name <- utils::tail(strsplit(to, ".", fixed = TRUE)[[1]], 1)
  .frs_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS %s_seg_idx ON %s
       (id_segment, watershed_group_code, discharge_min)", to_name, to))
  .frs_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS %s_wsg_idx ON %s (watershed_group_code)",
    to_name, to))
  # A custom AOI need not be one group, so delete every group the table holds.
  .frs_db_execute(conn, sprintf(
    "DELETE FROM %s WHERE watershed_group_code IN (
       SELECT DISTINCT watershed_group_code FROM %s)", to, table))
  .frs_db_execute(conn, sprintf(
    "INSERT INTO %s (id_segment, watershed_group_code, discharge_min, dist_m)
     SELECT origin_id, watershed_group_code, discharge_min, dist_m
     FROM %s WHERE discharge_min IS NOT NULL", to, walk_tbl))

  if (verbose) {
    stats <- DBI::dbGetQuery(conn, sprintf(
      "SELECT q.discharge_min,
         count(hit.origin_id)::int AS near,
         count(*) FILTER (WHERE hit.origin_id IS NULL
           AND o.localcode_ltree IS NOT NULL
           AND coalesce(e.dist_m, 0) < q.distance_max + %s)::int AS ended,
         count(*) FILTER (WHERE o.localcode_ltree IS NULL)::int AS nocode
       FROM %s o
       CROSS JOIN (VALUES %s) AS q(discharge_min, distance_max)
       LEFT JOIN %s hit ON hit.origin_id = o.id_segment
         AND hit.discharge_min = q.discharge_min
       LEFT JOIN %s e ON e.origin_id = o.id_segment
         AND e.discharge_min IS NULL
       WHERE o.mad_m3s IS NULL OR o.mad_m3s < q.discharge_min
       GROUP BY q.discharge_min ORDER BY q.discharge_min",
      .frs_sql_num(conn_max), table,
      .frs_near_river_values(discharge_min, distance_max),
      walk_tbl, walk_tbl))
    for (i in seq_len(nrow(stats))) {
      cat("  Near river >= ", stats$discharge_min[i], " m3/s: ",
          stats$near[i], " segments within ",
          distance_max[match(stats$discharge_min[i], discharge_min)],
          " m; ", stats$ended[i],
          " walks ended within reach (group outlet or the sea); ",
          stats$nocode[i], " with no local code did not walk\n", sep = "")
    }
    cat("  Near river walk: ",
        round((proc.time() - t0)["elapsed"], 1), "s\n", sep = "")
  }

  invisible(conn)
}


#' VALUES rows of (discharge_min, distance_max) as double precision
#'
#' Both numbers go through `.frs_sql_num()`, the formatter the
#' `near_river` predicate uses, so the stored `discharge_min` and the
#' predicate's literal are the same text.
#'
#' @noRd
.frs_near_river_values <- function(discharge_min, distance_max) {
  paste(sprintf("(%s::double precision, %s::double precision)",
                vapply(discharge_min, .frs_sql_num, character(1)),
                vapply(distance_max, .frs_sql_num, character(1))),
        collapse = ", ")
}


#' SQL that builds the near-river walk table
#'
#' One walk serves every discharge: origins are the rows below the
#' largest `discharge_min`, joined to every main-flow row downstream
#' within `max(distance_max) + conn_max` (straight line, then along the
#' path). Path order is `wscode_ltree DESC, downstream_route_measure
#' DESC, id_segment DESC`, with explicit row frames.
#'
#' `path_m` is the distance from the origin's downstream end to the point
#' where the walk enters the row: the lengths walked on the rows before
#' it plus every **jump** on the way. The walk enters each row at the
#' point nearest the previous row's downstream end (the origin's, for the
#' first row); a jump is the straight distance to that point, and only
#' the part of a row below it is walked. On a contiguous path every jump
#' is zero and every row is walked whole; where a tributary meets its
#' parent part-way along a row, only the part below the confluence
#' counts. A jump is a stretch
#' the table does not hold: a side-line connector (FWA draws about a
#' third of connectors as side lines, which the main-flow filter drops),
#' a side channel, or the river beyond the group's boundary. Counting
#' it keeps a path that leaves the table and re-enters from reading
#' short, so one discharge and distance gets the same answer whatever
#' else is asked.
#'
#' On the origin's own blue line the measure decides: a row there is on
#' the path only below the origin. `FWA_Downstream()` also accepts a row
#' by its local code alone, and a few FWA lines carry local codes out of
#' step with their measures, which would put a row upstream of the origin
#' on its path.
#'
#' `connector_m` is what the bank rule subtracts for a row in a polygon:
#' the connector rows (1400, 1450) on the path inside the row's own
#' polygon, plus the jumps that land on a row of that polygon and are no
#' longer than `entry_max`, the longest side-line connector run on the
#' table. A longer jump into the polygon (the river re-entering the
#' table) is not subtracted. Bank distance `path_m - connector_m` is
#' clamped at zero against floating-point residue.
#'
#' With `bank = FALSE` nothing is subtracted (centreline distance), and
#' with `jumps = FALSE` as well, jumps are not counted; both exist for
#' the check script's comparison with an independent walk.
#'
#' The table holds, per origin, one row per discharge it found within
#' range (`discharge_min`, `dist_m` = the smallest bank distance to a
#' non-connector row at or above that discharge, for an origin below it)
#' and one row with `discharge_min` NULL whose `dist_m` is how far the
#' capped walk reached (the bottom of its last row).
#'
#' @noRd
.frs_near_river_walk_sql <- function(table, walk_tbl, discharge_min,
                                     distance_max, conn_max, entry_max,
                                     bank = TRUE, jumps = TRUE) {
  # Not counting jumps while subtracting entry jumps would go negative.
  stopifnot(jumps || !bank)
  cap <- .frs_sql_num(max(distance_max) + conn_max)
  ord_bare <- "wscode_ltree DESC, downstream_route_measure DESC, id_segment DESC"
  ord <- "t.wscode_ltree DESC, t.downstream_route_measure DESC, t.id_segment DESC"
  frame <- " ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"
  conn_sql <- if (bank) {
    sprintf(paste0(
      "CASE WHEN waterbody_key IS NULL THEN 0 ELSE SUM(",
      "CASE WHEN edge_type IN (1400, 1450) THEN below_m ELSE 0 END",
      " + CASE WHEN jump_m <= %s THEN jump_m ELSE 0 END) OVER (",
      "PARTITION BY origin_id, waterbody_key ORDER BY %s%s) END"),
      .frs_sql_num(entry_max), ord_bare, frame)
  } else {
    "0"
  }
  sprintf(
    "CREATE TEMP TABLE %s AS
     WITH origins AS (
       SELECT id_segment, watershed_group_code, mad_m3s, blue_line_key,
         downstream_route_measure, wscode_ltree, localcode_ltree, geom
       FROM %s
       WHERE mad_m3s IS NULL OR mad_m3s < %s
     ),
     downstream AS (
       SELECT o.id_segment AS origin_id, o.watershed_group_code,
         o.mad_m3s AS origin_mad, t.id_segment, t.edge_type, t.mad_m3s,
         t.length_metre, t.waterbody_key, t.wscode_ltree,
         t.downstream_route_measure, t.geom,
         coalesce(LAG(ST_StartPoint(t.geom)) OVER (PARTITION BY o.id_segment
           ORDER BY %s), ST_StartPoint(o.geom)) AS prev_pt
       FROM origins o
       INNER JOIN %s t ON FWA_Downstream(
         o.blue_line_key, o.downstream_route_measure,
         o.wscode_ltree, o.localcode_ltree,
         t.blue_line_key, t.downstream_route_measure,
         t.wscode_ltree, t.localcode_ltree)
       WHERE t.blue_line_key = t.watershed_key
         AND (t.blue_line_key <> o.blue_line_key
              OR t.downstream_route_measure < o.downstream_route_measure)
         AND ST_DWithin(t.geom, o.geom, %s)
     ),
     entered AS (
       SELECT origin_id, watershed_group_code, origin_mad, id_segment,
         edge_type, mad_m3s, length_metre, waterbody_key, wscode_ltree,
         downstream_route_measure,
         ST_Distance(prev_pt, geom) AS jump_m,
         length_metre * ST_LineLocatePoint(ST_Force2D(geom),
           ST_Force2D(prev_pt)) AS below_m
       FROM downstream
     ),
     walked AS (
       SELECT origin_id, watershed_group_code, origin_mad, edge_type,
         mad_m3s, below_m,
         SUM(below_m + %s) OVER w - below_m AS path_m,
         %s AS connector_m
       FROM entered
       WINDOW w AS (PARTITION BY origin_id ORDER BY %s%s)
     ),
     capped AS (
       SELECT * FROM walked WHERE path_m <= %s
     )
     SELECT c.origin_id, c.watershed_group_code, q.discharge_min,
       greatest(min(c.path_m - c.connector_m), 0) AS dist_m
     FROM capped c
     INNER JOIN (VALUES %s) AS q(discharge_min, distance_max)
       ON c.mad_m3s >= q.discharge_min
      AND c.edge_type NOT IN (1400, 1450)
      AND (c.origin_mad IS NULL OR c.origin_mad < q.discharge_min)
      AND c.path_m - c.connector_m <= q.distance_max
     GROUP BY c.origin_id, c.watershed_group_code, q.discharge_min
     UNION ALL
     SELECT origin_id, watershed_group_code, NULL::double precision,
       max(path_m + below_m)
     FROM capped GROUP BY origin_id, watershed_group_code",
    walk_tbl, table, .frs_sql_num(max(discharge_min)), ord, table, cap,
    if (jumps) "jump_m" else "0", conn_sql, ord_bare, frame, cap,
    .frs_near_river_values(discharge_min, distance_max))
}
