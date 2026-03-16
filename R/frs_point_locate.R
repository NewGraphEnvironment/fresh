#' Locate a Point on the FWA Stream Network
#'
#' Given a blue line key and downstream route measure, return the point
#' geometry on the stream network. Wraps fwapg `fwa_locatealong()`.
#'
#' @param blue_line_key Integer. Blue line key of the stream.
#' @param downstream_route_measure Numeric. Downstream route measure in metres.
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#'
#' @return An `sf` data frame with a single point geometry.
#'
#' @family index
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#' pt <- frs_point_locate(conn, blue_line_key = 360873822,
#'   downstream_route_measure = 1000)
#' DBI::dbDisconnect(conn)
#' }
frs_point_locate <- function(
    conn,
    blue_line_key,
    downstream_route_measure
) {
  sql <- sprintf(
    "SELECT * FROM whse_basemapping.fwa_locatealong(%s, %s)",
    as.integer(blue_line_key),
    downstream_route_measure
  )
  frs_db_query(conn, sql)
}
