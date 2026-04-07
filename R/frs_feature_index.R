#' Index Upstream/Downstream Features for Stream Segments
#'
#' For each segment in a stream table, find which features from a
#' feature table are upstream or downstream on the network. Stores
#' results as feature ID arrays — enabling queries like "which
#' crossings are between this segment and the ocean?"
#'
#' Uses `fwa_upstream()` or `fwa_downstream()` for network-aware
#' traversal via ltree codes.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param segments Character. Schema-qualified segmented streams table
#'   (from [frs_network_segment()]).
#' @param features Character. Schema-qualified feature table
#'   (from [frs_feature_find()]).
#' @param direction Character. `"downstream"` (features between segment
#'   and ocean) or `"upstream"` (features above segment). Default
#'   `"downstream"`.
#' @param col_segment_id Character. Segment ID column. Default
#'   `"id_segment"`.
#' @param col_feature_id Character. Feature ID column. Default
#'   `"feature_id"`. If the feature table has no ID column, uses
#'   row position.
#' @param to Character. Output table name. Default
#'   `"working.feature_index"`.
#' @param label_filter Character or `NULL`. SQL predicate to filter
#'   features by label before indexing (e.g. `"label = 'blocked'"`).
#' @param overwrite Logical. Drop `to` before creating. Default `TRUE`.
#' @param verbose Logical. Print progress. Default `TRUE`.
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
#' # Which crossings are downstream of each segment?
#' frs_feature_index(conn,
#'   segments = "fresh.streams",
#'   features = "working.features_crossings",
#'   direction = "downstream",
#'   to = "working.crossings_dnstr")
#'
#' # Query: segments with confirmed barriers downstream
#' DBI::dbGetQuery(conn, "
#'   SELECT s.id_segment, i.features_dnstr
#'   FROM fresh.streams s
#'   JOIN working.crossings_dnstr i ON s.id_segment = i.id_segment
#'   WHERE array_length(i.features_dnstr, 1) > 0
#'   LIMIT 10")
#'
#' # Fish observations upstream of each segment
#' frs_feature_index(conn,
#'   segments = "fresh.streams",
#'   features = "working.features_fish_obs",
#'   direction = "upstream",
#'   col_feature_id = "fish_observation_point_id",
#'   to = "working.fish_obs_upstr")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_feature_index <- function(conn, segments, features,
                               direction = "downstream",
                               col_segment_id = "id_segment",
                               col_feature_id = "feature_id",
                               to = "working.feature_index",
                               label_filter = NULL,
                               overwrite = TRUE,
                               verbose = TRUE) {
  .frs_validate_identifier(segments, "segments table")
  .frs_validate_identifier(features, "features table")
  .frs_validate_identifier(to, "output table")
  .frs_validate_identifier(col_segment_id, "segment ID column")
  .frs_validate_identifier(col_feature_id, "feature ID column")
  stopifnot(direction %in% c("downstream", "upstream"))

  if (overwrite) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  }

  t0 <- proc.time()

  # Build feature filter
  feat_where <- ""
  if (!is.null(label_filter)) {
    feat_where <- sprintf(" WHERE %s", label_filter)
  }

  # fwa_upstream(a, b) = TRUE means b is upstream of a
  # fwa_downstream(a, b) = TRUE means b is downstream of a
  #
  # For "downstream" direction: find features downstream of segment
  #   → fwa_downstream(segment_pos, feature_pos) = TRUE
  #   → feature is downstream of segment
  #
  # For "upstream" direction: find features upstream of segment
  #   → fwa_upstream(segment_pos, feature_pos) = TRUE
  #   → feature is upstream of segment

  fwa_func <- if (direction == "downstream") "fwa_downstream" else "fwa_upstream"
  col_suffix <- if (direction == "downstream") "dnstr" else "upstr"

  # Check if feature table has the feature_id column
  has_fid <- .frs_table_has_col_quick(conn, features, col_feature_id)
  fid_expr <- if (has_fid) {
    sprintf("f.%s", col_feature_id)
  } else {
    "f.ctid::text"
  }

  sql <- sprintf(
    "CREATE TABLE %s AS
     SELECT
       s.%s AS id_segment,
       array_agg(%s ORDER BY f.downstream_route_measure) FILTER (
         WHERE %s IS NOT NULL
       ) AS features_%s
     FROM %s s
     LEFT JOIN (
       SELECT * FROM %s%s
     ) f ON (
       -- Same BLK: compare measures
       (f.blue_line_key = s.blue_line_key
        AND f.downstream_route_measure %s s.downstream_route_measure)
       OR
       -- Cross BLK: ltree traversal
       (f.blue_line_key != s.blue_line_key
        AND f.wscode_ltree IS NOT NULL
        AND s.wscode_ltree IS NOT NULL
        AND %s(
          s.wscode_ltree, s.localcode_ltree,
          f.wscode_ltree, f.localcode_ltree
        ))
     )
     GROUP BY s.%s",
    to,
    col_segment_id,
    fid_expr,
    fid_expr,
    col_suffix,
    segments,
    features, feat_where,
    if (direction == "downstream") "<=" else ">=",
    fwa_func,
    col_segment_id
  )

  .frs_db_execute(conn, sql)
  .frs_index_working(conn, to)

  if (verbose) {
    stats <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int AS total,
              count(*) FILTER (WHERE features_%s IS NOT NULL)::int AS with_features
       FROM %s", col_suffix, to))
    elapsed <- round((proc.time() - t0)["elapsed"], 1)
    cat("  ", direction, ": ", stats$with_features, "/", stats$total,
        " segments have features (", elapsed, "s)\n", sep = "")
  }

  invisible(conn)
}


#' Quick check if a column exists (no information_schema query)
#' @noRd
.frs_table_has_col_quick <- function(conn, table, col) {
  if (!inherits(conn, "DBIConnection")) return(FALSE)
  tryCatch({
    DBI::dbGetQuery(conn, sprintf(
      "SELECT %s FROM %s LIMIT 0", col, table))
    TRUE
  }, error = function(e) FALSE)
}
