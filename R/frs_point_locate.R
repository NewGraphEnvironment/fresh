#' Locate a Point on the FWA Stream Network
#'
#' Given a blue line key and downstream route measure, return the point
#' geometry on the stream network. Wraps fwapg `fwa_locatealong()`.
#'
#' @param blue_line_key Integer. Blue line key of the stream.
#' @param downstream_route_measure Numeric. Downstream route measure in metres.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame with a single point geometry.
#'
#' @family index
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Get the point at measure 1000 on a stream
#' pt <- frs_point_locate(blue_line_key = 360873822, downstream_route_measure = 1000)
#' }
frs_point_locate <- function(
    blue_line_key,
    downstream_route_measure,
    ...
) {
  sql <- sprintf(
    "SELECT * FROM whse_basemapping.fwa_locatealong(%s, %s)",
    as.integer(blue_line_key),
    downstream_route_measure
  )
  frs_db_query(sql, ...)
}
