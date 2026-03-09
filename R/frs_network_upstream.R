#' Get Stream Segments Upstream of a Network Position
#'
#' Returns all FWA stream segments upstream of a given blue line key and
#' downstream route measure. Uses the fwapg `fwa_upstream()` ltree comparison.
#'
#' @param blue_line_key Integer. Blue line key of the reference point.
#' @param downstream_route_measure Numeric. Downstream route measure of the
#'   reference point.
#' @param table Character. Fully qualified table name. Default
#'   `"whse_basemapping.fwa_stream_networks_sp"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used FWA stream attributes.
#' @param wscode_col Character. Name of the watershed code ltree column.
#'   Default `"wscode_ltree"`. Use `"wscode"` for bcfishpass views.
#' @param localcode_col Character. Name of the local code ltree column.
#'   Default `"localcode_ltree"`. Use `"localcode"` for bcfishpass views.
#' @param include_all Logical. If `TRUE`, include placeholder streams (999
#'   wscode) and unmapped tributaries (NULL localcode). Default `FALSE` filters
#'   these out. Only applied when querying the FWA base table.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame of upstream stream segments.
#'
#' @family traverse
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Get all streams upstream of a point on the Bulkley
#' upstream <- frs_network_upstream(
#'   blue_line_key = 360873822,
#'   downstream_route_measure = 166030
#' )
#'
#' # Use bcfishpass coho view
#' upstream <- frs_network_upstream(
#'   blue_line_key = 360873822,
#'   downstream_route_measure = 166030,
#'   table = "bcfishpass.streams_co_vw",
#'   wscode_col = "wscode",
#'   localcode_col = "localcode"
#' )
#' }
frs_network_upstream <- function(
    blue_line_key,
    downstream_route_measure,
    table = "whse_basemapping.fwa_stream_networks_sp",
    cols = c(
      "linear_feature_id", "blue_line_key", "waterbody_key", "edge_type",
      "gnis_name", "stream_order", "stream_magnitude", "gradient",
      "downstream_route_measure", "upstream_route_measure", "length_metre",
      "watershed_group_code", "wscode_ltree", "localcode_ltree", "geom"
    ),
    wscode_col = "wscode_ltree",
    localcode_col = "localcode_ltree",
    include_all = FALSE,
    ...
) {
  select_cols <- paste(paste0("s.", cols), collapse = ", ")

  guard_sql <- ""
  if (!include_all && .is_fwa_stream_table(table)) {
    guards <- .frs_stream_guards("s", wscode_col, localcode_col)
    guard_sql <- paste0("\n  AND ", paste(guards, collapse = "\n  AND "))
  }

  sql <- sprintf(
    paste0(
      "WITH ref AS (\n",
      "  SELECT %s AS wscode, %s AS localcode\n",
      "  FROM %s\n",
      "  WHERE blue_line_key = %s\n",
      "    AND downstream_route_measure <= %s\n",
      "  ORDER BY downstream_route_measure DESC\n",
      "  LIMIT 1\n",
      ")\n",
      "SELECT %s\n",
      "FROM %s s, ref\n",
      "WHERE whse_basemapping.fwa_upstream(\n",
      "  ref.wscode, ref.localcode,\n",
      "  s.%s, s.%s\n",
      ")%s"
    ),
    wscode_col, localcode_col,
    table,
    as.integer(blue_line_key),
    downstream_route_measure,
    select_cols,
    table,
    wscode_col, localcode_col,
    guard_sql
  )

  frs_db_query(sql, ...)
}
