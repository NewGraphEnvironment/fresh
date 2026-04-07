#' Find Gradient Break Locations on a Stream Network
#'
#' Detect where stream gradient exceeds a threshold for a sustained
#' distance (island detection). Produces break points at the entry of
#' each steep section, suitable for [frs_break_apply()].
#'
#' For locating point features on the network (crossings, falls,
#' observations), use [frs_feature_find()] instead.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Working schema table to find breaks on
#'   (from [frs_extract()]).
#' @param to Character. Destination table for break points.
#'   Default `"working.breaks"`.
#' @param attribute Character. Column name for threshold-based breaks.
#'   Currently only `"gradient"` is supported.
#' @param threshold Numeric. Threshold value — sustained sections where
#'   gradient exceeds this produce a break point at the entry.
#' @param interval Integer. Not used (kept for compatibility). Default `100`.
#' @param distance Integer. Upstream window in metres for gradient
#'   computation AND minimum island length. Default `100`.
#' @param overwrite Logical. If `TRUE`, drop `to` before creating.
#'   Default `TRUE`.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' # --- Where breaks occur (bundled data) ---
#' # Break points are locations where a stream attribute exceeds a threshold.
#' # Here: segments with gradient > 5% (potential barriers to fish passage).
#'
#' d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
#' streams <- d$streams
#'
#' # Which segments exceed 5% gradient?
#' is_steep <- streams$gradient > 0.05
#' message(sum(is_steep, na.rm = TRUE), " of ", nrow(streams),
#'         " segments exceed 5% gradient")
#'
#' # Plot: steep segments (red) are where breaks would be placed
#' plot(sf::st_geometry(streams), col = "grey80",
#'      main = "Break locations: gradient > 5%")
#' plot(sf::st_geometry(streams[which(is_steep), ]), col = "red", add = TRUE)
#' legend("topright", legend = c("below threshold", "above threshold (break)"),
#'        col = c("grey80", "red"), lwd = 2, cex = 0.8)
#'
#' \dontrun{
#' # --- Live DB usage ---
#' conn <- frs_db_conn()
#'
#' # Attribute mode: break where gradient exceeds 5%
#' conn |>
#'   frs_extract("bcfishpass.streams_vw", "working.streams", aoi = "BULK") |>
#'   frs_break_find("working.streams", attribute = "gradient", threshold = 0.05)
#'
#' DBI::dbDisconnect(conn)
#' }
frs_break_find <- function(conn, table, to = "working.breaks",
                           attribute = NULL, threshold = NULL,
                           interval = 100L, distance = 100L,
                           overwrite = TRUE) {
  .frs_validate_identifier(table, "source table")
  .frs_validate_identifier(to, "destination table")

  if (is.null(attribute) || is.null(threshold)) {
    stop("attribute and threshold are required", call. = FALSE)
  }

  if (overwrite) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  }

  .frs_break_find_attribute(conn, table, to, attribute, threshold,
                             interval, distance)

  invisible(conn)
}


#' Find gradient breaks using island detection
#'
#' Computes gradient at every FWA vertex over a `distance` metre
#' upstream window. Groups consecutive above-threshold vertices into
#' "islands" (minimum `distance` metres long) and creates one break
#' at the entry of each island — where gradient first exceeds the
#' threshold for a sustained section.
#'
#' Adapted from bcfishpass `gradient_barriers_load.sql` island
#' approach. Entry-only breaks are appropriate for access barriers
#' (everything upstream of the entry is blocked). For habitat
#' classification, segments are classified by their own gradient
#' attribute, not by break presence.
#'
#' @param conn DBI connection.
#' @param table Working streams table (for BLK list).
#' @param to Output breaks table name.
#' @param attribute Column name (currently only "gradient" supported).
#' @param threshold Numeric. Gradient threshold.
#' @param interval Not used (kept for API compatibility).
#' @param distance Integer. Upstream window in metres for gradient
#'   computation AND minimum island length. Default 100.
#' @noRd
.frs_break_find_attribute <- function(conn, table, to, attribute, threshold,
                                      interval, distance) {
  .frs_validate_identifier(attribute, "attribute column")
  stopifnot(is.numeric(threshold), length(threshold) == 1)
  stopifnot(is.numeric(distance), length(distance) == 1)

  dist <- as.integer(distance)

  sql <- sprintf(
    "CREATE TABLE %s AS
     WITH working_blks AS (
       SELECT DISTINCT blue_line_key FROM %s
     ),

     -- Gradient at every vertex over %dm upstream window
     vertex_grades AS (
       SELECT
         sv.blue_line_key,
         ROUND(sv.downstream_route_measure::numeric, 2) AS downstream_route_measure,
         ROUND(((ST_Z((ST_Dump(ST_LocateAlong(
           s2.geom, sv.downstream_route_measure + %d
         ))).geom) - sv.elevation) / %d)::numeric, 4) AS gradient
       FROM (
         SELECT
           s.blue_line_key,
           ((ST_LineLocatePoint(s.geom,
             ST_PointN(s.geom, generate_series(1, ST_NPoints(s.geom) - 1)))
             * s.length_metre) + s.downstream_route_measure
           ) AS downstream_route_measure,
           ST_Z(ST_PointN(s.geom, generate_series(1, ST_NPoints(s.geom) - 1))) AS elevation
         FROM whse_basemapping.fwa_stream_networks_sp s
         WHERE s.blue_line_key IN (SELECT blue_line_key FROM working_blks)
           AND s.edge_type IN (1000,1050,1100,1150,1250,1350,1410,2000,2300)
       ) sv
       INNER JOIN whse_basemapping.fwa_stream_networks_sp s2
         ON sv.blue_line_key = s2.blue_line_key
         AND sv.downstream_route_measure + %d >= s2.downstream_route_measure
         AND sv.downstream_route_measure + %d < s2.upstream_route_measure
       WHERE s2.edge_type != 6010
     ),

     -- Flag above threshold
     flagged AS (
       SELECT blue_line_key, downstream_route_measure,
         CASE WHEN gradient > %s THEN TRUE ELSE FALSE END AS above
       FROM vertex_grades
     ),

     -- Group consecutive above-threshold vertices into islands
     -- via lag/count window (bcfishpass pattern)
     islands AS (
       SELECT
         blue_line_key,
         min(downstream_route_measure) AS downstream_route_measure,
         max(downstream_route_measure) - min(downstream_route_measure) AS island_length
       FROM (
         SELECT blue_line_key, downstream_route_measure, above,
           count(step OR NULL) OVER (
             PARTITION BY blue_line_key
             ORDER BY downstream_route_measure
           ) AS grp
         FROM (
           SELECT blue_line_key, downstream_route_measure, above,
             lag(above) OVER (
               PARTITION BY blue_line_key
               ORDER BY downstream_route_measure
             ) IS DISTINCT FROM above AS step
           FROM flagged
         ) sub1
         WHERE above
       ) sub2
       GROUP BY blue_line_key, grp
     )

     -- Entry point of each island >= minimum length
     SELECT DISTINCT
       blue_line_key,
       downstream_route_measure,
       'gradient' AS label,
       'attribute' AS source
     FROM islands
     WHERE island_length >= %d",
    to, table,
    dist, dist, dist, dist, dist,
    .frs_sql_num(threshold),
    dist
  )
  .frs_db_execute(conn, sql)
}




#' Build SQL label expression from label spec
#'
#' @param label Static label string, or NULL.
#' @param label_col Column name to read label from, or NULL.
#' @param label_map Named character vector mapping column values to labels,
#'   or NULL (pass-through).
#' @return SQL expression string for the label column.
#' @noRd
.frs_label_expr <- function(label = NULL, label_col = NULL,
                            label_map = NULL) {
  if (!is.null(label_col)) {
    .frs_validate_identifier(label_col, "label_col")
    if (!is.null(label_map)) {
      # CASE expression mapping values
      whens <- vapply(names(label_map), function(val) {
        sprintf("WHEN %s = %s THEN %s",
                label_col,
                .frs_quote_string(val),
                .frs_quote_string(label_map[[val]]))
      }, character(1))
      sprintf("CASE %s ELSE %s END AS label",
              paste(whens, collapse = " "),
              label_col)
    } else {
      # Pass-through: use column values as-is
      sprintf("%s::text AS label", label_col)
    }
  } else if (!is.null(label)) {
    sprintf("%s AS label", .frs_quote_string(label))
  } else {
    "NULL::text AS label"
  }
}


#' Validate Breaks Against Upstream Evidence
#'
#' Filter break points by checking for upstream evidence. For each break,
#' counts rows in `evidence_table` that are upstream on the same
#' `blue_line_key`. Breaks with count >= `count_threshold` are removed.
#'
#' This is generic — the evidence table can contain any point features
#' with `blue_line_key` and `downstream_route_measure` columns (fish
#' observations, water quality stations, SAR sightings, etc.). Use `where`
#' to filter the evidence to relevant records.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param breaks Character. Table name containing break points with
#'   `blue_line_key` and `downstream_route_measure` columns.
#' @param evidence_table Character. Schema-qualified table with evidence
#'   features. Must have `blue_line_key` and `downstream_route_measure`
#'   columns.
#' @param where Character or `NULL`. SQL predicate to filter the evidence
#'   table (without leading AND/WHERE). Column references use alias `e`.
#'   Examples: `"e.species_code IN ('CO','CH')"`,
#'   `"e.observation_date >= '1990-01-01'"`.
#' @param count_threshold Integer. Minimum upstream evidence count to
#'   remove a break. Default `1` (any evidence removes the break).
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
#' # Remove gradient breaks where coho or chinook were observed upstream
#' conn |>
#'   frs_break_validate("working.breaks",
#'     evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
#'     where = "e.species_code IN ('CO', 'CH')")
#'
#' # Remove breaks with 5+ recent observations of any species upstream
#' conn |>
#'   frs_break_validate("working.breaks",
#'     evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
#'     where = "e.observation_date >= '1990-01-01'",
#'     count_threshold = 5)
#'
#' # Generic: validate against any point evidence table
#' conn |>
#'   frs_break_validate("working.breaks",
#'     evidence_table = "working.water_quality_sites",
#'     where = "e.conductivity > 100")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_break_validate <- function(conn, breaks, evidence_table,
                               where = NULL, count_threshold = 1L) {
  .frs_validate_identifier(breaks, "breaks table")
  .frs_validate_identifier(evidence_table, "evidence table")
  stopifnot(is.numeric(count_threshold), length(count_threshold) == 1)

  # Build evidence filter
  evidence_where <- if (!is.null(where)) {
    paste(" AND", where)
  } else {
    ""
  }

  # Delete breaks that have upstream evidence
  # Join breaks to FWA stream network to get wscode/localcode,
  # then count upstream observations
  sql <- sprintf(
    "DELETE FROM %s b
     WHERE b.downstream_route_measure IN (
       SELECT b2.downstream_route_measure
       FROM %s b2
       JOIN whse_basemapping.fwa_stream_networks_sp s
         ON b2.blue_line_key = s.blue_line_key
         AND b2.downstream_route_measure >= s.downstream_route_measure
         AND b2.downstream_route_measure < s.upstream_route_measure
       WHERE (
         SELECT count(*)
         FROM %s e
         WHERE e.blue_line_key = s.blue_line_key
           AND e.downstream_route_measure > b2.downstream_route_measure%s
       ) >= %d
       AND b.blue_line_key = b2.blue_line_key
     )",
    breaks, breaks, evidence_table, evidence_where,
    as.integer(count_threshold)
  )
  .frs_db_execute(conn, sql)

  invisible(conn)
}


#' Apply Break Points to Split Stream Geometry
#'
#' Split stream segments in a working table at break point locations using
#' `ST_LocateBetween()` (PostGIS linear referencing). This follows the
#' bcfishpass `break_streams()` pattern: shorten original segments and insert
#' new segments at the break measures.
#'
#' Break points within 1m of existing segment endpoints are skipped.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Working schema table to split
#'   (from [frs_extract()]).
#' @param breaks Character. Table name containing break points with
#'   `blue_line_key` and `downstream_route_measure` columns
#'   (from [frs_break_find()]).
#' @param segment_id Character. Column name used as the segment identifier
#'   in `table`. Default `"linear_feature_id"` (FWA base table). Use
#'   `"segmented_stream_id"` for bcfishpass tables.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' # --- Before vs after breaking (bundled data) ---
#' d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
#' streams <- d$streams
#'
#' # Visualize: segments that would be split at gradient > 8%
#' steep <- !is.na(streams$gradient) & streams$gradient > 0.08
#' streams$would_break <- ifelse(steep, "split here", "keep")
#' message(sum(steep), " of ", nrow(streams), " segments would be split")
#'
#' plot(streams["would_break"],
#'      main = "Segments split by frs_break_apply()",
#'      pal = c("grey80", "red"), key.pos = 1)
#'
#' \dontrun{
#' # --- Live DB: copy-paste to see before/after ---
#' conn <- frs_db_conn()
#' aoi <- d$aoi
#'
#' # 1. Extract FWA base streams to working schema
#' conn |> frs_extract(
#'   from = "whse_basemapping.fwa_stream_networks_sp",
#'   to = "working.demo_break",
#'   cols = c("linear_feature_id", "blue_line_key",
#'            "downstream_route_measure", "upstream_route_measure",
#'            "gradient", "geom"),
#'   aoi = aoi, overwrite = TRUE)
#'
#' # 2. Plot BEFORE
#' before <- frs_db_query(conn,
#'   "SELECT gradient, geom FROM working.demo_break")
#' plot(before["gradient"], main = paste("Before:", nrow(before), "segments"))
#'
#' # 3. Convert to generated columns — gradient auto-recomputes after break
#' conn |> frs_col_generate("working.demo_break")
#'
#' # 4. Break where gradient > 8% (sampled at 100m intervals)
#' conn |> frs_break("working.demo_break",
#'   attribute = "gradient", threshold = 0.08)
#'
#' # 5. Plot AFTER — more segments, gradient recomputed per sub-segment
#' after <- frs_db_query(conn,
#'   "SELECT gradient, geom FROM working.demo_break")
#' plot(after["gradient"],
#'   main = paste("After:", nrow(after), "segments (+",
#'                nrow(after) - nrow(before), "from breaks)"))
#'
#' # Clean up
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_break")
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.breaks")
#' DBI::dbDisconnect(conn)
#' }
frs_break_apply <- function(conn, table, breaks,
                            segment_id = "linear_feature_id") {
  .frs_validate_identifier(table, "stream table")
  .frs_validate_identifier(breaks, "breaks table")
  .frs_validate_identifier(segment_id, "segment_id column")

  # Step 1: Create temp table with new segments from break points
  # Following bcfishpass break_streams() pattern:
  # - Join breaks to streams where measure falls within segment (>1m from ends)
  # - Use lead() to pair up new segment boundaries
  # - Cut geometry with ST_LocateBetween
  sid <- segment_id
  sql_temp <- sprintf(
    "CREATE TEMPORARY TABLE temp_broken_streams AS
     WITH breakpoints AS (
       SELECT DISTINCT
         blue_line_key,
         round(downstream_route_measure::numeric)::integer AS downstream_route_measure
       FROM %s
     ),
     to_break AS (
       SELECT
         s.%s AS seg_id,
         s.downstream_route_measure AS meas_stream_ds,
         s.upstream_route_measure AS meas_stream_us,
         b.downstream_route_measure AS meas_event
       FROM %s s
       INNER JOIN breakpoints b
         ON s.blue_line_key = b.blue_line_key
         AND (b.downstream_route_measure - s.downstream_route_measure) > 1
         AND (s.upstream_route_measure - b.downstream_route_measure) > 1
     ),
     new_measures AS (
       SELECT
         seg_id,
         meas_event AS downstream_route_measure,
         lead(meas_event, 1, meas_stream_us) OVER (
           PARTITION BY seg_id ORDER BY meas_event
         ) AS upstream_route_measure
       FROM to_break
     )
     SELECT
       n.seg_id,
       n.downstream_route_measure,
       n.upstream_route_measure,
       (ST_Dump(ST_LocateBetween(
         s.geom, n.downstream_route_measure, n.upstream_route_measure
       ))).geom AS geom
     FROM new_measures n
     INNER JOIN %s s ON n.seg_id = s.%s",
    breaks, sid, table, table, sid
  )
  .frs_db_execute(conn, sql_temp)

  # Step 2: Shorten original segments to the first break point
  sql_shorten <- sprintf(
    "WITH min_segs AS (
       SELECT DISTINCT ON (seg_id)
         seg_id,
         downstream_route_measure
       FROM temp_broken_streams
       ORDER BY seg_id, downstream_route_measure ASC
     ),
     shortened AS (
       SELECT
         m.seg_id,
         (ST_Dump(ST_LocateBetween(
           s.geom, s.downstream_route_measure, m.downstream_route_measure
         ))).geom AS geom
       FROM min_segs m
       INNER JOIN %s s ON m.seg_id = s.%s
     )
     UPDATE %s a
     SET geom = b.geom
     FROM shortened b
     WHERE b.seg_id = a.%s",
    table, sid, table, sid
  )
  .frs_db_execute(conn, sql_shorten)

  # Step 3: Insert new segments with attributes carried from parent
  # Discover columns dynamically — carry everything except segment_id,
  # measures, and geom (those come from the split, not the parent)
  # Get writable columns only (excludes GENERATED ALWAYS columns)
  cols_writable <- .frs_table_columns(conn, table, exclude_generated = TRUE)

  # Split columns: segment_id, measures, and geom come from the split
  cols_split_all <- c(sid, "downstream_route_measure",
                      "upstream_route_measure", "geom")
  cols_split <- intersect(cols_split_all, cols_writable)

  # Carry columns: everything writable that isn't a split column
  # This preserves linear_feature_id (FWA provenance) from parent
  cols_carry <- setdiff(cols_writable, cols_split_all)

  # Build INSERT column list and SELECT expressions
  cols_insert_parts <- character(0)
  select_parts <- character(0)

  # segment_id — new unique ID from max + row_number
  if (sid %in% cols_split) {
    cols_insert_parts <- c(cols_insert_parts, sid)
    select_parts <- c(select_parts, sprintf(
      "(SELECT max(%s) FROM %s) + row_number() OVER (
         ORDER BY t.seg_id, t.downstream_route_measure
       )", sid, table))
  }

  # Carried columns from parent (includes linear_feature_id for provenance)
  if (length(cols_carry) > 0) {
    cols_insert_parts <- c(cols_insert_parts, cols_carry)
    select_parts <- c(select_parts, paste0("s.", cols_carry))
  }

  # Measures and geom from temp table (only if writable)
  for (col in c("downstream_route_measure", "upstream_route_measure", "geom")) {
    if (col %in% cols_split) {
      cols_insert_parts <- c(cols_insert_parts, col)
      select_parts <- c(select_parts, paste0("t.", col))
    }
  }

  sql_insert <- sprintf(
    "INSERT INTO %s (%s)
     SELECT %s
     FROM temp_broken_streams t
     INNER JOIN %s s ON t.seg_id = s.%s",
    table, paste(cols_insert_parts, collapse = ", "),
    paste(select_parts, collapse = ",\n       "),
    table, sid
  )
  .frs_db_execute(conn, sql_insert)

  # Cleanup temp table
  .frs_db_execute(conn, "DROP TABLE IF EXISTS temp_broken_streams")

  invisible(conn)
}


#' Break Stream Network at Threshold or Point Locations
#'
#' Convenience wrapper that calls [frs_break_find()], optionally
#' [frs_break_validate()], then [frs_break_apply()] in sequence.
#'
#' @inheritParams frs_break_find
#' @param points_where Character or `NULL`. SQL predicate to filter rows from
#'   `points_table` (e.g. `"barrier_ind = TRUE"`). Passed to
#'   [frs_break_find()] as `where`.
#' @param evidence_table Character or `NULL`. If provided, validate breaks
#'   against upstream evidence before applying. Passed to
#'   [frs_break_validate()].
#' @param where Character or `NULL`. SQL predicate to filter evidence
#'   (e.g. `"e.species_code IN ('CO','CH')"`). Passed to
#'   [frs_break_validate()].
#' @param count_threshold Integer. Minimum upstream evidence count to
#'   remove a break. Default `1`.
#' @param segment_id Character. Column name used as segment identifier.
#'   Passed to [frs_break_apply()]. Default `"linear_feature_id"`.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' # --- Concept: what frs_break does (bundled data) ---
#' d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
#' streams <- d$streams
#'
#' # Steep segments are where breaks get placed
#' steep <- !is.na(streams$gradient) & streams$gradient > 0.08
#' plot(sf::st_geometry(streams), col = "grey80",
#'      main = "Gradient breaks (> 8%)")
#' plot(sf::st_geometry(streams[steep, ]), col = "red", add = TRUE)
#' legend("topright",
#'        legend = c("below threshold", "above (break here)"),
#'        col = c("grey80", "red"), lwd = 2, cex = 0.8)
#'
#' \dontrun{
#' # --- Live DB: copy-paste to see before/after ---
#' conn <- frs_db_conn()
#' aoi <- d$aoi  # Byman-Ailport sf polygon from bundled data
#'
#' # 1. Extract FWA base streams (unsegmented) to working schema
#' conn |> frs_extract(
#'   from = "whse_basemapping.fwa_stream_networks_sp",
#'   to = "working.demo_streams",
#'   cols = c("linear_feature_id", "blue_line_key",
#'            "downstream_route_measure", "upstream_route_measure",
#'            "gradient", "geom"),
#'   aoi = aoi,
#'   overwrite = TRUE
#' )
#'
#' # 2. Plot BEFORE — original segments
#' before <- frs_db_query(conn,
#'   "SELECT gradient, geom FROM working.demo_streams")
#' n_before <- nrow(before)
#' plot(before["gradient"], main = paste("Before:", n_before, "segments"))
#'
#' # 3. Convert to generated columns — gradient auto-recomputes after break
#' conn |> frs_col_generate("working.demo_streams")
#'
#' # 4. Break at gradient > 8%
#' conn |> frs_break("working.demo_streams",
#'   attribute = "gradient", threshold = 0.08)
#'
#' # 5. Plot AFTER — more segments, gradient recomputed per sub-segment
#' after <- frs_db_query(conn,
#'   "SELECT gradient, geom FROM working.demo_streams")
#' n_after <- nrow(after)
#' plot(after["gradient"],
#'      main = paste("After:", n_after, "segments (+",
#'                   n_after - n_before, "from breaks)"))
#'
#' # Clean up
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_streams")
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.breaks")
#' DBI::dbDisconnect(conn)
#' }
frs_break <- function(conn, table, to = "working.breaks",
                      attribute = NULL, threshold = NULL,
                      interval = 100L, distance = 100L,
                      points_table = NULL, points = NULL,
                      points_where = NULL,
                      aoi = NULL, overwrite = TRUE,
                      evidence_table = NULL, where = NULL,
                      count_threshold = 1L,
                      segment_id = "linear_feature_id") {
  # Step 1: Find breaks
  frs_break_find(conn, table, to = to,
                 attribute = attribute, threshold = threshold,
                 interval = interval, distance = distance,
                 points_table = points_table, points = points,
                 where = points_where,
                 aoi = aoi, overwrite = overwrite)

  # Step 2: Validate (optional)
  if (!is.null(evidence_table)) {
    frs_break_validate(conn, breaks = to,
                       evidence_table = evidence_table,
                       where = where,
                       count_threshold = count_threshold)
  }

  # Step 3: Apply
  frs_break_apply(conn, table, breaks = to, segment_id = segment_id)

  invisible(conn)
}
