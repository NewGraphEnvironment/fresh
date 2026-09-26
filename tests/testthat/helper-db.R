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
