#' Reduce Barriers to Downstream-Most Per Flow Path
#'
#' Given a point table on an FWA stream network, remove any points that
#' have another point from the same table downstream of them on the same
#' upstream flow path. The result is the minimal set of points needed to
#' define access blocking per reach — equivalent to bcfishpass's
#' "non-minimal removal" step.
#'
#' On a full watershed group this typically reduces ~27,000 raw gradient
#' barriers to ~700 downstream-most per reach. Once the downstream-most
#' barrier on a path is present, any barrier upstream of it is redundant
#' for access-blocking purposes.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param from Character. Source table (schema-qualified) with barrier
#'   points. Must contain `blue_line_key`, `downstream_route_measure`,
#'   `wscode_ltree`, and `localcode_ltree` columns. Enrich with ltree
#'   columns via [frs_col_join()] if needed.
#' @param to Character. Destination table for minimal barriers.
#'   Default `"working.barriers_minimal"`.
#' @param tolerance Numeric. Tolerance in metres when comparing positions
#'   on the same reach. Default `1` — two points within 1 m on the same
#'   `blue_line_key` are treated as coincident and both are kept. Matches
#'   bcfishpass convention; prevents near-coincident gradient barriers
#'   (different gradient classes at the same vertex) from cancelling each
#'   other out.
#' @param overwrite Logical. If `TRUE` (default), drop `to` before
#'   creating.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family barriers
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Typical pipeline: detect gradient barriers, enrich with ltree cols,
#' # then reduce to the minimal set for segmentation.
#' frs_break_find(conn,
#'   table     = "whse_basemapping.fwa_stream_networks_sp",
#'   to        = "working.barriers_raw",
#'   attribute = "gradient",
#'   classes   = c("15" = 0.15, "20" = 0.20, "25" = 0.25, "30" = 0.30))
#'
#' frs_col_join(conn, "working.barriers_raw",
#'   from = "whse_basemapping.fwa_stream_networks_sp",
#'   cols = c("wscode_ltree", "localcode_ltree"),
#'   by   = "blue_line_key")
#'
#' n_before <- DBI::dbGetQuery(conn,
#'   "SELECT count(*) FROM working.barriers_raw")[[1]]
#'
#' frs_barriers_minimal(conn,
#'   from = "working.barriers_raw",
#'   to   = "working.barriers_minimal")
#'
#' n_after <- DBI::dbGetQuery(conn,
#'   "SELECT count(*) FROM working.barriers_minimal")[[1]]
#'
#' message("Reduced ", n_before, " -> ", n_after, " barriers (",
#'         round(100 * (1 - n_after / n_before)), "% removed)")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_barriers_minimal <- function(conn, from,
                                 to = "working.barriers_minimal",
                                 tolerance = 1,
                                 overwrite = TRUE) {
  .frs_validate_identifier(from, "source table")
  .frs_validate_identifier(to, "destination table")

  if (!is.numeric(tolerance) || length(tolerance) != 1L || tolerance < 0) {
    stop("tolerance must be a single non-negative numeric value",
         call. = FALSE)
  }

  required_cols <- c("blue_line_key", "downstream_route_measure",
                     "wscode_ltree", "localcode_ltree")

  if (inherits(conn, "DBIConnection")) {
    parts <- strsplit(from, "\\.", fixed = FALSE)[[1]]
    schema <- if (length(parts) == 2) parts[1] else "public"
    tbl <- parts[length(parts)]
    cols <- DBI::dbGetQuery(conn, sprintf(
      "SELECT column_name FROM information_schema.columns
       WHERE table_schema = %s AND table_name = %s",
      .frs_quote_string(schema), .frs_quote_string(tbl)
    ))$column_name
    missing <- setdiff(required_cols, cols)
    if (length(missing) > 0L) {
      stop(sprintf(
        paste0("Source table %s is missing required columns: %s. ",
               "Use frs_col_join() to add ltree columns from ",
               "fwa_stream_networks_sp."),
        from, paste(missing, collapse = ", ")
      ), call. = FALSE)
    }
  }

  if (overwrite) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  }

  .frs_db_execute(
    conn,
    sprintf("CREATE TABLE %s AS SELECT * FROM %s", to, from)
  )

  .frs_index_working(conn, to)

  # Delete rows that have another row downstream of them on the same flow
  # path. `whse_basemapping.fwa_upstream(A, B)` returns TRUE when B is
  # upstream of A. Here the query-level `a` is passed as the function-level
  # second point, and query `b` as function first — so the predicate
  # evaluates "query a is upstream of query b", and we delete `a` when any
  # such `b` exists. What remains is the downstream-most point per path.
  sql <- sprintf("
    DELETE FROM %s a
    WHERE EXISTS (
      SELECT 1 FROM %s b
      WHERE b.ctid <> a.ctid
        AND whse_basemapping.fwa_upstream(
          b.blue_line_key, b.downstream_route_measure,
          b.wscode_ltree, b.localcode_ltree,
          a.blue_line_key, a.downstream_route_measure,
          a.wscode_ltree, a.localcode_ltree,
          false, %s
        )
    )", to, to, format(tolerance, nsmall = 0, scientific = FALSE))

  .frs_db_execute(conn, sql)

  invisible(conn)
}
