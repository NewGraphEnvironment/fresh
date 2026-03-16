#' Get Waterbody Polygons Upstream or Downstream of a Network Position
#'
#' Returns lake or wetland polygons upstream or downstream of a given blue line
#' key and downstream route measure. Polygon tables (`fwa_lakes_poly`,
#' `fwa_wetlands_poly`) have NULL `localcode_ltree`, so `fwa_upstream()` /
#' `fwa_downstream()` can't query them directly. This function bridges through
#' the stream network: it runs the traversal on stream segments (which have
#' `localcode_ltree`), extracts distinct `waterbody_key` values, then joins to
#' the polygon table.
#'
#' See [fresh#8](https://github.com/NewGraphEnvironment/fresh/issues/8) for
#' background.
#'
#' @param blue_line_key Integer. Blue line key of the reference point.
#' @param downstream_route_measure Numeric. Downstream route measure of the
#'   reference point.
#' @param table Character. Fully qualified polygon table name. Default
#'   `"whse_basemapping.fwa_lakes_poly"`.
#' @param cols Character vector of column names to select from the polygon
#'   table. Default includes the most commonly used attributes.
#' @param direction Character. `"upstream"` (default) or `"downstream"`.
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#'
#' @return An `sf` data frame of waterbody polygons.
#'
#' @family traverse
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Upstream lakes from the Neexdzii Kwa / Wedzin Kwa confluence
#' lakes <- frs_waterbody_network(conn,
#'   blue_line_key = 360873822,
#'   downstream_route_measure = 166030
#' )
#'
#' # Upstream wetlands
#' wetlands <- frs_waterbody_network(conn,
#'   blue_line_key = 360873822,
#'   downstream_route_measure = 166030,
#'   table = "whse_basemapping.fwa_wetlands_poly"
#' )
#' DBI::dbDisconnect(conn)
#' }
frs_waterbody_network <- function(
    conn,
    blue_line_key,
    downstream_route_measure,
    table = "whse_basemapping.fwa_lakes_poly",
    cols = c(
      "waterbody_key", "waterbody_type", "gnis_name_1", "area_ha",
      "blue_line_key", "watershed_group_code", "geom"
    ),
    direction = "upstream"
) {
  direction <- match.arg(direction, c("upstream", "downstream"))
  fwa_fn <- switch(direction,
    upstream = "whse_basemapping.fwa_upstream",
    downstream = "whse_basemapping.fwa_downstream"
  )

  select_cols <- paste(paste0("p.", cols), collapse = ", ")

  sql <- sprintf(
    paste0(
      "WITH ref AS (\n",
      "  SELECT wscode_ltree, localcode_ltree\n",
      "  FROM whse_basemapping.fwa_stream_networks_sp\n",
      "  WHERE blue_line_key = %s\n",
      "    AND downstream_route_measure <= %s\n",
      "  ORDER BY downstream_route_measure DESC\n",
      "  LIMIT 1\n",
      "),\n",
      "network_wbkeys AS (\n",
      "  SELECT DISTINCT s.waterbody_key\n",
      "  FROM whse_basemapping.fwa_stream_networks_sp s, ref\n",
      "  WHERE %s(\n",
      "    ref.wscode_ltree, ref.localcode_ltree,\n",
      "    s.wscode_ltree, s.localcode_ltree\n",
      "  )\n",
      "  AND s.waterbody_key IS NOT NULL\n",
      ")\n",
      "SELECT %s\n",
      "FROM %s p\n",
      "JOIN network_wbkeys n ON p.waterbody_key = n.waterbody_key"
    ),
    as.integer(blue_line_key),
    downstream_route_measure,
    fwa_fn,
    select_cols,
    table
  )

  frs_db_query(conn, sql)
}
