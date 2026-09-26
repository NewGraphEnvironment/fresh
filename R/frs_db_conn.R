#' Connect to FWA PostgreSQL Database
#'
#' Opens a connection to a PostgreSQL database containing fwapg (and
#' optionally bcfishpass / bcfishobs). Connection parameters follow the
#' standard libpq conventions, so `frs_db_conn()` connects to whatever the
#' caller's environment points at, e.g. the local fwapg Docker database
#' in `docker/`, or a remote host.
#'
#' Parameters resolve in this order:
#'
#' 1. Explicit arguments, field by field.
#' 2. Standard libpq environment variables (`PGHOST`, `PGPORT`,
#'    `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGSERVICE`, ...). If any of
#'    `PGHOST`, `PGHOSTADDR`, `PGPORT`, `PGDATABASE`, `PGUSER` or
#'    `PGSERVICE` is set, libpq resolves the unset fields itself and the
#'    legacy variables below are ignored.
#' 3. Legacy `PG_*_SHARE` variables (`PG_DB_SHARE`, `PG_HOST_SHARE`,
#'    `PG_PORT_SHARE`, `PG_USER_SHARE`, `PG_PASS_SHARE`), used only when
#'    none of the standard variables are set. Deprecated: a message is
#'    shown once per session.
#' 4. libpq defaults (local socket or `localhost`, OS user name,
#'    `~/.pgpass`, `~/.pg_service.conf`).
#'
#' The two variable groups are never mixed, so a legacy database name can
#' not be paired with a standard host.
#'
#' @param dbname Database name. Default `NULL` (resolved as above).
#' @param host Host name. Default `NULL`.
#' @param port Port number. Default `NULL`.
#' @param user User name. Default `NULL`.
#' @param password Password. Default `NULL`.
#'
#' @return A [DBI::DBIConnection-class] object.
#'
#' @family database
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Standard libpq env vars, e.g. in ~/.Renviron:
#' #   PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg PGUSER=postgres
#' conn <- frs_db_conn()
#' DBI::dbDisconnect(conn)
#'
#' # Explicit arguments override the environment per field
#' conn <- frs_db_conn(port = 63333, dbname = "bcfishpass")
#' DBI::dbDisconnect(conn)
#' }
frs_db_conn <- function(
    dbname = NULL,
    host = NULL,
    port = NULL,
    user = NULL,
    password = NULL
) {
  res <- .frs_conn_resolve(dbname = dbname, host = host, port = port,
                           user = user, password = password)
  do.call(DBI::dbConnect, c(list(RPostgres::Postgres()), res$params))
}


# Package-level session state (once-per-session messages)
.frs_state <- new.env(parent = emptyenv())
.frs_state$share_msg_shown <- FALSE


#' Resolve connection parameters for frs_db_conn()
#'
#' Explicit args win per field. Remaining fields come from one env-var
#' group only: standard libpq vars (left for libpq to read), else legacy
#' `PG_*_SHARE` (passed explicitly, libpq never reads them), else libpq
#' defaults. `NULL` and `""` are both treated as unset.
#'
#' @return List with `params` (named list of non-empty args for
#'   `DBI::dbConnect()`) and `source` (`"standard"`, `"share"` or
#'   `"default"`).
#' @noRd
.frs_conn_resolve <- function(dbname = NULL, host = NULL, port = NULL,
                              user = NULL, password = NULL) {
  params <- list(dbname = dbname, host = host, port = port, user = user,
                 password = password)
  params <- params[vapply(params, .frs_is_set, logical(1))]

  cols_std <- c("PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
                "PGSERVICE")
  cols_share <- c(dbname = "PG_DB_SHARE", host = "PG_HOST_SHARE",
                  port = "PG_PORT_SHARE", user = "PG_USER_SHARE",
                  password = "PG_PASS_SHARE")

  if (any(nzchar(Sys.getenv(cols_std)))) {
    return(list(params = params, source = "standard"))
  }

  vals_share <- Sys.getenv(cols_share)
  names(vals_share) <- names(cols_share)
  if (!any(nzchar(vals_share[names(vals_share) != "password"]))) {
    return(list(params = params, source = "default"))
  }

  if (!isTRUE(.frs_state$share_msg_shown)) {
    message(
      "frs_db_conn(): using deprecated PG_*_SHARE env vars. Set the ",
      "standard PGHOST / PGPORT / PGDATABASE / PGUSER / PGPASSWORD ",
      "instead. (Shown once per session.)")
    .frs_state$share_msg_shown <- TRUE
  }
  for (nm in names(vals_share)) {
    if (is.null(params[[nm]]) && nzchar(vals_share[[nm]])) {
      params[[nm]] <- unname(vals_share[[nm]])
    }
  }
  params <- params[intersect(names(cols_share), names(params))]
  list(params = params, source = "share")
}


.frs_is_set <- function(x) {
  !is.null(x) && length(x) == 1L && !is.na(x) && nzchar(as.character(x))
}


#' Extract connection parameters from an existing connection
#'
#' Reads host, port, dbname, user from a live [RPostgres::Postgres()]
#' connection. Used by [frs_habitat()] to pass connection params to
#' parallel workers so they can open their own connections without
#' depending on the workers' environment variables.
#'
#' Password is not available from `DBI::dbGetInfo()` (security). Must
#' be provided explicitly via `password` param or the connection will
#' fail for password-authenticated databases. An empty `password` lets
#' libpq fall back to the worker's `PGPASSWORD` / `~/.pgpass`, which is
#' wrong when the parent connected via the legacy `PG_PASS_SHARE`, so
#' pass `password` to [frs_habitat()] in that case.
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
