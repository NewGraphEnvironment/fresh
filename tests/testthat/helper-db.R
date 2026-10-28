# Skip when the connected DB lacks a schema. The default connection may be
# a local fwapg (whse_basemapping, bcfishobs, working) without the
# bcfishpass schema, which lives on the shared tunnel DB.
skip_if_no_schema <- function(schema) {
  has <- tryCatch({
    conn <- frs_db_conn()
    on.exit(DBI::dbDisconnect(conn))
    nrow(DBI::dbGetQuery(conn, sprintf(
      "SELECT 1 FROM pg_namespace WHERE nspname = %s",
      DBI::dbQuoteString(conn, schema)))) > 0L
  }, error = function(e) FALSE)
  testthat::skip_if_not(has, sprintf("schema %s not in DB", schema))
}

# Skip when a connection can't actually be made. A set credential env var
# doesn't mean the server is reachable, so gate on a real connect +
# SELECT 1. `connect` is any zero-arg function returning a DBI connection,
# so live tests against a non-default DB (e.g. the bcfishpass tunnel) can
# pass their own connector. Any error skips — including bad credentials or
# a broken connector — so the error text goes into the skip message.
skip_if_no_conn <- function(connect = frs_db_conn) {
  err <- tryCatch({
    conn <- connect()
    on.exit(DBI::dbDisconnect(conn))
    DBI::dbGetQuery(conn, "SELECT 1")
    NULL
  }, error = function(e) conditionMessage(e))
  if (!is.null(err)) {
    testthat::skip(paste("DB connection failed:", err))
  }
}

# A connection to a local fwapg, or a skip. `FRESH_PG*` env vars, defaulting to
# the `docker/` container, because these tests must not reach the shared
# instance the `PG*` vars name: a trial DROPs and recreates fwapg's functions
# inside its transaction, and a rollback there is not a full undo (`dblink` is
# installed on the shared host). Never on CI: they need the database.
frs_fwapg_conn <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("FRESH_PGHOST", "localhost"),
    port = as.integer(Sys.getenv("FRESH_PGPORT", "5432")),
    dbname = Sys.getenv("FRESH_PGDATABASE", "fwapg"),
    user = Sys.getenv("FRESH_PGUSER", "postgres"),
    password = Sys.getenv("FRESH_PGPASSWORD", "postgres")
  )
}

local_fwapg <- function(env = parent.frame()) {
  testthat::skip_on_ci()
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("RPostgres")
  conn <- tryCatch(frs_fwapg_conn(), error = function(e) NULL)
  if (is.null(conn)) testthat::skip("no local fwapg database")
  withr::defer(DBI::dbDisconnect(conn), envir = env)
  conn
}
