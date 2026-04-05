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
  if (!nzchar(dbname)) stop("PG_DB_SHARE env var is not set", call. = FALSE)
  if (!nzchar(host)) stop("PG_HOST_SHARE env var is not set", call. = FALSE)
  if (!nzchar(port)) stop("PG_PORT_SHARE env var is not set", call. = FALSE)
  if (!nzchar(user)) stop("PG_USER_SHARE env var is not set", call. = FALSE)

  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = dbname,
    host = host,
    port = port,
    user = user,
    password = password
  )
}


#' Extract connection parameters from an existing connection
#'
#' Reads host, port, dbname, user from a live [RPostgres::Postgres()]
#' connection. Used by [frs_habitat()] to pass connection params to
#' parallel workers so they can open their own connections without
#' depending on `PG_*_SHARE` environment variables.
#'
#' Password is not available from `DBI::dbGetInfo()` (security). Must
#' be provided explicitly via `password` param or the connection will
#' fail for password-authenticated databases.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param password Character. Password for reconnection. Required for
#'   password-authenticated databases. Not needed for trust auth or
#'   `.pgpass` file.
#' @return Named list with `dbname`, `host`, `port`, `user`, `password`.
#' @noRd
.frs_conn_params <- function(conn, password = "") {
  info <- DBI::dbGetInfo(conn)
  list(
    dbname = info$dbname,
    host = info$host,
    port = info$port,
    user = info$username,
    password = password
  )
}
