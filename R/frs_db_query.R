#' Query FWA PostgreSQL Database
#'
#' Executes a SQL query on an open connection. Uses [sf::st_read()] so
#' spatial columns are returned as sf geometry.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param query Character. SQL query string.
#'
#' @return An `sf` data frame (if the query returns geometry) or a plain
#'   data frame.
#'
#' @family database
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#' frs_db_query(conn, "SELECT * FROM whse_basemapping.fwa_lakes_poly LIMIT 5")
#' DBI::dbDisconnect(conn)
#' }
frs_db_query <- function(conn, query) {
  sf::st_read(conn, query = query)
}
