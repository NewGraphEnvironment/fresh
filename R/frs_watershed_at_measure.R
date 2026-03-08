#' Watershed at Measure
#'
#' Delineate a watershed polygon at a point on the stream network, defined by
#' blue line key and downstream route measure. Wraps the fwapg
#' `fwa_watershedatmeasure()` function.
#'
#' When `upstream_measure` is provided, returns the difference between the
#' downstream and upstream watersheds — the subbasin *between* the two points.
#'
#' @param blue_line_key Integer. FWA blue line key identifying the stream.
#' @param downstream_route_measure Numeric. Route measure of the downstream
#'   point (metres).
#' @param upstream_measure Numeric or `NULL`. Route measure of an upstream
#'   point. When provided, returns the watershed between the two measures
#'   (downstream minus upstream).
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame with a single polygon geometry.
#'
#' @family network
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Watershed upstream of a single point
#' ws <- frs_watershed_at_measure(360873822, 208877)
#'
#' # Subbasin between two points (network subtraction)
#' aoi <- frs_watershed_at_measure(360873822, 208877, upstream_measure = 233564)
#' }
frs_watershed_at_measure <- function(
    blue_line_key,
    downstream_route_measure,
    upstream_measure = NULL,
    ...
) {
  ws_down <- frs_db_query(
    sprintf(
      "SELECT geom FROM whse_basemapping.fwa_watershedatmeasure(%s, %s)",
      blue_line_key, downstream_route_measure
    ),
    ...
  )

  if (is.null(upstream_measure)) {
    return(ws_down)
  }

  if (upstream_measure <= downstream_route_measure) {
    stop("upstream_measure must be greater than downstream_route_measure")
  }

  ws_up <- frs_db_query(
    sprintf(
      "SELECT geom FROM whse_basemapping.fwa_watershedatmeasure(%s, %s)",
      blue_line_key, upstream_measure
    ),
    ...
  )

  sf::st_difference(ws_down, ws_up)
}
