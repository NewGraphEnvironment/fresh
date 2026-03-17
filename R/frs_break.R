#' Find Break Locations on a Stream Network
#'
#' Identify break points where the stream network should be split. Supports
#' three modes: attribute threshold (e.g. gradient > 0.05), existing point
#' table (e.g. falls, dams), or user-provided sf points (snapped via
#' [frs_point_snap()]).
#'
#' All modes produce the same output shape: a table with `blue_line_key` and
#' `downstream_route_measure` columns, suitable for [frs_break_apply()].
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Working schema table to find breaks on
#'   (from [frs_extract()]).
#' @param to Character. Destination table for break points.
#'   Default `"working.breaks"`.
#' @param attribute Character or `NULL`. Column name for threshold-based breaks.
#'   Currently only `"gradient"` is supported — uses `fwa_slopealonginterval()`
#'   to compute slope at fine resolution and find where it exceeds `threshold`.
#' @param threshold Numeric or `NULL`. Threshold value — intervals where
#'   computed `attribute > threshold` generate a break point.
#' @param interval Integer. Sampling interval in metres for attribute mode.
#'   Default `100`. Smaller values find more precise break locations but
#'   take longer.
#' @param distance Integer. Upstream distance in metres over which to compute
#'   slope for attribute mode. Default `100`. Should generally equal
#'   `interval`.
#' @param points_table Character or `NULL`. Schema-qualified table name
#'   containing existing break points with `blue_line_key` and
#'   `downstream_route_measure` columns (e.g. falls, dams, crossings).
#' @param points An `sf` object or `NULL`. User-provided points to snap
#'   to the stream network via [frs_point_snap()].
#' @param aoi AOI specification for filtering (passed to
#'   `.frs_resolve_aoi()`). Only used with `points_table` mode.
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
#' # Table mode: break at known falls locations
#' conn |> frs_break_find("working.streams",
#'   points_table = "whse_basemapping.fwa_obstructions_sp")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_break_find <- function(conn, table, to = "working.breaks",
                           attribute = NULL, threshold = NULL,
                           interval = 100L, distance = 100L,
                           points_table = NULL, points = NULL,
                           aoi = NULL, overwrite = TRUE) {
  .frs_validate_identifier(table, "source table")
  .frs_validate_identifier(to, "destination table")

  # Detect mode
  has_attr <- !is.null(attribute) && !is.null(threshold)
  has_table <- !is.null(points_table)
  has_points <- !is.null(points)
  n_modes <- sum(has_attr, has_table, has_points)

  if (n_modes == 0) {
    stop("Provide one of: attribute+threshold, points_table, or points",
         call. = FALSE)
  }
  if (n_modes > 1) {
    stop("Provide only one of: attribute+threshold, points_table, or points",
         call. = FALSE)
  }

  if (overwrite) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  }

  if (has_attr) {
    .frs_break_find_attribute(conn, table, to, attribute, threshold,
                               interval, distance)
  } else if (has_table) {
    .frs_break_find_table(conn, table, to, points_table, aoi)
  } else {
    .frs_break_find_points(conn, table, to, points)
  }

  invisible(conn)
}


#' Find breaks by attribute threshold via fine-grained slope sampling
#'
#' Uses `fwa_slopealonginterval()` to compute gradient at `interval` metre
#' resolution along each `blue_line_key` in `table`. Intervals where the
#' computed gradient exceeds `threshold` become break points.
#'
#' This produces break measures that fall WITHIN existing FWA segments,
#' so `frs_break_apply()` will actually split geometry.
#'
#' @noRd
.frs_break_find_attribute <- function(conn, table, to, attribute, threshold,
                                      interval, distance) {
  .frs_validate_identifier(attribute, "attribute column")
  stopifnot(is.numeric(threshold), length(threshold) == 1)
  stopifnot(is.numeric(interval), length(interval) == 1)
  stopifnot(is.numeric(distance), length(distance) == 1)

  # Use the working table's BLKs but get valid measure ranges from the
  # FWA base table (fwa_slopealonginterval is strict about bounds).
  # Only sample BLKs that appear in our working table.
  sql <- sprintf(
    "CREATE TABLE %s AS
     WITH working_blks AS (
       SELECT DISTINCT blue_line_key FROM %s
     ),
     blk_ranges AS (
       SELECT
         f.blue_line_key,
         min(f.downstream_route_measure)::integer AS start_m,
         floor(max(f.upstream_route_measure))::integer AS end_m
       FROM whse_basemapping.fwa_stream_networks_sp f
       WHERE f.blue_line_key IN (SELECT blue_line_key FROM working_blks)
       GROUP BY f.blue_line_key
       HAVING (floor(max(f.upstream_route_measure))::integer -
               min(f.downstream_route_measure)::integer) >= %d
     )
     SELECT DISTINCT b.blue_line_key,
       g.downstream_measure::double precision AS downstream_route_measure
     FROM blk_ranges b
     CROSS JOIN LATERAL fwa_slopealonginterval(
       b.blue_line_key, %d, %d, b.start_m, b.end_m
     ) g
     WHERE g.%s > %s",
    to, table, as.integer(interval) + as.integer(distance),
    as.integer(interval), as.integer(distance),
    attribute, threshold
  )
  .frs_db_execute(conn, sql)
}


#' Find breaks from an existing point table
#'
#' Reads `blue_line_key` and `downstream_route_measure` from an existing
#' database table (e.g. falls, dams, crossings). Optionally filters by AOI.
#'
#' @noRd
.frs_break_find_table <- function(conn, table, to, points_table, aoi) {
  .frs_validate_identifier(points_table, "points table")

  aoi_pred <- .frs_resolve_aoi(aoi, conn = conn)
  where_clause <- if (nzchar(aoi_pred)) {
    paste(" WHERE", aoi_pred)
  } else {
    ""
  }

  sql <- sprintf(
    "CREATE TABLE %s AS
     SELECT DISTINCT blue_line_key,
       downstream_route_measure
     FROM %s%s",
    to, points_table, where_clause
  )
  .frs_db_execute(conn, sql)
}


#' Find breaks from user-provided sf points
#'
#' Snaps user points to the stream network via [frs_point_snap()] and
#' extracts `blue_line_key` + `downstream_route_measure`.
#'
#' @noRd
.frs_break_find_points <- function(conn, table, to, points) {
  if (!inherits(points, "sf")) {
    stop("points must be an sf object", call. = FALSE)
  }

  snapped <- frs_point_snap(conn, points)

  # Write snapped points to the breaks table
  blk <- snapped$blue_line_key
  drm <- snapped$downstream_route_measure

  values <- paste(
    sprintf("(%d, %s)", as.integer(blk), as.numeric(drm)),
    collapse = ", "
  )

  sql <- sprintf(
    "CREATE TABLE %s (blue_line_key integer, downstream_route_measure double precision);
     INSERT INTO %s VALUES %s",
    to, to, values
  )
  .frs_db_execute(conn, sql)
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
#' # 3. Break where gradient > 8% (sampled at 100m intervals)
#' conn |> frs_break("working.demo_break",
#'   attribute = "gradient", threshold = 0.08)
#'
#' # 4. Plot AFTER — more segments where gradient splits occurred
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

  # Split columns: these come from the temp table, not the parent
  cols_split_all <- c(sid, "downstream_route_measure",
                      "upstream_route_measure", "geom")
  # Only include split columns that are actually writable
  cols_split <- intersect(cols_split_all, cols_writable)

  # Carry columns: everything writable that isn't a split column
  cols_carry <- setdiff(cols_writable, cols_split_all)

  # Build INSERT column list and SELECT expressions
  cols_insert_parts <- character(0)
  select_parts <- character(0)

  # segment_id — new ID from max + row_number
  if (sid %in% cols_split) {
    cols_insert_parts <- c(cols_insert_parts, sid)
    select_parts <- c(select_parts, sprintf(
      "(SELECT max(%s) FROM %s) + row_number() OVER (
         ORDER BY t.seg_id, t.downstream_route_measure
       )", sid, table))
  }

  # Carried columns from parent
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
#' @param evidence_table Character or `NULL`. If provided, validate breaks
#'   against upstream evidence before applying. Passed to
#'   [frs_break_validate()].
#' @param where Character or `NULL`. SQL predicate to filter evidence
#'   (e.g. `"e.species_code IN ('CO','CH')"`). Passed to
#'   [frs_break_validate()].
#' @param count_threshold Integer. Minimum upstream evidence count to
#'   remove a break. Default `1`.
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
#' # 3. Break at gradient > 15%
#' conn |> frs_break("working.demo_streams",
#'   attribute = "gradient", threshold = 0.15)
#'
#' # 4. Plot AFTER — more segments where splits occurred
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
                      aoi = NULL, overwrite = TRUE,
                      evidence_table = NULL, where = NULL,
                      count_threshold = 1L,
                      segment_id = "linear_feature_id") {
  # Step 1: Find breaks
  frs_break_find(conn, table, to = to,
                 attribute = attribute, threshold = threshold,
                 interval = interval, distance = distance,
                 points_table = points_table, points = points,
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
