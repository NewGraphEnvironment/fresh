#' Match Two Point Datasets Along FWA Network Within Instream Distance
#'
#' For each point in `table_a`, find the closest point in `table_b` on
#' the same FWA stream (`blue_line_key`) within `distance_max` instream
#' metres, and write the joined result to `table_to`. Each `table_a`
#' point links to at most one `table_b` point — the closest one within
#' the threshold; points with no match within the threshold appear in
#' the output with `<col_b_id>` set to NULL.
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
#'   column named in `col_a_id`.
#' @param table_b Character. Schema-qualified target table. Points to
#'   match **to**. Same column requirements as `table_a`. The
#'   ID column named in `col_b_id` is the value carried over to
#'   `table_to`.
#' @param table_to Character. Schema-qualified destination. Created by
#'   this function via `DROP TABLE IF EXISTS` + `CREATE TABLE AS`.
#'   Columns are all of `table_a`'s columns plus `<col_b_id>`
#'   (the matched target ID, nullable) plus `distance_instream` (numeric,
#'   the absolute difference in `downstream_route_measure` between the
#'   matched pair; NULL for unmatched rows).
#' @param distance_max Numeric scalar. Maximum instream distance in
#'   metres. Computed as
#'   `ABS(table_a.downstream_route_measure - table_b.downstream_route_measure)`.
#'   bcfp's PSCIS↔modelled case uses 100.
#' @param col_a_id Character. Default `"id"`. The unique-key
#'   column on `table_a`.
#' @param col_b_id Character. Default `"id"`. The unique-key
#'   column on `table_b` carried forward into `table_to`.
#' @param tiebreak Character. Distance metric used to pick a winner
#'   when multiple `table_a` rows compete for the same `table_b` row
#'   (b-side dedup). One of:
#'   - `"instream"` (default): order by `ABS(drm_a - drm_b)`. Self-
#'     consistent with the threshold filter; works on any FWA-snapped
#'     point dataset without requiring geometry columns.
#'   - `"planar"`: order by `ST_Distance(a.geom, b.geom)`. Mirrors
#'     bcfp's `02_pscis_streams_150m.sql` tiebreak (line 190). Requires
#'     a `geom` column on both `table_a` and `table_b` (FWA convention).
#'     Use this when bcfp-byte-identical output is required and your
#'     input tables carry geom.
#'
#'   The threshold filter (`distance_max`) and the a-side dedup tiebreak
#'   are instream-distance in **both** modes — only the b-side dedup
#'   tiebreak changes. The two modes converge when no `table_b` row has
#'   multiple competing `table_a` matches; they diverge only in
#'   clustered-point edge cases.
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
#' **Single-stream-per-input assumption.** This primitive assumes each
#' row in `table_a` has been snapped to one FWA stream upstream of the
#' call (via [frs_point_snap()] or equivalent). It does not consider
#' alternate stream candidates within a planar buffer. bcfp's
#' `02_pscis_streams_150m.sql` does — it starts from raw PSCIS points,
#' considers all FWA streams within 150m planar, then scores by
#' name/width to pick the best (PSCIS, stream) pair. As a result,
#' `frs_point_match` matches bcfp's final `bcfishpass.pscis.modelled_crossing_id`
#' byte-identically when the input PSCIS lands on the same stream bcfp
#' chose; ~0.5% edge cases on a large WSG (BULK validation 2026-05-11)
#' diverge where bcfp's multi-stream consideration picks a different
#' stream than the caller's single-stream snap. Workaround: caller can
#' run multi-stream candidate selection before calling this primitive.
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
#'   col_a_id = "stream_crossing_id",
#'   col_b_id = "modelled_crossing_id"
#' )
#'
#' # Field-assessed crossings vs user-added crossings (deduplication)
#' frs_point_match(
#'   conn,
#'   table_a        = "wsg_adms.crossings_field",
#'   table_b        = "wsg_adms.crossings_user",
#'   table_to       = "wsg_adms.crossings_matched",
#'   distance_max   = 50,
#'   col_a_id = "field_id",
#'   col_b_id = "user_id"
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
    col_a_id = "id",
    col_b_id = "id",
    tiebreak = c("instream", "planar")) {

  tiebreak <- match.arg(tiebreak)

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
  .frs_validate_identifier(col_a_id, "col_a_id")
  .frs_validate_identifier(col_b_id, "col_b_id")

  if (identical(col_a_id, col_b_id)) {
    stop("`col_a_id` and `col_b_id` must differ; the output ",
         "carries both columns side-by-side, so identical names would ",
         "collide. Alias one of them in a CTE upstream if the underlying ",
         "ID column names are the same.", call. = FALSE)
  }

  # Introspect table_a so the final SELECT can carry every column
  # forward explicitly (PostgreSQL has no SELECT * EXCEPT). Guard
  # against table_a containing columns that would collide with the
  # ones we add (`<col_b_id>`, `distance_instream`,
  # `dedup_metric_internal`).
  cols_a <- .frs_table_columns(conn, table_a)
  reserved <- c(col_b_id, "distance_instream", "dedup_metric_internal")
  collide <- intersect(cols_a, reserved)
  if (length(collide) > 0L) {
    stop(sprintf(
      paste0(
        "`table_a` already has column(s) frs_point_match adds (%s). ",
        "Rename in a CTE upstream or pick a different `col_b_id`."
      ),
      paste(collide, collapse = ", ")
    ), call. = FALSE)
  }
  cols_a_list <- paste0("ranked.", cols_a, collapse = ",\n      ")

  # b-side dedup metric: instream by default, planar (ST_Distance on geom)
  # when caller opts in. Threshold filter + a-side dedup stay instream.
  dedup_metric_sql <- if (tiebreak == "planar") {
    "ST_Distance(a.geom, b.geom)"
  } else {
    "ABS(a.downstream_route_measure - b.downstream_route_measure)"
  }

  # SQL composition. Argument order in sprintf:
  #   1 = table_a, 2 = table_b, 3 = table_to,
  #   4 = col_a_id, 5 = col_b_id, 6 = distance_max literal,
  #   7 = ranked.<col> projection for table_a columns
  #
  # Bidirectional dedup mirrors bcfp's two-pass algorithm in
  # 02_pscis_streams_150m.sql:
  #
  # 1. `candidates` — LEFT JOIN within `distance_max` on same blue_line_key.
  #    Multiple b-rows per a-row possible; unmatched a-rows carry NULL.
  # 2. `a_dedup` — DISTINCT ON (a_id, blue_line_key) keeps each a-row's
  #    nearest b-row. Unmatched a-rows persist (NULLS LAST in ORDER).
  # 3. `ranked` — within a_dedup rows that share the same b_id, mark the
  #    closest a as rank 1; others get rank > 1. NULL-b rows are rank 1
  #    trivially (they don't compete).
  # 4. Final SELECT — emit b_id only when b_rank = 1 (winning a per b).
  #    Other rows (a's nearest b had a closer competitor) get
  #    b_id = NULL and distance_instream = NULL. Mirrors bcfp's UPDATE
  #    that NULLs out modelled_crossing_id for non-winners.
  #
  # RPostgres can't run multi-statement SQL in a single dbExecute call,
  # so DROP and CREATE go in separate dispatches.
  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", table_to))

  sql_fmt <- "
    CREATE TABLE %3$s AS
    WITH candidates AS (
      SELECT
        a.*,
        b.%5$s AS %5$s,
        ABS(a.downstream_route_measure - b.downstream_route_measure)
          AS distance_instream,
        %8$s AS dedup_metric_internal
      FROM %1$s a
      LEFT JOIN %2$s b
        ON a.blue_line_key = b.blue_line_key
       AND ABS(a.downstream_route_measure - b.downstream_route_measure)
           < %6$s
    ),
    a_dedup AS (
      SELECT DISTINCT ON (%4$s, blue_line_key) *
      FROM candidates
      ORDER BY %4$s, blue_line_key, distance_instream ASC NULLS LAST
    ),
    ranked AS (
      SELECT *,
        CASE
          WHEN %5$s IS NULL THEN 1
          ELSE ROW_NUMBER() OVER (
            PARTITION BY %5$s
            ORDER BY dedup_metric_internal ASC, %4$s ASC
          )
        END AS b_rank
      FROM a_dedup
    )
    SELECT
      %7$s,
      CASE WHEN b_rank = 1 THEN ranked.%5$s ELSE NULL END AS %5$s,
      CASE WHEN b_rank = 1 THEN distance_instream ELSE NULL END
        AS distance_instream
    FROM ranked"

  sql <- sprintf(
    sql_fmt,
    table_a,
    table_b,
    table_to,
    col_a_id,
    col_b_id,
    .frs_sql_num(distance_max),
    cols_a_list,
    dedup_metric_sql
  )

  .frs_db_execute(conn, sql)

  invisible(conn)
}
