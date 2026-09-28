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
