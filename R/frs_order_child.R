#' Classify rearing on direct children of large-order streams
#'
#' Post-classification update that adds a habitat label (default
#' `rearing`) to segments on direct tributaries of large-order rivers,
#' optionally distance-capped from the confluence. Runs after
#' `frs_habitat_classify()` (and any post-classify step like
#' `frs_cluster()`); is additive, idempotent, and never overrides
#' segments above an inaccessible barrier.
#'
#' @section Why this exists:
#'
#' Small streams flowing directly into mainstem rivers support juvenile
#' rearing even when the FWA-measured channel width is below the
#' species threshold. The parent river supplies flow, temperature,
#' access; cool tributary water mixes at the confluence; backwater /
#' off-channel habitat near the mouth is high-value. Channel-width
#' measurement on the small tributary doesn't reflect this reality.
#'
#' bcfishpass models this with a hard-coded predicate
#' `cw.channel_width >= rear_channel_width_min OR
#' (s.stream_order_parent >= 5 AND s.stream_order = 1)` (per BT/CH/CO/
#' ST/WCT rear SQL in
#' `model/02_habitat_linear/sql/load_habitat_linear_<sp>.sql`). This
#' function exposes the same biology as a parametric post-classification
#' rule, so callers can tune `parent_order_min`, `child_order_min/max`,
#' and `distance_max` without touching the rule grammar.
#'
#' @section Direct-child semantics:
#'
#' A "direct child" of a large river is a segment that satisfies all of:
#'
#' 1. **`stream_order = stream_order_max` (per blue_line_key).** The
#'    segment is on the mouth-side reach of its BLK — the part where
#'    the BLK has reached its final, maximum order. Tributaries joining
#'    upstream may push the BLK to a higher order at lower DRM, but the
#'    headwater portions (where the BLK is still at a smaller order
#'    before any tribs join) are excluded. Without this filter, a
#'    multi-order BLK like a named creek that grows from order-1
#'    headwaters to order-3 mouth would have its order-1 headwater
#'    reaches credited even though they are not the "direct trib" of a
#'    large parent — they are just upstream of one.
#' 2. **`stream_order_parent >= parent_order_min`.** The receiving
#'    stream at the BLK's first downstream confluence is at least the
#'    threshold order (default 5L = bcfp's hardcoded value).
#' 3. **`stream_order` between `child_order_min` and `child_order_max`
#'    (defaults to 1L for both).** Restricts the child trib's own
#'    order. Default 1L matches bcfishpass.
#'
#' `stream_order_max` is computed on the fly via window function over
#' the `table` argument: `MAX(stream_order) OVER (PARTITION BY blue_line_key)`.
#' fresh's streams table doesn't store this column; bcfp's
#' `bcfishpass.streams` does, but the value is the same.
#'
#' @section Distance grain:
#'
#' `distance_max` filters on the segment's start measure
#' (`downstream_route_measure`). The grain of FWA segmentation
#' determines what gets captured at the boundary — segments straddling
#' the cap are kept (whole-segment-in, biology-conservative
#' overshoot). Documented as a tradeoff in fresh#158; alternate exact
#' break + filter approaches are out of scope here.
#'
#' @section SQL emitted:
#'
#' ```sql
#' WITH s AS (
#'   SELECT *,
#'          MAX(stream_order) OVER (PARTITION BY blue_line_key) AS stream_order_max
#'   FROM <table>
#' )
#' UPDATE <habitat>
#' SET <label> = TRUE
#' FROM s
#' WHERE <habitat>.id_segment = s.id_segment
#'   AND <habitat>.species_code = '<species>'
#'   AND <habitat>.accessible = TRUE
#'   AND <habitat>.<label> IS NOT TRUE
#'   AND s.stream_order = s.stream_order_max
#'   AND s.stream_order_parent >= <parent_order_min>
#'   AND s.stream_order >= <child_order_min>   -- default 1 if both NULL
#'   AND s.stream_order <= <child_order_max>   -- default 1 if both NULL
#'   [AND s.downstream_route_measure <= <distance_max>]
#' ```
#'
#' Bracketed clauses are emitted only when the corresponding parameter
#' is non-NULL.
#'
#' @param conn DBI connection.
#' @param table Character. Schema-qualified streams table (e.g.
#'   `"fresh.streams"`).
#' @param habitat Character. Schema-qualified habitat table (e.g.
#'   `"fresh.streams_habitat"`).
#' @param species Character. Species code (e.g. `"BT"`).
#' @param label Character. Habitat-table column to set TRUE. Default
#'   `"rearing"`. Generic on the column name — pass `"lake_rearing"`,
#'   `"wetland_rearing"`, or any custom boolean column when biology
#'   supports it.
#' @param parent_order_min Integer. Minimum parent stream order for a
#'   direct-child segment to qualify. Default `5L` (matches
#'   bcfishpass's hard-coded value).
#' @param child_order_min Integer or `NULL`. If set, segment's
#'   `stream_order` must be `>= child_order_min`. Default `NULL`. When
#'   both `child_order_min` and `child_order_max` are `NULL`, both
#'   default to `1L` (matches bcfishpass's `stream_order = 1` predicate).
#' @param child_order_max Integer or `NULL`. If set, segment's
#'   `stream_order` must be `<= child_order_max`. Default `NULL`. When
#'   both `child_order_min` and `child_order_max` are `NULL`, both
#'   default to `1L` (matches bcfishpass's `stream_order = 1` predicate).
#' @param distance_max Numeric or `NULL`. If set, segment's
#'   `downstream_route_measure` must be `<= distance_max` (metres from
#'   tributary mouth). Default `NULL` (whole tributary).
#' @param verbose Logical. Print before/after counts. Default `TRUE`.
#'
#' @return Invisibly, the number of segments newly labeled.
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Reproduce bcfishpass exactly: direct children of order-5+ rivers,
#' # no distance cap, for BT/CH/CO/ST/WCT.
#' for (sp in c("BT", "CH", "CO", "ST", "WCT")) {
#'   frs_order_child(conn, "fresh.streams", "fresh.streams_habitat",
#'     species = sp)
#' }
#'
#' # Distance-capped: only the lower 300 m of each direct-child trib.
#' frs_order_child(conn, "fresh.streams", "fresh.streams_habitat",
#'   species = "BT", distance_max = 300)
#'
#' # Restrict to 3rd-order-and-above direct children of major rivers.
#' frs_order_child(conn, "fresh.streams", "fresh.streams_habitat",
#'   species = "BT", child_order_min = 3)
#' }
#'
#' @export
frs_order_child <- function(conn,
                            table,
                            habitat,
                            species,
                            label = "rearing",
                            parent_order_min = 5L,
                            child_order_min = NULL,
                            child_order_max = NULL,
                            distance_max = NULL,
                            verbose = TRUE) {
  .frs_validate_identifier(table, "table")
  .frs_validate_identifier(habitat, "habitat")
  .frs_validate_identifier(label, "label")
  if (!is.character(species) || length(species) != 1L || !nzchar(species)) {
    stop("species must be a single non-empty string", call. = FALSE)
  }
  if (!is.numeric(parent_order_min) || length(parent_order_min) != 1L) {
    stop("parent_order_min must be a numeric scalar", call. = FALSE)
  }

  sp_quoted <- .frs_quote_string(species)
  pom <- as.integer(parent_order_min)

  # Default both child bounds to 1L when neither is set — matches
  # bcfishpass's `stream_order = 1` predicate exactly. Caller can pass
  # one or both to widen (e.g. orders 1-2) or narrow.
  if (is.null(child_order_min) && is.null(child_order_max)) {
    child_order_min <- 1L
    child_order_max <- 1L
  }

  child_min_clause <- if (!is.null(child_order_min)) {
    sprintf("AND s.stream_order >= %d", as.integer(child_order_min))
  } else ""
  child_max_clause <- if (!is.null(child_order_max)) {
    sprintf("AND s.stream_order <= %d", as.integer(child_order_max))
  } else ""
  distance_clause <- if (!is.null(distance_max)) {
    sprintf("AND s.downstream_route_measure <= %s",
            .frs_sql_num(distance_max))
  } else ""

  # `stream_order_max` is derived per BLK on the fly. fresh.streams
  # doesn't store it; bcfp's bcfishpass.streams does. The CTE makes
  # the predicate work over either source identically.
  sql <- sprintf(
    "WITH s AS (
       SELECT *,
              MAX(stream_order) OVER (PARTITION BY blue_line_key) AS stream_order_max
       FROM %s
     )
     UPDATE %s h
     SET %s = TRUE
     FROM s
     WHERE h.id_segment = s.id_segment
       AND h.species_code = %s
       AND h.accessible = TRUE
       AND h.%s IS NOT TRUE
       AND s.stream_order = s.stream_order_max
       AND s.stream_order_parent >= %d
       %s %s %s",
    table,
    habitat, label,
    sp_quoted,
    label,
    pom,
    child_min_clause, child_max_clause, distance_clause)

  n_before <- 0L
  if (verbose) {
    n_before <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*) FILTER (WHERE %s)::int AS n FROM %s
       WHERE species_code = %s", label, habitat, sp_quoted))$n
    message(sprintf("  %s before: %d segments with %s = TRUE",
                    species, n_before, label))
  }

  n_added <- DBI::dbExecute(conn, sql)

  if (verbose) {
    message(sprintf("  %s order_child: +%d segments labeled %s = TRUE",
                    species, n_added, label))
  }

  invisible(n_added)
}
