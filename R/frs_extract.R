#' Stage Data to Working Schema
#'
#' Copy rows from a read-only source table into a writable working schema
#' table via `CREATE TABLE AS SELECT`. The working copy can then be modified
#' by [frs_break_apply()], [frs_classify()], and [frs_aggregate()].
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param from Character. Schema-qualified source table
#'   (e.g. `"bcfishpass.streams_co_vw"`).
#' @param to Character. Schema-qualified destination table
#'   (e.g. `"working.streams_co"`).
#' @param cols Character vector of column names to select, or `NULL` for all
#'   columns (`SELECT *`).
#' @param aoi AOI specification passed to `.frs_resolve_aoi()`. One of:
#'   - `NULL` — no spatial filter (copy all rows)
#'   - Character vector — watershed group code(s)
#'   - `sf`/`sfc` polygon — spatial intersection
#'   - Named list — see [.frs_resolve_aoi()] for details
#' @param overwrite Logical. If `TRUE`, drop the destination table before
#'   creating. If `FALSE` (default), error when the table already exists.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Extract coho streams for Bulkley watershed group
#' conn |> frs_extract(
#'   from = "bcfishpass.streams_co_vw",
#'   to = "working.streams_co",
#'   aoi = "BULK"
#' )
#'
#' # Extract specific columns with overwrite
#' conn |> frs_extract(
#'   from = "bcfishpass.streams_co_vw",
#'   to = "working.streams_co",
#'   cols = c("segmented_stream_id", "blue_line_key", "gradient",
#'            "channel_width", "geom"),
#'   aoi = "BULK",
#'   overwrite = TRUE
#' )
#'
#' DBI::dbDisconnect(conn)
#' }
frs_extract <- function(conn, from, to, cols = NULL, aoi = NULL,
                        overwrite = FALSE) {
  .frs_validate_identifier(from, "source table")
  .frs_validate_identifier(to, "destination table")

  if (!is.null(cols)) {
    stopifnot(is.character(cols), length(cols) > 0)
    for (col in cols) .frs_validate_identifier(col, "column")
  }

  # Build SELECT clause
  select_clause <- if (is.null(cols)) "*" else paste(cols, collapse = ", ")

  # Build WHERE clause from AOI
  aoi_pred <- .frs_resolve_aoi(aoi, conn = conn)
  where_clause <- if (nzchar(aoi_pred)) {
    paste(" WHERE", aoi_pred)
  } else {
    ""
  }

  # Drop existing table if overwrite requested
  if (overwrite) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  }

  # CREATE TABLE AS SELECT
  sql <- sprintf("CREATE TABLE %s AS SELECT %s FROM %s%s",
                 to, select_clause, from, where_clause)
  .frs_db_execute(conn, sql)

  invisible(conn)
}
