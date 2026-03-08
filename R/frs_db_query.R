#' Query FWA PostgreSQL Database
#'
#' Connects via [frs_db_conn()], executes a SQL query, disconnects, and
#' returns the result. Uses [sf::st_read()] so spatial columns are returned
#' as sf geometry.
#'
#' @param query Character. SQL query string.
#' @param ... Additional arguments passed to [frs_db_conn()].
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
#' frs_db_query("SELECT * FROM whse_basemapping.fwa_lakes_poly LIMIT 5")
#' }
frs_db_query <- function(query, ...) {
  conn <- frs_db_conn(...)
  on.exit(DBI::dbDisconnect(conn))
  sf::st_read(conn, query = query)
}
