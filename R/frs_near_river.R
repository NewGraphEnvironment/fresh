#' Distance from Each Segment Down to the Nearest River
#'
#' For every segment of a segmented streams table that is smaller than a
#' threshold, walks the network downstream and records the distance to
#' the nearest segment at least that size. Size is one of three measures:
#' mean annual discharge (`mad_m3s`), modelled channel width
#' (`channel_width`) or stream order (`stream_order`). A habitat rule's
#' `near_river` condition reads the result, so a small stream close to a
#' large river can pass a rule whose size test it fails (see
#' [frs_habitat_predicates()]). [frs_habitat_classify()] calls this
#' itself when a rule asks; call it directly to inspect the distances.
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
#'   centreline. A connector belongs to the tributary, so it is never a
#'   target, and the connector inside the target's polygon (same
#'   `waterbody_key`) is left out of the distance. FWA draws about a
#'   third of connectors as side lines, which the walk does not follow;
#'   the walk then jumps from the tributary's mouth to the centreline, and
#'   that jump is left out too. A connector inside a polygon the walk only
#'   passes through, because that river is too small, stays in the
#'   distance.
#' - Any other jump between consecutive rows of the path is counted at
#'   its straight length: a side channel the walk does not follow, or a
#'   stretch of river outside `table` that the path leaves and re-enters.
#' - Where a tributary joins its parent follows FWA's local codes, as in
#'   every downstream trace in fresh. Where a code places the confluence
#'   away from where the lines meet, the distance can differ from a
#'   walk that enters at the nearest point, either way: longer by a
#'   counted jump, or shorter by the stretch between the two points.
#'
#' **Which segments are measured.** Only segments whose own value of the
#' measure is NULL or below `threshold` get a row: a river large enough
#' to be a target passes or fails on its own size test, never on its
#' distance to itself. A segment with a NULL value is never a target.
#'
#' **The three measures differ in what they see.** fwapg's discharge is
#' missing on some main stems (none of BULK's 1,118 river-polygon rows
#' carries one), while channel width is modelled on every river-polygon
#' row and missing mostly on first-order streams, which are origins, not
#' targets. Most lake flow lines carry no width but do carry an order, so
#' under width a lake's line is rarely a river and under order it is.
#' Stream order is topological: an order-5 stream in a dry basin can
#' carry less water than an order-4 one in a wet basin.
#'
#' **Limits.**
#' - The walk sees only `table`. A working table holds one watershed
#'   group, so a river beyond the group's outlet is not found.
#' - To stay fast, the walk joins only rows within `distance_max` (plus
#'   the longest connector run) in a straight line, and cuts the path
#'   where a row it skipped was directly above the next row on that
#'   row's line. A path that jumps out of that reach and comes back in a
#'   way that test cannot see (the skipped run ends a line, or the row
#'   above is out of step with its local code) can read short. It needs
#'   a jump between path rows; none occurs on BULK at 3 m3/s within 1 or
#'   20 km.
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
#'   `geom`, and the column of each measure asked for: `mad_m3s`,
#'   `channel_width` or `stream_order`.
#' @param to Character. Schema-qualified output table, created if it does
#'   not exist, with columns `id_segment`, `watershed_group_code`,
#'   `measure`, `threshold`, `distance_max` and `dist_m`. A `near_river`
#'   rule reads only rows of its own exact measure, threshold and
#'   distance, so build the table with the pairs the rules carry
#'   ([frs_habitat_classify()] does): a walk at a longer distance does
#'   not serve a rule with a shorter one. Rows for the watershed groups
#'   in `table` are replaced on every call; other groups' rows are kept.
#'   A table written by fresh 0.41.0 (with a `discharge_min` column and
#'   no `measure`) stops the call; drop it and re-run.
#' @param threshold Numeric vector. River sizes to find, each finite and
#'   above zero, in the measure's unit: m3/s for `"discharge"`, m for
#'   `"channel_width"`, an order for `"stream_order"`.
#' @param distance_max Numeric vector, one per `threshold`. Farthest
#'   distance (m) to record for that pair. Each pair is walked on its own,
#'   so a pair's distances never depend on the other pairs in the call;
#'   pairs must be distinct.
#' @param measure Character, length 1 or one per `threshold`:
#'   `"discharge"` (default), `"channel_width"` or `"stream_order"`.
#' @param verbose Logical. Print rows written, segments with no local
#'   code, and timing. Default `TRUE`.
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
#'   threshold = 3, distance_max = 1000)
#'
#' # The same, finding the river by a modelled channel width of 20 m
#' frs_near_river(conn, "working_bulk.streams", "working_bulk.near_river",
#'   threshold = 20, distance_max = 1000, measure = "channel_width")
#'
#' DBI::dbGetQuery(conn, "
#'   SELECT measure, threshold, count(*) AS n, round(avg(dist_m)) AS mean_m
#'   FROM working_bulk.near_river GROUP BY 1, 2")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_near_river <- function(conn, table, to, threshold, distance_max,
                           measure = "discharge", verbose = TRUE) {
  measure <- .frs_near_river_check(conn, table, to, threshold, distance_max,
                                   measure)

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

  .frs_near_river_table(conn, to)
  # A custom AOI need not be one group, so delete every group the table holds.
  .frs_db_execute(conn, sprintf(
    "DELETE FROM %s WHERE watershed_group_code IN (
       SELECT DISTINCT watershed_group_code FROM %s)", to, table))
  # One walk per (measure, threshold, distance_max), so each answer is a
  # function of its own numbers: the cap and prefilter come from the pair
  # alone, never from another rule's distance.
  for (i in seq_along(threshold)) {
    q <- threshold[i]
    d <- distance_max[i]
    col <- .frs_near_river_cols()[[measure[i]]]
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", walk_tbl))
    .frs_db_execute(conn, .frs_near_river_walk_sql(
      table, walk_tbl, q, d, conn_max, entry_max = lens$side, col = col))
    .frs_db_execute(conn, sprintf(
      "INSERT INTO %s (id_segment, watershed_group_code, measure, threshold,
         distance_max, dist_m)
       SELECT origin_id, watershed_group_code, %s, threshold,
         %s::double precision, dist_m
       FROM %s", to, .frs_quote_string(measure[i]), .frs_sql_num(d),
      walk_tbl))
    if (verbose) {
      stats <- DBI::dbGetQuery(conn, sprintf(
        "SELECT count(*)::int AS near,
           (SELECT count(*) FROM %s o WHERE o.localcode_ltree IS NULL
              AND (o.%s IS NULL OR o.%s < %s))::int AS nocode
         FROM %s", table, col, col, .frs_sql_num(q), walk_tbl))
      cat("  Near river ", .frs_near_river_label(measure[i], q), ": ",
          stats$near, " segments within ", d, " m; ", stats$nocode,
          " with no local code did not walk\n", sep = "")
    }
  }
  if (verbose) {
    cat("  Near river walk: ",
        round((proc.time() - t0)["elapsed"], 1), "s\n", sep = "")
  }

  invisible(conn)
}


#' Every check frs_near_river() makes before it writes, writing nothing
#'
#' Identifiers, the numbers, the measure, distinct pairs, the columns each
#' measure and the walk read, and the output table's shape. A function of
#' its own so [frs_habitat_classify()] runs the same checks before its
#' first write: a stop inside the walk would come after classify had
#' deleted the group's habitat rows (fresh#263 review).
#'
#' @return `measure`, recycled to one per `threshold`.
#' @noRd
.frs_near_river_check <- function(conn, table, to, threshold, distance_max,
                                  measure = "discharge") {
  .frs_validate_identifier(table, "streams table")
  .frs_validate_identifier(to, "output table")
  ok_num <- function(x) {
    is.numeric(x) && length(x) > 0 && all(is.finite(x)) && all(x > 0)
  }
  if (!ok_num(threshold)) {
    stop("threshold must be finite numbers above zero", call. = FALSE)
  }
  if (!ok_num(distance_max) || length(distance_max) != length(threshold)) {
    stop(paste0("distance_max must be finite numbers above zero, one per ",
                "threshold"), call. = FALSE)
  }
  if (!is.character(measure) || anyNA(measure) ||
      !length(measure) %in% c(1L, length(threshold)) ||
      !all(measure %in% names(.frs_near_river_cols()))) {
    stop(sprintf(paste0("measure must be one of %s, length 1 or one per ",
                        "threshold"),
                 paste0('"', names(.frs_near_river_cols()), '"',
                        collapse = ", ")), call. = FALSE)
  }
  measure <- rep_len(measure, length(threshold))
  if (anyDuplicated(data.frame(measure, threshold, distance_max))) {
    stop("each (measure, threshold, distance_max) pair must be distinct",
         call. = FALSE)
  }
  size_cols <- unname(.frs_near_river_cols()[unique(measure)])
  cols_need <- c("id_segment", "watershed_group_code", "blue_line_key",
                 "watershed_key", "downstream_route_measure", "wscode_ltree",
                 "localcode_ltree", "edge_type", "waterbody_key",
                 "length_metre", size_cols, "geom")
  cols_have <- names(DBI::dbGetQuery(conn,
    sprintf("SELECT * FROM %s LIMIT 0", table)))
  missing <- setdiff(cols_need, cols_have)
  if (length(missing) > 0) {
    stop(sprintf("%s has no %s column%s (frs_near_river() needs %s)",
                 table, paste(missing, collapse = ", "),
                 if (length(missing) > 1) "s" else "",
                 if (any(missing %in% size_cols))
                   paste0("the column of each measure; mad_m3s is joined ",
                          "by frs_network_segment() or frs_col_join()")
                 else "the columns frs_network_segment() writes"),
         call. = FALSE)
  }
  # The walk compares each size column with a number; frs_col_join() types
  # a joined column `text`, which Postgres would refuse mid-walk.
  frame <- DBI::dbGetQuery(conn, sprintf("SELECT %s FROM %s LIMIT 0",
                                         paste(size_cols, collapse = ", "),
                                         table))
  not_num <- size_cols[!vapply(frame[size_cols], is.numeric, logical(1))]
  if (length(not_num) > 0) {
    stop(sprintf(paste0("%s: %s must be numeric, got %s (frs_col_join() ",
                        "types a joined column text; cast it)"), table,
                 paste(not_num, collapse = ", "),
                 paste(vapply(frame[not_num], function(x) class(x)[1],
                              character(1)), collapse = ", ")),
         call. = FALSE)
  }
  .frs_near_river_check_shape(conn, to)
  measure
}


#' Column each near_river measure reads
#'
#' @return Named character vector, measure = column on the streams table.
#' @noRd
.frs_near_river_cols <- function() {
  c(discharge = "mad_m3s", channel_width = "channel_width",
    stream_order = "stream_order")
}


#' A near_river measure and threshold, for messages
#'
#' @noRd
.frs_near_river_label <- function(measure, threshold) {
  switch(measure,
    discharge = sprintf(">= %s m3/s", threshold),
    channel_width = sprintf("channel width >= %s m", threshold),
    stream_order = sprintf("order >= %s", threshold))
}


#' Stop if a near_river output table exists in fresh 0.41.0's shape
#'
#' Writes nothing, so [frs_habitat_classify()] can run it before its first
#' write. `to_regclass()` resolves `to` the way the later statements will.
#'
#' @noRd
.frs_near_river_check_shape <- function(conn, to) {
  .frs_validate_identifier(to, "output table")
  exists <- !is.na(DBI::dbGetQuery(conn, sprintf(
    "SELECT to_regclass(%s)::text AS r", .frs_quote_string(to)))$r)
  if (!exists) return(invisible(to))
  have <- names(DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s LIMIT 0", to)))
  if (!all(c("measure", "threshold") %in% have)) {
    stop(sprintf(paste0(
      "%s has no measure / threshold columns: it was written by fresh ",
      "0.41.0, which measured discharge only. Drop it and re-run (the ",
      "table is rebuilt from the streams table)."), to), call. = FALSE)
  }
  invisible(to)
}


#' Create the near_river output table, refusing the 0.41.0 shape
#'
#' @noRd
.frs_near_river_table <- function(conn, to) {
  .frs_near_river_check_shape(conn, to)
  .frs_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s (
       id_segment integer,
       watershed_group_code character varying(4),
       measure text,
       threshold double precision,
       distance_max double precision,
       dist_m double precision)", to))
  to_name <- utils::tail(strsplit(to, ".", fixed = TRUE)[[1]], 1)
  .frs_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS %s_seg_idx ON %s
       (id_segment, watershed_group_code, measure, threshold, distance_max)",
    to_name, to))
  .frs_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS %s_wsg_idx ON %s (watershed_group_code)",
    to_name, to))
  invisible(to)
}


#' VALUES rows of (threshold, distance_max) as double precision
#'
#' Both numbers go through `.frs_sql_num()`, the formatter the
#' `near_river` predicate uses, so the stored `threshold` and the
#' predicate's literal are the same text.
#'
#' @noRd
.frs_near_river_values <- function(threshold, distance_max) {
  paste(sprintf("(%s::double precision, %s::double precision)",
                vapply(threshold, .frs_sql_num, character(1)),
                vapply(distance_max, .frs_sql_num, character(1))),
        collapse = ", ")
}


#' SQL that builds the near-river walk table
#'
#' One walk per `(threshold, distance_max)` pair (scalars) on one size
#' column `col` (`.frs_near_river_cols()`): origins are the rows whose
#' `col` is NULL or below `threshold`, joined to every main-flow row
#' downstream within `distance_max + conn_max` (straight line, then along
#' the path). Path order is `wscode_ltree DESC, downstream_route_measure
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
#' short.
#'
#' On the origin's own blue line the measure decides: a row there is on
#' the path only below the origin. `FWA_Downstream()` also accepts a row
#' by its local code alone, and a few FWA lines carry local codes out of
#' step with their measures, which would put a row upstream of the origin
#' on its path.
#'
#' `connector_m` is what the bank rule subtracts for a row in a polygon:
#' the connector rows (1400, 1450) on the path inside the row's own
#' polygon, plus, for each jump that lands on a row of that polygon, the
#' part of the jump line inside the polygon (where it crosses the bank),
#' at most `entry_max`, the longest side-line connector run on the table.
#' A jump from a side-line connector's top lies wholly inside; one from a
#' tributary that ends on a side channel crosses dry land first, and
#' that part stays in the distance. The total is capped at `conn_max`,
#' the allowance the cap and prefilter carry, so the cap never drops a
#' row whose bank distance is within `distance_max`. Polygons come from
#' `.frs_near_river_polygons()`. Bank distance `path_m - connector_m` is
#' clamped at zero against floating-point residue.
#'
#' With `bank = FALSE` nothing is subtracted (centreline distance), and
#' with `jumps = FALSE` as well, jumps are not counted; both exist for
#' the check script's comparison with an independent walk.
#'
#' The prefilter drops rows wholly beyond `cap`; on a contiguous path
#' every row after one is beyond `cap` too. A jump can carry the path
#' from a dropped row back within `cap`, so the path is cut at the first
#' row whose neighbour directly above it on its own line is on the path
#' and was dropped. Two shapes that test cannot see can still read
#' short (see [frs_near_river()], Limits); the answer for a pair is
#' still a function of that pair alone, because each pair is walked on
#' its own.
#'
#' The table holds one row per origin that found a river within range
#' (`threshold`, `dist_m` = the smallest bank distance to a
#' non-connector row whose `col` is at or above the threshold, for an
#' origin below it).
#'
#' @noRd
.frs_near_river_walk_sql <- function(table, walk_tbl, threshold,
                                     distance_max, conn_max, entry_max,
                                     bank = TRUE, jumps = TRUE,
                                     col = "mad_m3s") {
  # One pair per walk: the cap and prefilter come from distance_max, so
  # two pairs in one walk would make one answer depend on the other, and
  # the output (grouped by discharge) would merge them.
  stopifnot(length(threshold) == 1L, length(distance_max) == 1L,
            col %in% .frs_near_river_cols())
  # Not counting jumps while subtracting entry jumps would go negative.
  stopifnot(jumps || !bank)
  cap <- .frs_sql_num(max(distance_max) + conn_max)
  ord_bare <- "wscode_ltree DESC, downstream_route_measure DESC, id_segment DESC"
  ord <- "t.wscode_ltree DESC, t.downstream_route_measure DESC, t.id_segment DESC"
  frame <- " ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"
  conn_sql <- if (bank) {
    # least(): the cap and prefilter allow conn_max of subtraction, so the
    # SQL enforces that bound (a path can enter one polygon more than once).
    sprintf(paste0(
      "CASE WHEN waterbody_key IS NULL THEN 0 ELSE least(%s, SUM(",
      "CASE WHEN edge_type IN (1400, 1450) THEN below_m ELSE 0 END",
      " + entry_in_m) OVER (",
      "PARTITION BY origin_id, waterbody_key ORDER BY %s%s)) END"),
      .frs_sql_num(conn_max), ord_bare, frame)
  } else {
    "0"
  }
  # The part of a jump inside the landing row's polygon: the walk reaches
  # the bank where the jump line crosses into it. Capped at entry_max so
  # the cap and prefilter (max(distance_max) + conn_max) stay sufficient.
  entry_sql <- if (bank) {
    sprintf(paste0(
      "CASE WHEN ST_Distance(prev_pt, geom) > 0.001 AND waterbody_key IS NOT NULL THEN ",
      "least(%s, coalesce((SELECT sum(ST_Length(ST_Intersection(",
      "ST_MakeLine(ST_Force2D(downstream.prev_pt), ST_Force2D(ST_ClosestPoint(",
      "downstream.geom, downstream.prev_pt))), ",
      "p.geom))) FROM %s p WHERE p.waterbody_key = downstream.waterbody_key), 0)) ",
      "ELSE 0 END"), .frs_sql_num(entry_max), .frs_near_river_polygons())
  } else {
    "0"
  }
  sprintf(
    "CREATE TEMP TABLE %s AS
     WITH origins AS (
       SELECT id_segment, watershed_group_code,
         %s::double precision AS val, blue_line_key,
         downstream_route_measure, wscode_ltree, localcode_ltree, geom
       FROM %s
       WHERE (%s IS NULL OR %s < %s)
         -- FWA_Downstream() would still join a row with no local code to
         -- the bottom row of every ancestor line (its wscode = localcode
         -- branch never reads the origin's local code), skipping the
         -- network between; such a row has no place to start from.
         AND localcode_ltree IS NOT NULL
     ),
     downstream AS (
       SELECT o.id_segment AS origin_id, o.watershed_group_code,
         o.val AS origin_val, t.id_segment, t.edge_type,
         t.%s::double precision AS val,
         t.length_metre, t.waterbody_key, t.wscode_ltree,
         t.downstream_route_measure, t.geom,
         coalesce(LAG(ST_StartPoint(t.geom)) OVER (PARTITION BY o.id_segment
           ORDER BY %s), ST_StartPoint(o.geom)) AS prev_pt,
         -- The row directly above this one on its own line. If it is on
         -- the path but the prefilter dropped it, the walk cannot reach
         -- this row without it: the path is cut here.
         EXISTS (
           SELECT 1 FROM (
             SELECT r.blue_line_key, r.downstream_route_measure,
               r.wscode_ltree, r.localcode_ltree, r.geom
             FROM %s r
             WHERE r.blue_line_key = t.blue_line_key
               AND r.downstream_route_measure > t.downstream_route_measure
             ORDER BY r.downstream_route_measure LIMIT 1) r
           WHERE (r.blue_line_key <> o.blue_line_key
                  OR r.downstream_route_measure < o.downstream_route_measure)
             AND NOT ST_DWithin(r.geom, o.geom, %s)
             AND FWA_Downstream(
               o.blue_line_key, o.downstream_route_measure,
               o.wscode_ltree, o.localcode_ltree,
               r.blue_line_key, r.downstream_route_measure,
               r.wscode_ltree, r.localcode_ltree)) AS above_dropped
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
       SELECT origin_id, watershed_group_code, origin_val, id_segment,
         edge_type, val, length_metre, waterbody_key, wscode_ltree,
         downstream_route_measure,
         ST_Distance(prev_pt, geom) AS jump_m,
         length_metre * ST_LineLocatePoint(ST_Force2D(geom),
           ST_Force2D(prev_pt)) AS below_m,
         %s AS entry_in_m, above_dropped
       FROM downstream
     ),
     walked AS (
       SELECT origin_id, watershed_group_code, origin_val, edge_type,
         val, below_m,
         SUM(below_m + %s) OVER w - below_m AS path_m,
         %s AS connector_m,
         bool_or(above_dropped) OVER w AS cut
       FROM entered
       WINDOW w AS (PARTITION BY origin_id ORDER BY %s%s)
     ),
     capped AS (
       SELECT * FROM walked WHERE path_m <= %s AND NOT cut
     )
     SELECT c.origin_id, c.watershed_group_code, q.threshold,
       greatest(min(c.path_m - c.connector_m), 0) AS dist_m
     FROM capped c
     INNER JOIN (VALUES %s) AS q(threshold, distance_max)
       ON c.val >= q.threshold
      AND c.edge_type NOT IN (1400, 1450)
      AND (c.origin_val IS NULL OR c.origin_val < q.threshold)
      AND c.path_m - c.connector_m <= q.distance_max
     GROUP BY c.origin_id, c.watershed_group_code, q.threshold",
    walk_tbl, col, table, col, col, .frs_sql_num(threshold), col, ord,
    table, cap, table, cap,
    entry_sql, if (jumps) "jump_m" else "0", conn_sql, ord_bare, frame, cap,
    .frs_near_river_values(threshold, distance_max))
}


#' Waterbody polygons the bank rule measures against
#'
#' A SQL subquery of `waterbody_key, geom` over FWA's river, lake,
#' reservoir and wetland polygons. A function so tests can point the walk
#' at a fixture.
#'
#' @noRd
.frs_near_river_polygons <- function() {
  paste0("(",
    paste(sprintf("SELECT waterbody_key, geom FROM whse_basemapping.%s",
                  c("fwa_rivers_poly", "fwa_lakes_poly",
                    "fwa_manmade_waterbodies_poly", "fwa_wetlands_poly")),
          collapse = " UNION ALL "), ")")
}
