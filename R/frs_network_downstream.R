#' Get Stream Segments Downstream of a Network Position
#'
#' Returns all FWA stream segments downstream of a given blue line key and
#' downstream route measure. Uses the fwapg `fwa_downstream()` ltree comparison.
#'
#' @param blue_line_key Integer. Blue line key of the reference point.
#' @param downstream_route_measure Numeric. Downstream route measure of the
#'   reference point.
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
    ...
) {
  sql <- sprintf(
    paste0(
      "WITH ref AS (\n",
      "  SELECT wscode_ltree, localcode_ltree\n",
      "  FROM whse_basemapping.fwa_stream_networks_sp\n",
      "  WHERE blue_line_key = %s\n",
      "    AND downstream_route_measure <= %s\n",
      "    AND upstream_route_measure > %s\n",
      "  LIMIT 1\n",
      ")\n",
      "SELECT s.*\n",
      "FROM whse_basemapping.fwa_stream_networks_sp s, ref\n",
      "WHERE whse_basemapping.fwa_downstream(\n",
      "  ref.wscode_ltree, ref.localcode_ltree,\n",
      "  s.wscode_ltree, s.localcode_ltree\n",
      ")"
    ),
    as.integer(blue_line_key),
    downstream_route_measure,
    downstream_route_measure
  )

  frs_db_query(sql, ...)
}
