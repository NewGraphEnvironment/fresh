#' Overlay flags from one table onto another
#'
#' OR-in boolean flags from a source table (`from`) onto an existing
#' classified table (`to`), purely additively (`FALSE → TRUE` only,
#' never reversed). Surfaced for the bcfishpass / link blend of
#' rule-based classification (`frs_habitat_classify()`) with
#' manually-curated knowns (`user_habitat_classification.csv`), but
#' the mechanism is generic: any boolean-flagged source over any
#' boolean-flagged target.
#'
#' Two source-table shapes (`format`):
#'
#' - **`"wide"`** — one row per segment, columns named
#'   `{habitat_type}_{species_lower}` (e.g. `spawning_sk`). Boolean.
#'   Matches the bcfishpass `streams_habitat_known` convention.
#' - **`"long"`** — one row per (segment × species × habitat_type),
#'   with `species_code`, `habitat_type`, and an indicator column
#'   (`long_value_col`, default `habitat_ind`). Indicator can be
#'   boolean or text (`'TRUE'`/`'true'`/`'t'` case + whitespace
#'   insensitive). Matches link's `user_habitat_classification`
#'   table.
#'
#' Two join modes (`bridge`):
#'
#' - **Direct (`bridge = NULL`)** — the `to` table has the join keys
#'   directly. SQL does `to.<by> = from.<by>` (point match).
#' - **Bridged (`bridge = "<segments_table>"`)** — the `to` table is
#'   keyed by `id_segment` (e.g. `fresh.streams_habitat`) and lacks
#'   the geographic keys in `by`. The bridge table provides the
#'   link, with id_segment + range columns. SQL does a 3-way join:
#'
#'   ```
#'   to.id_segment = bridge.id_segment
#'   AND bridge.<by[1]> = from.<by[1]>
#'   AND bridge.downstream_route_measure >= from.downstream_route_measure
#'   AND bridge.upstream_route_measure   <= from.upstream_route_measure
#'   ```
#'
#'   Range containment, not point match — covers the case where one
#'   `from` row's `[drm, urm]` range maps to multiple bridge segments
#'   (e.g. when other break sources fall inside the range).
#'
#' Future bridges aren't required to be `fresh.streams` — any table
#' providing `id_segment` + the join-key columns + range columns
#' works. Use cases include lake / wetland centerline segments or
#' cottonwood-polygon segmentations pinned to a hydrology network.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param from Character. Schema-qualified source table providing
#'   the flags to overlay. Wide- or long-format per `format`.
#' @param to Character. Schema-qualified destination table to UPDATE
#'   in place. Must have boolean columns named in `habitat_types`
#'   plus a `species_code` column. Either has the join keys (`by`)
#'   directly, or only `id_segment` (use `bridge` to resolve).
#' @param bridge Character or `NULL`. Optional schema-qualified
#'   segments table providing `id_segment` + the join keys in `by`
#'   + `downstream_route_measure` + `upstream_route_measure`. When
#'   provided, switches to a 3-way range-containment join. Default
#'   `NULL` (direct point-match join — `to` must have the join keys).
#'   **Note:** the range column names are currently hardcoded to FWA
#'   convention (`downstream_route_measure` / `upstream_route_measure`).
#'   `from` and `bridge` must both use these names; non-FWA segment
#'   schemas would need a follow-up parameterisation.
#' @param species Character vector. Species codes to ingest. `NULL`
#'   (default) processes every species code present in `to`.
#' @param habitat_types Character vector. Habitat-type columns to OR
#'   in. Defaults to the four standard ones: `c("spawning",
#'   "rearing", "lake_rearing", "wetland_rearing")`. Must be a
#'   subset of the columns present in `to`.
#' @param by Character vector. Columns used to match `from` to either
#'   `to` (when `bridge = NULL`) or to `bridge` (when bridge supplied).
#'   Default `c("blue_line_key", "downstream_route_measure")`.
#' @param format Character. `"wide"` (default) or `"long"`.
#' @param long_value_col Character. For `format = "long"`, the column
#'   name in `from` that holds the indicator. Default
#'   `"habitat_ind"`. Accepts boolean or `'true'`/`'t'` text
#'   (case + whitespace insensitive).
#' @param verbose Logical. Print per-species per-habitat summary.
#'   Default `TRUE`.
#'
#' @return `conn` invisibly (for piping).
#'
#' @family habitat
#' @export
#'
#' @examples
#' \dontrun{
#' # Direct join (target has the keys):
#' frs_habitat_overlay(conn,
#'   from = "ws.user_habitat_classification",
#'   to   = "ws.streams_habitat_keyed",
#'   format = "long")
#'
#' # Bridged join (target is fresh.streams_habitat, keyed by id_segment):
#' frs_habitat_overlay(conn,
#'   from   = "ws.user_habitat_classification",
#'   to     = "fresh.streams_habitat",
#'   bridge = "fresh.streams",
#'   format = "long")
#' }
frs_habitat_overlay <- function(conn, from, to,
                                bridge = NULL,
                                species = NULL,
                                habitat_types = c("spawning", "rearing",
                                                  "lake_rearing", "wetland_rearing"),
                                by = c("blue_line_key", "downstream_route_measure"),
                                format = c("wide", "long"),
                                long_value_col = "habitat_ind",
                                verbose = TRUE) {

  format <- match.arg(format)

  # --- Argument validation ---
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(from), length(from) == 1L, nchar(from) > 0,
    is.character(to),   length(to)   == 1L, nchar(to)   > 0,
    is.character(habitat_types), length(habitat_types) > 0,
    is.character(by), length(by) > 0,
    is.character(long_value_col), length(long_value_col) == 1L
  )
  if (!is.null(bridge)) {
    stopifnot(is.character(bridge), length(bridge) == 1L, nchar(bridge) > 0)
    .frs_validate_identifier(bridge, "bridge")
  }
  .frs_validate_identifier(from, "from")
  .frs_validate_identifier(to,   "to")
  .frs_validate_identifier(long_value_col, "long_value_col")
  for (b in by) .frs_validate_identifier(b, "by column")
  for (h in habitat_types) .frs_validate_identifier(h, "habitat_types entry")
  if (!is.null(species)) {
    stopifnot(is.character(species), length(species) > 0)
    bad <- !grepl("^[A-Za-z]+$", species)
    if (any(bad)) {
      stop(sprintf("species code(s) must be alphabetic only: %s",
                   paste(species[bad], collapse = ", ")), call. = FALSE)
    }
  }

  # Validate habitat_types are columns in `to` so we don't UPDATE
  # mid-loop and crash on a missing column halfway through.
  to_parts <- strsplit(to, "\\.", fixed = FALSE)[[1]]
  if (length(to_parts) != 2L) {
    stop("`to` must be schema-qualified (e.g. 'working.streams_habitat')",
         call. = FALSE)
  }
  to_cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s",
    .frs_quote_string(to_parts[1]),
    .frs_quote_string(to_parts[2])))$column_name
  missing_hab <- setdiff(habitat_types, to_cols)
  if (length(missing_hab) > 0) {
    stop(sprintf(
      "habitat_types not found as columns in %s: %s",
      to, paste(missing_hab, collapse = ", ")), call. = FALSE)
  }

  # --- Discover species set ---
  if (is.null(species)) {
    species <- DBI::dbGetQuery(conn, sprintf(
      "SELECT DISTINCT species_code FROM %s ORDER BY species_code",
      to))$species_code
    if (length(species) == 0) {
      if (verbose) cat("frs_habitat_overlay: target table is empty, nothing to do.\n")
      return(invisible(conn))
    }
  }

  # --- Discover from-table columns ---
  from_parts <- strsplit(from, "\\.", fixed = FALSE)[[1]]
  if (length(from_parts) != 2L) {
    stop("`from` must be schema-qualified (e.g. 'working.user_habitat_classification')",
         call. = FALSE)
  }
  from_cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s",
    .frs_quote_string(from_parts[1]),
    .frs_quote_string(from_parts[2])))$column_name
  if (length(from_cols) == 0) {
    stop(sprintf("from table %s not found or has no columns", from),
         call. = FALSE)
  }

  # --- Long-format: validate required columns up front ---
  if (format == "long") {
    required_long <- c(by, "species_code", "habitat_type", long_value_col)
    missing_long <- setdiff(required_long, from_cols)
    if (length(missing_long) > 0) {
      stop(sprintf(
        "long-format `from` table %s missing required columns: %s",
        from, paste(missing_long, collapse = ", ")), call. = FALSE)
    }
  }

  # --- Bridge validation: must have id_segment + by + range columns ---
  if (!is.null(bridge)) {
    bridge_parts <- strsplit(bridge, "\\.", fixed = FALSE)[[1]]
    if (length(bridge_parts) != 2L) {
      stop("`bridge` must be schema-qualified (e.g. 'fresh.streams')",
           call. = FALSE)
    }
    bridge_cols <- DBI::dbGetQuery(conn, sprintf(
      "SELECT column_name FROM information_schema.columns
       WHERE table_schema = %s AND table_name = %s",
      .frs_quote_string(bridge_parts[1]),
      .frs_quote_string(bridge_parts[2])))$column_name
    required_bridge <- c("id_segment", by,
                          "downstream_route_measure", "upstream_route_measure")
    missing_bridge <- setdiff(required_bridge, bridge_cols)
    if (length(missing_bridge) > 0) {
      stop(sprintf(
        "bridge table %s missing required columns: %s",
        bridge, paste(missing_bridge, collapse = ", ")), call. = FALSE)
    }
  }

  # --- Build join clause once ---
  if (is.null(bridge)) {
    # Direct: to ↔ from on by columns
    from_clause <- sprintf("FROM %s AS k", from)
    join_pred   <- paste(sprintf("h.%s = k.%s", by, by), collapse = " AND ")
  } else {
    # 3-way: to.id_segment = bridge.id_segment + bridge ranges contain from.
    # Range columns are handled by the >= / <= predicates below; strip
    # them from the equality `by` clause so we don't double-constrain
    # (point match on drm would always fail when the from range is
    # wider than the bridge segment).
    range_cols <- c("downstream_route_measure", "upstream_route_measure")
    by_eq <- setdiff(by, range_cols)
    if (length(by_eq) == 0) {
      stop("`by` must include at least one non-range column when `bridge` is set",
           call. = FALSE)
    }
    from_clause <- sprintf("FROM %s AS s, %s AS k", bridge, from)
    bk_pred <- paste(sprintf("s.%s = k.%s", by_eq, by_eq), collapse = " AND ")
    join_pred <- paste0(
      "h.id_segment = s.id_segment AND ", bk_pred,
      " AND s.downstream_route_measure >= k.downstream_route_measure",
      " AND s.upstream_route_measure   <= k.upstream_route_measure")
  }

  # --- OR in flags per (habitat_type, species) ---
  total_updates <- 0L
  for (sp in species) {
    sp_lower <- tolower(sp)
    for (hab in habitat_types) {

      sql <- if (format == "wide") {
        col <- paste0(hab, "_", sp_lower)
        if (!col %in% from_cols) {
          if (verbose) {
            cat(sprintf("  skip %s/%s (no column `%s` in %s)\n",
                        sp, hab, col, from))
          }
          next
        }
        sprintf(
          "UPDATE %s AS h
           SET %s = TRUE
           %s
           WHERE %s
             AND h.species_code = %s
             AND k.%s IS TRUE
             AND (h.%s IS NULL OR h.%s = FALSE)",
          to, hab, from_clause, join_pred,
          .frs_quote_string(sp),
          col, hab, hab)
      } else {
        # long format
        sprintf(
          "UPDATE %s AS h
           SET %s = TRUE
           %s
           WHERE %s
             AND h.species_code = %s
             AND k.species_code = %s
             AND k.habitat_type = %s
             AND (lower(trim(k.%s::text)) IN ('true', 't'))
             AND (h.%s IS NULL OR h.%s = FALSE)",
          to, hab, from_clause, join_pred,
          .frs_quote_string(sp),
          .frs_quote_string(sp),
          .frs_quote_string(hab),
          long_value_col,
          hab, hab)
      }

      n <- .frs_db_execute(conn, sql)
      total_updates <- total_updates + n
      if (verbose) {
        cat(sprintf("  %s/%s: %d segments flipped from FALSE/NULL -> TRUE\n",
                    sp, hab, n))
      }
    }
  }

  if (verbose) {
    cat(sprintf("frs_habitat_overlay: %d total updates across %d species, %d habitat types\n",
                total_updates, length(species), length(habitat_types)))
  }
  invisible(conn)
}
