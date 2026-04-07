#' Find Features on a Stream Network
#'
#' Locate features from a database table or sf object on the stream
#' network. Produces a table with `blue_line_key`, `downstream_route_measure`,
#' `label`, and `source` columns, suitable for [frs_break_apply()],
#' [frs_feature_index()], or as a break source in [frs_habitat()].
#'
#' Unlike [frs_break_find()] which is specific to gradient threshold
#' detection, this function handles any point features on the network:
#' crossings, fish observations, water quality stations, flow gauges,
#' territory boundaries, etc.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param table Character. Working streams table (for BLK scoping).
#' @param to Character. Destination table name. Default
#'   `"working.features"`.
#' @param points_table Character or `NULL`. Schema-qualified table with
#'   network-referenced features.
#' @param points An `sf` object or `NULL`. User-provided points to snap
#'   to the network via [frs_point_snap()].
#' @param where Character or `NULL`. SQL predicate to filter
#'   `points_table`.
#' @param col_blk Character. Column name for stream identifier in
#'   `points_table`. Default `"blue_line_key"`.
#' @param col_measure Character. Column name for route measure in
#'   `points_table`. Default `"downstream_route_measure"`.
#' @param col_id Character or `NULL`. Column name for feature ID.
#'   When provided, included in output for joining back to source.
#' @param label Character or `NULL`. Static label for all features.
#' @param label_col Character or `NULL`. Column name to read labels from.
#' @param label_map Named character vector or `NULL`. Maps `label_col`
#'   values to output labels.
#' @param overwrite Logical. Drop `to` before creating. Default `TRUE`.
#' @param append Logical. INSERT INTO existing `to` table. Default
#'   `FALSE`.
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
#' # Crossings with severity labels
#' frs_feature_find(conn, "working.streams",
#'   points_table = "working.crossings",
#'   col_id = "aggregated_crossings_id",
#'   label_col = "barrier_status",
#'   label_map = c("BARRIER" = "blocked", "POTENTIAL" = "potential"),
#'   to = "working.features_crossings")
#'
#' # Fish observations
#' frs_feature_find(conn, "working.streams",
#'   points_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
#'   col_id = "fish_observation_point_id",
#'   label_col = "species_code",
#'   to = "working.features_fish_obs")
#'
#' # Use as break source in habitat pipeline
#' frs_habitat(conn, "BULK", break_sources = list(
#'   list(table = "working.features_crossings",
#'        label_col = "label")))
#'
#' DBI::dbDisconnect(conn)
#' }
frs_feature_find <- function(conn, table, to = "working.features",
                             points_table = NULL, points = NULL,
                             where = NULL,
                             col_blk = "blue_line_key",
                             col_measure = "downstream_route_measure",
                             col_id = NULL,
                             label = NULL, label_col = NULL,
                             label_map = NULL,
                             overwrite = TRUE, append = FALSE) {
  .frs_validate_identifier(table, "streams table")
  .frs_validate_identifier(to, "destination table")

  has_table <- !is.null(points_table)
  has_points <- !is.null(points)

  if (!has_table && !has_points) {
    stop("Provide one of: points_table or points", call. = FALSE)
  }
  if (has_table && has_points) {
    stop("Provide only one of: points_table or points", call. = FALSE)
  }

  if (overwrite && !append) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  }

  if (has_table) {
    .frs_feature_find_table(conn, table, to, points_table,
      where = where, col_blk = col_blk, col_measure = col_measure,
      col_id = col_id, label = label, label_col = label_col,
      label_map = label_map, append = append)
  } else {
    .frs_feature_find_points(conn, table, to, points, col_id = col_id)
  }

  invisible(conn)
}


#' Find features from an existing point table
#' @noRd
.frs_feature_find_table <- function(conn, table, to, points_table,
                                     where = NULL,
                                     col_blk = "blue_line_key",
                                     col_measure = "downstream_route_measure",
                                     col_id = NULL,
                                     label = NULL, label_col = NULL,
                                     label_map = NULL,
                                     append = FALSE) {
  .frs_validate_identifier(points_table, "points table")
  .frs_validate_identifier(col_blk, "col_blk")
  .frs_validate_identifier(col_measure, "col_measure")
  if (!is.null(col_id)) .frs_validate_identifier(col_id, "col_id")

  clauses <- character(0)

  # Scope to BLKs present in the working streams table
  clauses <- c(clauses, sprintf(
    "%s IN (SELECT DISTINCT blue_line_key FROM %s)",
    col_blk, table))

  if (!is.null(where)) {
    clauses <- c(clauses, where)
  }

  where_clause <- paste(" WHERE", paste(clauses, collapse = " AND "))

  # Build label expression
  label_expr <- .frs_label_expr(label, label_col, label_map)

  # Build select columns
  id_expr <- if (!is.null(col_id)) {
    sprintf(", %s AS feature_id", col_id)
  } else {
    ""
  }

  select_sql <- sprintf(
    "SELECT DISTINCT %s AS blue_line_key, %s AS downstream_route_measure, %s, %s AS source%s FROM %s%s",
    col_blk, col_measure,
    label_expr,
    .frs_quote_string(points_table),
    id_expr,
    points_table, where_clause
  )

  id_col_def <- if (!is.null(col_id)) ", feature_id text" else ""
  cols_def <- sprintf("(blue_line_key integer,
     downstream_route_measure double precision,
     label text,
     source text%s)", id_col_def)

  if (append) {
    .frs_db_execute(conn, sprintf(
      "CREATE TABLE IF NOT EXISTS %s %s", to, cols_def))
    id_cols <- if (!is.null(col_id)) ", feature_id" else ""
    sql <- sprintf(
      "INSERT INTO %s (blue_line_key, downstream_route_measure, label, source%s) %s",
      to, id_cols, select_sql)
  } else {
    sql <- sprintf("CREATE TABLE %s AS %s", to, select_sql)
  }
  .frs_db_execute(conn, sql)
}


#' Find features from user-provided sf points
#' @noRd
.frs_feature_find_points <- function(conn, table, to, points,
                                      col_id = NULL) {
  if (!inherits(points, "sf")) {
    stop("points must be an sf object", call. = FALSE)
  }

  snapped <- frs_point_snap(conn, points)

  blk <- snapped$blue_line_key
  drm <- snapped$downstream_route_measure
  fid <- if (!is.null(col_id) && col_id %in% names(points)) {
    as.character(points[[col_id]])
  } else {
    rep("NULL", length(blk))
  }

  id_col_def <- if (!is.null(col_id)) ", feature_id text" else ""

  if (!is.null(col_id) && col_id %in% names(points)) {
    values <- paste(
      sprintf("(%d, %s, NULL, 'sf', %s)",
              as.integer(blk), as.numeric(drm),
              .frs_quote_string(fid)),
      collapse = ", ")
    sql <- sprintf(
      "CREATE TABLE %s (blue_line_key integer, downstream_route_measure double precision, label text, source text, feature_id text);
       INSERT INTO %s VALUES %s",
      to, to, values)
  } else {
    values <- paste(
      sprintf("(%d, %s, NULL, 'sf')", as.integer(blk), as.numeric(drm)),
      collapse = ", ")
    sql <- sprintf(
      "CREATE TABLE %s (blue_line_key integer, downstream_route_measure double precision, label text, source text);
       INSERT INTO %s VALUES %s",
      to, to, values)
  }
  .frs_db_execute(conn, sql)
}
