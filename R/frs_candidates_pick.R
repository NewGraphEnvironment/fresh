#' Score, Filter, and Dedup Candidates per Key
#'
#' Third primitive in fresh's point-handling family (alongside
#' [frs_point_snap()] and [frs_point_match()]). Given a candidates
#' table where multiple rows can share the same key value, optionally
#' compute a per-row score from a caller-supplied SQL expression,
#' optionally filter disqualifiers via a caller-supplied WHERE clause,
#' then keep one row per key by `DISTINCT ON (col_key) ORDER BY ...`.
#'
#' Designed for the "score + filter + dedup per key" pattern that
#' shows up wherever column-to-column comparisons disambiguate matches
#' beyond pure geometry: stream-name matching, watershed-group
#' agreement, species-code overlap, assessment-date proximity, channel-
#' width × stream-order compatibility, etc. Composes with
#' [frs_point_snap()] (upstream — produces multi-candidate per key) and
#' [frs_point_match()] (downstream — operates on single-candidate-per-key
#' input).
#'
#' Reproduces bcfp's `04_pscis.sql` PSCIS-to-stream selection pattern
#' (`smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`) when the caller supplies
#' the bcfp `name_score` and `weighted_distance` ORDER BY clauses.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param table_in Character. Schema-qualified candidates table.
#'   Multiple rows per `col_key` value are expected (the whole point —
#'   pick one). Typically the output of `frs_point_snap(num_features = N)`
#'   optionally enriched with JOINs to pull in score-bearing columns.
#' @param table_to Character. Schema-qualified destination. Dropped +
#'   recreated by this function via DDL.
#' @param col_key Character. Column on `table_in` that groups
#'   competing rows. After this function runs, `table_to` has at most
#'   one row per distinct `col_key` value.
#' @param exp_score Character or `NULL`. Optional SQL fragment yielding
#'   a `score` column — evaluated per row. The caller writes the SQL.
#'   Example: `"CASE WHEN LOWER(a.stream_name) = LOWER(b.gnis_name)
#'   THEN 100 ELSE 0 END"`. When supplied, the output table gains a
#'   `score` column; when `NULL`, no score column is added.
#' @param exp_filter Character or `NULL`. Optional SQL `WHERE` clause
#'   for disqualifiers, evaluated against `table_in` (or the scored
#'   intermediate when `exp_score` is set). Example: `"score >= 0"` to
#'   drop rows with score < 0. The caller writes the SQL.
#' @param order_by Character vector. Sequence of `"<expr> ASC|DESC"`
#'   strings (e.g. `c("score DESC", "distance_to_stream ASC")`) used
#'   for the `DISTINCT ON (col_key) ORDER BY ...` dedup tiebreak.
#'   `col_key` is prepended automatically (PostgreSQL requires the
#'   leading `ORDER BY` columns to match `DISTINCT ON`).
#'
#' @return `conn` invisibly, for piping. Side effect: drops + recreates
#'   `table_to` with all `table_in` columns plus (when `exp_score` is
#'   supplied) a `score` column, deduped to one row per `col_key`.
#'
#' @details
#' SQL composition:
#'
#' \preformatted{
#' WITH scored AS (
#'   SELECT *, (<exp_score>) AS score
#'   FROM <table_in>
#' )
#' SELECT DISTINCT ON (<col_key>) *
#' FROM scored
#' WHERE <exp_filter>
#' ORDER BY <col_key>, <order_by[1]>, <order_by[2]>, ...
#' }
#'
#' The `WITH scored AS` CTE is omitted when `exp_score = NULL` (and the
#' caller's `order_by` cannot reference a `score` column).
#' The `WHERE` clause is omitted when `exp_filter = NULL`.
#'
#' **Caller's responsibilities** (NOT this primitive's):
#' - Producing the candidates table (multi-row-per-key).
#' - Enriching it with JOINs to pull in score-bearing columns.
#' - Writing `exp_score` / `exp_filter` SQL.
#' - Writing `order_by` clauses.
#'
#' **What this primitive does**:
#' - Sanitizes `col_key`, `table_in`, `table_to` identifiers.
#' - Composes the CTE + SELECT.
#' - Executes via `DBI::dbExecute()`.
#'
#' @family network
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # bcfp PSCIS-to-stream selection (reproduces 04_pscis.sql logic):
#' # caller has staged candidates with stream_name (from PSCIS) and
#' # gnis_name (from FWA) columns joined in.
#' frs_candidates_pick(
#'   conn,
#'   table_in   = "working_bulk.pscis_stream_candidates",
#'   table_to   = "working_bulk.pscis",
#'   col_key    = "stream_crossing_id",
#'   exp_score  = "CASE
#'                  WHEN LOWER(stream_name) = LOWER(gnis_name) THEN 100
#'                  WHEN stream_name IS NULL OR gnis_name IS NULL THEN 0
#'                  ELSE -100
#'                END",
#'   exp_filter = "score >= 0",
#'   order_by   = c("score DESC", "distance_to_stream ASC")
#' )
#'
#' # Generic field-assessed vs user-added crossings dedup:
#' frs_candidates_pick(
#'   conn,
#'   table_in   = "wsg_adms.crossings_candidates",
#'   table_to   = "wsg_adms.crossings",
#'   col_key    = "site_id",
#'   order_by   = c("assessment_date DESC", "distance_to_stream ASC")
#' )
#'
#' DBI::dbDisconnect(conn)
#' }
frs_candidates_pick <- function(
    conn,
    table_in,
    table_to,
    col_key,
    exp_score = NULL,
    exp_filter = NULL,
    order_by) {

  if (missing(table_in) || !is.character(table_in) ||
        length(table_in) != 1L || !nzchar(table_in)) {
    stop("`table_in` is required (no default).", call. = FALSE)
  }
  if (missing(table_to) || !is.character(table_to) ||
        length(table_to) != 1L || !nzchar(table_to)) {
    stop("`table_to` is required (no default).", call. = FALSE)
  }
  if (missing(col_key) || !is.character(col_key) ||
        length(col_key) != 1L || !nzchar(col_key)) {
    stop("`col_key` is required (no default).", call. = FALSE)
  }
  if (missing(order_by) || !is.character(order_by) ||
        length(order_by) < 1L || any(!nzchar(order_by))) {
    stop("`order_by` is required: a character vector of at least one ",
         "ORDER BY clause (e.g. c(\"score DESC\", \"distance ASC\")).",
         call. = FALSE)
  }

  .frs_validate_identifier(table_in, "table_in")
  .frs_validate_identifier(table_to, "table_to")
  .frs_validate_identifier(col_key, "col_key")

  if (!is.null(exp_score)) {
    if (!is.character(exp_score) || length(exp_score) != 1L ||
          !nzchar(exp_score)) {
      stop("`exp_score`, when supplied, must be a single non-empty ",
           "character string (SQL fragment yielding a score column).",
           call. = FALSE)
    }
  }
  if (!is.null(exp_filter)) {
    if (!is.character(exp_filter) || length(exp_filter) != 1L ||
          !nzchar(exp_filter)) {
      stop("`exp_filter`, when supplied, must be a single non-empty ",
           "character string (SQL WHERE clause).", call. = FALSE)
    }
  }

  # When exp_score is set we add a `score` column to the output. Guard
  # against table_in already having a `score` column (would collide).
  if (!is.null(exp_score)) {
    cols_in <- .frs_table_columns(conn, table_in)
    if ("score" %in% cols_in) {
      stop("`table_in` already has a `score` column; frs_candidates_pick ",
           "would add another via `exp_score`. Rename the existing column ",
           "in a CTE upstream or set `exp_score = NULL` and reference the ",
           "existing column in `order_by`.", call. = FALSE)
    }
  }

  # ORDER BY composition: col_key first (PostgreSQL requires DISTINCT ON
  # leading columns to match), then caller's order_by clauses.
  order_by_sql <- paste(
    c(col_key, order_by),
    collapse = ", "
  )

  # Filter clause composition: only emit WHERE when supplied.
  where_clause <- if (!is.null(exp_filter)) {
    sprintf("WHERE %s", exp_filter)
  } else {
    ""
  }

  # FROM source: scored CTE if exp_score set, otherwise table_in directly.
  if (!is.null(exp_score)) {
    from_sql <- sprintf(
      "WITH scored AS (\n  SELECT *, (%s) AS score\n  FROM %s\n)\nSELECT DISTINCT ON (%s) *\nFROM scored",
      exp_score, table_in, col_key
    )
  } else {
    from_sql <- sprintf(
      "SELECT DISTINCT ON (%s) *\nFROM %s",
      col_key, table_in
    )
  }

  # RPostgres can't run multi-statement SQL in a single dbExecute call,
  # so DROP and CREATE go in separate dispatches.
  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", table_to))

  sql <- sprintf(
    "CREATE TABLE %s AS\n%s\n%s\nORDER BY %s",
    table_to,
    from_sql,
    where_clause,
    order_by_sql
  )

  .frs_db_execute(conn, sql)

  invisible(conn)
}
