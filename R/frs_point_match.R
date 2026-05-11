#' Match Two Point Datasets Along FWA Network Within Instream Distance
#'
#' For each point in `table_a`, find the closest point in `table_b` on
#' the same FWA stream (`blue_line_key`) within `distance_max` instream
#' metres, and write the joined result to `table_to`. Each `table_a`
#' point links to at most one `table_b` point — the closest one within
#' the threshold; points with no match within the threshold appear in
#' the output with `<table_b_id_col>` set to NULL.
#'
#' Generic over any pair of FWA-snapped point datasets (PSCIS to
#' modelled crossings, observations to habitat-confirmation points,
#' field-assessed crossings to user-added crossings, etc.). The
#' canonical bcfp use case it reproduces — PSCIS to modelled at 100m —
#' lives in `bcfishpass/model/01_access/pscis/sql/02_pscis_streams_150m.sql`
#' at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c` (current `bcfishpass.log`
#' tunnel state at the time of writing).
#'
#' @param conn A [DBI::DBIConnection-class] object pointing at fwapg.
#' @param table_a Character. Schema-qualified source table. Points to
#'   match **from**. Must already be snapped to FWA — required columns
#'   are `blue_line_key` and `downstream_route_measure` plus the ID
#'   column named in `table_a_id_col`.
#' @param table_b Character. Schema-qualified target table. Points to
#'   match **to**. Same column requirements as `table_a`. The
#'   ID column named in `table_b_id_col` is the value carried over to
#'   `table_to`.
#' @param table_to Character. Schema-qualified destination. Created by
#'   this function via `DROP TABLE IF EXISTS` + `CREATE TABLE AS`.
#'   Columns are all of `table_a`'s columns plus `<table_b_id_col>`
#'   (the matched target ID, nullable) plus `distance_instream` (numeric,
#'   the absolute difference in `downstream_route_measure` between the
#'   matched pair; NULL for unmatched rows).
#' @param distance_max Numeric scalar. Maximum instream distance in
#'   metres. Computed as
#'   `ABS(table_a.downstream_route_measure - table_b.downstream_route_measure)`.
#'   bcfp's PSCIS↔modelled case uses 100.
#' @param table_a_id_col Character. Default `"id"`. The unique-key
#'   column on `table_a`.
#' @param table_b_id_col Character. Default `"id"`. The unique-key
#'   column on `table_b` carried forward into `table_to`.
#'
#' @return `conn` invisibly, for piping. Side effect: drops + recreates
#'   `table_to`.
#'
#' @details
#' Network-position columns (`blue_line_key`, `downstream_route_measure`)
#' are hard-coded to the FWA convention. Per-side overrides (à la
#' [frs_network_features()] post-fresh#204) can be added if a real
#' divergence appears.
#'
#' **Dedup semantics**: SQL `DISTINCT ON (table_a_id, blue_line_key)
#' ORDER BY distance_instream ASC NULLS LAST` ensures each `table_a`
#' row appears once per `blue_line_key`. The closest non-NULL match
#' wins. Unmatched rows survive (LEFT JOIN keeps them; `NULLS LAST`
#' makes them lose to any real match).
#'
#' **Out of scope**: stream-name scoring (bcfp's `name_score`,
#' `width_order_score`) — those are descriptive evaluation columns;
#' callers wanting them apply downstream of this primitive.
#'
#' @family network
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # PSCIS ↔ modelled crossings at 100m instream distance (bcfp parity)
#' frs_point_match(
#'   conn,
#'   table_a        = "working_adms.pscis_assessment_snapped",
#'   table_b        = "fresh.modelled_stream_crossings",
#'   table_to       = "working_adms.pscis",
#'   distance_max   = 100,
#'   table_a_id_col = "stream_crossing_id",
#'   table_b_id_col = "modelled_crossing_id"
#' )
#'
#' # Field-assessed crossings vs user-added crossings (deduplication)
#' frs_point_match(
#'   conn,
#'   table_a        = "wsg_adms.crossings_field",
#'   table_b        = "wsg_adms.crossings_user",
#'   table_to       = "wsg_adms.crossings_matched",
#'   distance_max   = 50,
#'   table_a_id_col = "field_id",
#'   table_b_id_col = "user_id"
#' )
#'
#' DBI::dbDisconnect(conn)
#' }
frs_point_match <- function(
    conn,
    table_a,
    table_b,
    table_to,
    distance_max,
    table_a_id_col = "id",
    table_b_id_col = "id") {

  if (missing(table_a) || !is.character(table_a) ||
        length(table_a) != 1L || !nzchar(table_a)) {
    stop("`table_a` is required (no default).", call. = FALSE)
  }
  if (missing(table_b) || !is.character(table_b) ||
        length(table_b) != 1L || !nzchar(table_b)) {
    stop("`table_b` is required (no default).", call. = FALSE)
  }
  if (missing(table_to) || !is.character(table_to) ||
        length(table_to) != 1L || !nzchar(table_to)) {
    stop("`table_to` is required (no default).", call. = FALSE)
  }
  if (missing(distance_max) || !is.numeric(distance_max) ||
        length(distance_max) != 1L || is.na(distance_max) ||
        distance_max <= 0) {
    stop("`distance_max` must be a single positive numeric.", call. = FALSE)
  }

  .frs_validate_identifier(table_a, "table_a")
  .frs_validate_identifier(table_b, "table_b")
  .frs_validate_identifier(table_to, "table_to")
  .frs_validate_identifier(table_a_id_col, "table_a_id_col")
  .frs_validate_identifier(table_b_id_col, "table_b_id_col")

  if (identical(table_a_id_col, table_b_id_col)) {
    stop("`table_a_id_col` and `table_b_id_col` must differ; the output ",
         "carries both columns side-by-side, so identical names would ",
         "collide. Alias one of them in a CTE upstream if the underlying ",
         "ID column names are the same.", call. = FALSE)
  }

  # SQL composition. Argument order in sprintf:
  #   1 = table_a              (FROM)
  #   2 = table_b              (LEFT JOIN)
  #   3 = table_to             (CREATE TABLE)
  #   4 = table_a_id_col       (DISTINCT ON + ORDER BY)
  #   5 = table_b_id_col       (the linking column carried to output)
  #   6 = distance_max         (numeric literal in the join predicate)
  #
  # LEFT JOIN preserves all table_a rows even when there's no match
  # within `distance_max` on the same blue_line_key. The DISTINCT ON
  # then keeps one row per (table_a_id, blue_line_key) — the matched
  # one if it exists, the un-matched row otherwise. NULLS LAST on
  # distance_instream ensures real matches outrank unmatched rows.
  sql_fmt <- "
    DROP TABLE IF EXISTS %3$s;
    CREATE TABLE %3$s AS
    SELECT DISTINCT ON (a.%4$s, a.blue_line_key)
      a.*,
      b.%5$s AS %5$s,
      ABS(a.downstream_route_measure - b.downstream_route_measure)
        AS distance_instream
    FROM %1$s a
    LEFT JOIN %2$s b
      ON a.blue_line_key = b.blue_line_key
     AND ABS(a.downstream_route_measure - b.downstream_route_measure)
         < %6$s
    ORDER BY a.%4$s, a.blue_line_key,
             ABS(a.downstream_route_measure - b.downstream_route_measure)
             ASC NULLS LAST"

  sql <- sprintf(
    sql_fmt,
    table_a,
    table_b,
    table_to,
    table_a_id_col,
    table_b_id_col,
    .frs_sql_num(distance_max)
  )

  .frs_db_execute(conn, sql)

  invisible(conn)
}
