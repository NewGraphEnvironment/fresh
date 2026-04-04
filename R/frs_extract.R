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
#'   - Named list — table+id lookup or blk+measure delineation
#' @param where Character or `NULL`. SQL predicate to filter rows. When both
#'   `aoi` and `where` are provided they are ANDed together. Example:
#'   `"watershed_group_code = 'BULK'"` for a fast column filter on tables
#'   that carry a watershed group code column.
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
#' # --- What frs_extract produces (bundled data) ---
#' # frs_extract copies source table rows into a writable working table.
#' # Here we show what the extracted data looks like using cached data
#' # from the Byman-Ailport subbasin (Upper Bulkley River).
#'
#' d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
#' streams <- d$streams
#'
#' # Streams have the columns you'd select: gradient, measures, geometry
#' names(streams)
#' nrow(streams)  # 2167 segments in this subbasin
#'
#' # Plot streams colored by gradient — this is what you'd extract
#' # to a working table before breaking/classifying
#' plot(streams["gradient"], main = "Stream gradient (Byman-Ailport)",
#'      breaks = c(0, 0.03, 0.05, 0.08, 0.15, 1), key.pos = 1)
#'
#' \dontrun{
#' # --- Live DB: extract the same Byman-Ailport area ---
#' conn <- frs_db_conn()
#' aoi <- d$aoi  # sf polygon from bundled data
#'
#' conn |> frs_extract(
#'   from = "bcfishpass.streams_vw",
#'   to = "working.demo_streams",
#'   cols = c("segmented_stream_id", "linear_feature_id", "blue_line_key",
#'            "gradient", "channel_width", "downstream_route_measure",
#'            "upstream_route_measure", "geom"),
#'   aoi = aoi,
#'   overwrite = TRUE
#' )
#'
#' # Read back and plot — should match the bundled data above
#' result <- frs_db_query(conn,
#'   "SELECT gradient, geom FROM working.demo_streams")
#' plot(result["gradient"], main = paste(nrow(result), "segments extracted"))
#'
#' # Clean up
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_streams")
#' DBI::dbDisconnect(conn)
#' }
frs_extract <- function(conn, from, to, cols = NULL, aoi = NULL,
                        where = NULL, overwrite = FALSE) {
  .frs_validate_identifier(from, "source table")
  .frs_validate_identifier(to, "destination table")

  if (!is.null(cols)) {
    stopifnot(is.character(cols), length(cols) > 0)
    for (col in cols) .frs_validate_identifier(col, "column")
  }

  # Build SELECT clause
  select_clause <- if (is.null(cols)) "*" else paste(cols, collapse = ", ")

  # Build WHERE clause from AOI and/or where predicate
  preds <- character(0)
  aoi_pred <- .frs_resolve_aoi(aoi, conn = conn)
  if (nzchar(aoi_pred)) preds <- c(preds, aoi_pred)
  if (!is.null(where)) {
    stopifnot(is.character(where), length(where) == 1, nzchar(where))
    preds <- c(preds, where)
  }
  where_clause <- if (length(preds) > 0) {
    paste(" WHERE", paste(preds, collapse = " AND "))
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

  .frs_index_working(conn, to)

  invisible(conn)
}
