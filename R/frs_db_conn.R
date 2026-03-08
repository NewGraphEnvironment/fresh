#' Connect to FWA PostgreSQL Database
#'
#' Opens a connection to a PostgreSQL database containing fwapg, bcfishpass,
#' and bcfishobs. Connection parameters default to environment variables
#' matching the `PG_*_SHARE` convention used by fpr.
#'
#' @param dbname Database name. Default: `Sys.getenv("PG_DB_SHARE")`.
#' @param host Host name. Default: `Sys.getenv("PG_HOST_SHARE")`.
#' @param port Port number. Default: `Sys.getenv("PG_PORT_SHARE")`.
#' @param user User name. Default: `Sys.getenv("PG_USER_SHARE")`.
#' @param password Password. Default: `Sys.getenv("PG_PASS_SHARE")`.
#'
#' @return A [DBI::DBIConnection-class] object.
#'
#' @family database
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#' DBI::dbDisconnect(conn)
#' }
frs_db_conn <- function(
    dbname = Sys.getenv("PG_DB_SHARE"),
    host = Sys.getenv("PG_HOST_SHARE"),
    port = Sys.getenv("PG_PORT_SHARE"),
    user = Sys.getenv("PG_USER_SHARE"),
    password = Sys.getenv("PG_PASS_SHARE")
) {
  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = dbname,
    host = host,
    port = port,
    user = user,
    password = password
  )
}
