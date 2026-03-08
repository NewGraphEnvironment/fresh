#' Get Stream Segments Downstream of a Network Position
#'
#' Returns all FWA stream segments downstream of a given blue line key and
#' downstream route measure. Uses the fwapg `fwa_downstream()` ltree comparison.
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
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame of downstream stream segments.
#'
#' @family traverse
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Get all streams downstream of a point
#' downstream <- frs_network_downstream(
#'   blue_line_key = 360873822,
#'   downstream_route_measure = 166030
#' )
#' }
frs_network_downstream <- function(
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
    ...
) {
  select_cols <- paste(paste0("s.", cols), collapse = ", ")

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
      "WHERE whse_basemapping.fwa_downstream(\n",
      "  ref.wscode, ref.localcode,\n",
      "  s.%s, s.%s\n",
      ")"
    ),
    wscode_col, localcode_col,
    table,
    as.integer(blue_line_key),
    downstream_route_measure,
    select_cols,
    table,
    wscode_col, localcode_col
  )

  frs_db_query(sql, ...)
}
