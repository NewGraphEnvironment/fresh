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
#' @section Timeouts:
#' libpq waits without limit by default, so a host that stops answering
#' blocks the call instead of raising an error. `frs_db_conn()` bounds both
#' waits, so a silent host fails the same way a refusing one does:
#'
#' - **Connecting.** `connect_timeout` seconds per host address tried
#'   (libpq counts each address, and treats 1 as 2). Resolved like the
#'   other fields: the argument, then `PGCONNECT_TIMEOUT`, then 10.
#' - **An established connection that goes silent.** TCP keepalives
#'   (`keepalives_idle = 60`, `keepalives_interval = 10`,
#'   `keepalives_count = 6`) drop a dead peer in about two minutes rather
#'   than the operating system's default of about two hours.
#'
#' A long-running query is not bounded: the server keeps answering
#' keepalives and acknowledging data while it works. Bound statements with
#' a server-side `statement_timeout` if you need to.
#'
#' Limits of these bounds:
#'
#' - Keepalives probe only a connection with nothing in flight. Once a
#'   query has been sent and not acknowledged, the operating system's
#'   retransmission timeout applies instead. On Linux, pass
#'   `tcp_user_timeout` (milliseconds) in `...` to shorten it. It is not a
#'   default: libpq knows the keyword only from PostgreSQL 12, refuses it
#'   before that, and applies it only where the system supports
#'   `TCP_USER_TIMEOUT`.
#' - Through a local tunnel (an SSH port forward, say), keepalives and
#'   acknowledgements come from the local end of the tunnel, so only the
#'   connect is bounded; a remote end that dies after connecting is
#'   detected by the tunnel's own settings, if at all.
#' - None of them apply to a Unix-domain socket.
#' - Keywords passed here take precedence over the same keywords in a
#'   `PGSERVICE` service file. Pass `NULL` in `...` to defer to the file
#'   for a keepalive keyword, or give `connect_timeout` explicitly.
#'
#' @param dbname Database name. Default `NULL` (resolved as above).
#' @param host Host name. Default `NULL`.
#' @param port Port number. Default `NULL`.
#' @param user User name. Default `NULL`.
#' @param password Password. Default `NULL`.
#' @param connect_timeout Seconds libpq waits for each connection attempt,
#'   a whole number; `0` waits without limit. Default `NULL`: libpq reads
#'   `PGCONNECT_TIMEOUT` when it is set, otherwise 10. See Timeouts.
#' @param ... Further libpq connection keywords, passed to
#'   [DBI::dbConnect()]. A keyword given here replaces the default of the
#'   same name (`keepalives = 0` turns keepalives off), and `NULL` removes
#'   it, leaving the value to libpq and the operating system.
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
#'
#' # A slow link: wait longer to connect
#' conn <- frs_db_conn(connect_timeout = 30)
#' DBI::dbDisconnect(conn)
#' }
frs_db_conn <- function(
    dbname = NULL,
    host = NULL,
    port = NULL,
    user = NULL,
    password = NULL,
    connect_timeout = NULL,
    ...
) {
  res <- .frs_conn_resolve(dbname = dbname, host = host, port = port,
                           user = user, password = password)
  bounds <- .frs_conn_bounds(connect_timeout = connect_timeout, ...)
  do.call(DBI::dbConnect,
          c(list(RPostgres::Postgres()), res$params, bounds))
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
    message("frs_db_conn(): using deprecated PG_*_SHARE env vars. Set the ",
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


#' Timeout keywords for a libpq connection
#'
#' One source for the bounds every connection fresh opens carries:
#' [frs_db_conn()] and the `frs_habitat()` workers (via
#' `.frs_conn_params()`). `connect_timeout` resolves explicit argument, then
#' `PGCONNECT_TIMEOUT` (left for libpq to read, so nothing is returned),
#' then 10 s. The idle-connection defaults merge with `...`: a named value
#' replaces a default, `NULL` removes it, and any other keyword passes
#' through to libpq.
#'
#' @return Named list of libpq connection keywords.
#' @noRd
.frs_conn_bounds <- function(connect_timeout = NULL, ...) {
  bounds <- list(keepalives = 1L, keepalives_idle = 60L,
                 keepalives_interval = 10L, keepalives_count = 6L)

  if (!is.null(connect_timeout)) {
    ok <- is.numeric(connect_timeout) && length(connect_timeout) == 1L &&
      is.finite(connect_timeout) && connect_timeout >= 0 &&
      connect_timeout <= .Machine$integer.max &&
      connect_timeout == round(connect_timeout)
    if (!ok) {
      stop("frs_db_conn(): connect_timeout must be one whole number of ",
           "seconds, 0 or more (0 waits without limit).", call. = FALSE)
    }
    bounds$connect_timeout <- as.integer(connect_timeout)
  } else if (!nzchar(Sys.getenv("PGCONNECT_TIMEOUT"))) {
    bounds$connect_timeout <- 10L
  }

  dots <- list(...)
  unnamed <- is.null(names(dots)) || any(!nzchar(names(dots)))
  if (length(dots) > 0L && unnamed) {
    stop("frs_db_conn(): arguments in ... must be named libpq connection ",
         "keywords.", call. = FALSE)
  }
  for (nm in names(dots)) {
    bounds[[nm]] <- dots[[nm]]
  }
  # RPostgres hands values to libpq as text, and a whole double such as
  # 3e5 prints as "3e+05", which libpq refuses as an integer.
  lapply(bounds, .frs_libpq_whole)
}


.frs_libpq_whole <- function(x) {
  if (!is.double(x) || length(x) != 1L || !is.finite(x) || x != round(x)) {
    return(x)
  }
  if (abs(x) <= .Machine$integer.max) {
    return(as.integer(x))
  }
  format(x, scientific = FALSE, trim = TRUE)
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
#' The timeout keywords from `.frs_conn_bounds()` ride along, so a worker's
#' connection is bounded the same way. A worker may not share the parent's
#' environment, so a `PGCONNECT_TIMEOUT` set in the parent is passed as an
#' explicit value. A `connect_timeout` or `...` the parent's
#' [frs_db_conn()] call was given cannot be read back from `conn`, so
#' workers get the defaults.
#'
#' @param password Character. Password for reconnection. Required for
#'   password-authenticated databases. Not needed for trust auth or
#'   `.pgpass` file.
#' @return Named list with `dbname`, `host`, `port`, `user`, `password`,
#'   then the timeout keywords.
#' @noRd
.frs_conn_params <- function(conn, password = "") {
  info <- DBI::dbGetInfo(conn)
  bounds <- .frs_conn_bounds()
  ct_env <- Sys.getenv("PGCONNECT_TIMEOUT")
  if (nzchar(ct_env)) bounds$connect_timeout <- ct_env
  c(list(
    dbname = info$dbname,
    host = info$host,
    port = info$port,
    user = info$username,
    password = password
  ), bounds)
}
