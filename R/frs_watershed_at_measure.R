#' Watershed at Measure
#'
#' Delineate a watershed polygon at a point on the stream network, defined by
#' blue line key and downstream route measure. Wraps the fwapg
#' `fwa_watershedatmeasure()` function.
#'
#' When `upstream_measure` is provided, returns the difference between the
#' downstream and upstream watersheds — the subbasin *between* the two points.
#' The upstream point can be on a different blue line key (e.g. a tributary)
#' by specifying `upstream_blk`.
#'
#' @param blue_line_key Integer. FWA blue line key identifying the stream.
#' @param downstream_route_measure Numeric. Route measure of the downstream
#'   point (metres).
#' @param upstream_measure Numeric or `NULL`. Route measure of an upstream
#'   point. When provided, returns the watershed between the two measures
#'   (downstream minus upstream).
#' @param upstream_blk Integer or `NULL`. Blue line key for the upstream point.
#'   Defaults to `blue_line_key` (same stream). Use when the upstream point is
#'   on a tributary.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame with a single polygon geometry.
#'
#' @family watershed
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Watershed upstream of a single point
#' ws <- frs_watershed_at_measure(360873822, 208877)
#'
#' # Subbasin between two points on the same stream
#' aoi <- frs_watershed_at_measure(360873822, 208877, upstream_measure = 233564)
#'
#' # Subbasin with upstream point on a tributary (different BLK)
#' aoi <- frs_watershed_at_measure(360873822, 165115,
#'   upstream_measure = 838, upstream_blk = 360886221)
#' }
frs_watershed_at_measure <- function(
    blue_line_key,
    downstream_route_measure,
    upstream_measure = NULL,
    upstream_blk = NULL,
    ...
) {
  if (!is.numeric(blue_line_key) || length(blue_line_key) != 1 || is.na(blue_line_key)) {
    stop("blue_line_key must be a single numeric value")
  }
  if (!is.numeric(downstream_route_measure) || length(downstream_route_measure) != 1 ||
      is.na(downstream_route_measure)) {
    stop("downstream_route_measure must be a single numeric value")
  }
  if (!is.null(upstream_measure)) {
    if (!is.numeric(upstream_measure) || length(upstream_measure) != 1 ||
        is.na(upstream_measure)) {
      stop("upstream_measure must be a single numeric value or NULL")
    }
  }
  if (!is.null(upstream_blk)) {
    if (!is.numeric(upstream_blk) || length(upstream_blk) != 1 || is.na(upstream_blk)) {
      stop("upstream_blk must be a single numeric value or NULL")
    }
  }

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

  up_blk <- if (is.null(upstream_blk)) blue_line_key else upstream_blk

  if (up_blk == blue_line_key &&
      upstream_measure <= downstream_route_measure) {
    stop("upstream_measure must be greater than downstream_route_measure")
  }

  ws_up <- frs_db_query(
    sprintf(
      "SELECT geom FROM whse_basemapping.fwa_watershedatmeasure(%s, %s)",
      up_blk, upstream_measure
    ),
    ...
  )

  if (!sf::st_intersects(ws_down, ws_up, sparse = FALSE)[1, 1]) {
    stop("upstream watershed does not intersect downstream watershed; ",
         "points may not be on the same network")
  }

  sf::st_difference(ws_down, ws_up)
}
