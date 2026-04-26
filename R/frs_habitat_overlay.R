#' Overlay known-habitat flags onto a classified streams_habitat table
#'
#' After [frs_habitat_classify()] populates per-segment per-species
#' habitat booleans from rules, `frs_habitat_overlay()` ORs in additional
#' TRUE flags from a wide-format known-habitat table — capturing field
#' observations / expert review / manual additions that the rule-based
#' classifier doesn't reach. Mirrors the bcfishpass pipeline's blend of
#' `habitat_linear_<sp>` (model) with `streams_habitat_known` (knowns)
#' into the published `streams_habitat_linear`.
#'
#' Known-habitat is **purely additive**: this function never sets a
#' flag from `TRUE` to `FALSE`. Callers wanting "known beats model"
#' semantics should preprocess the known table before calling.
#'
#' Two known-table shapes supported via the `format` argument:
#'
#' - **`"wide"`** (default) — one row per segment, columns named
#'   `{habitat_type}_{species_lower}` (e.g. `spawning_sk`, `rearing_co`).
#'   Boolean or NULL. Matches the bcfishpass `streams_habitat_known`
#'   convention. Missing per-species columns are skipped with a verbose
#'   message — many species have known data only for certain habitat
#'   types.
#'
#' - **`"long"`** — one row per (segment × species × habitat_type),
#'   with a `species_code` column, a `habitat_type` column, and an
#'   indicator column (`habitat_ind`) holding `'TRUE'`/`'FALSE'` (text)
#'   or boolean. Matches link's `user_habitat_classification.csv`
#'   shape. The function filters by species + habitat_type before the
#'   join.
#'
#' Segments are matched between `table` and `known` using a join on the
#' columns named in `by` (default `c("blue_line_key", "downstream_route_measure")`).
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param table Character. Schema-qualified streams_habitat table to
#'   update in place. Must have columns `id_segment`, `species_code`,
#'   plus boolean columns named in `habitat_types`, plus the join keys
#'   in `by`.
#' @param known Character. Schema-qualified known-habitat table.
#'   Wide-format: join keys + per-species columns. Long-format: join
#'   keys + `species_code` + `habitat_type` + the indicator column
#'   named in `long_value_col`.
#' @param species Character vector. Species codes to ingest. `NULL`
#'   (default) processes every species code present in `table`.
#' @param habitat_types Character vector. Habitat-type columns to OR
#'   in. Defaults to the four standard ones: `c("spawning", "rearing",
#'   "lake_rearing", "wetland_rearing")`. Must be a subset of the
#'   columns present in `table`.
#' @param by Character vector. Columns used to join `table` to `known`.
#'   Default `c("blue_line_key", "downstream_route_measure")`.
#' @param format Character. `"wide"` (default) or `"long"` — see
#'   description.
#' @param long_value_col Character. For `format = "long"`, the column
#'   name in `known` that holds the indicator. Default `"habitat_ind"`.
#'   Accepts: boolean values, OR text values `'TRUE'`/`'true'`/`'t'`
#'   (case + whitespace insensitive). Anything else (NULL, `'FALSE'`,
#'   `'1'`, `'yes'`, ...) skips the row.
#' @param verbose Logical. Print per-species per-habitat summary.
#'   Default `TRUE`.
#'
#' @return `conn` invisibly (for piping).
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # After frs_habitat_classify() populated working.streams_habitat,
#' # OR in known habitat from a CSV-loaded table.
#' frs_habitat_overlay(conn,
#'   table   = "working.streams_habitat",
#'   known   = "working.user_habitat_classification",
#'   species = c("CO", "SK", "CH"))
#' }
frs_habitat_overlay <- function(conn, table, known,
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
    is.character(table), length(table) == 1L, nchar(table) > 0,
    is.character(known), length(known) == 1L, nchar(known) > 0,
    is.character(habitat_types), length(habitat_types) > 0,
    is.character(by), length(by) > 0,
    is.character(long_value_col), length(long_value_col) == 1L
  )
  .frs_validate_identifier(long_value_col, "long_value_col")
  if (!is.null(species)) {
    stopifnot(is.character(species), length(species) > 0)
  }
  .frs_validate_identifier(table, "table")
  .frs_validate_identifier(known, "known")
  for (b in by) .frs_validate_identifier(b, "by column")
  for (h in habitat_types) .frs_validate_identifier(h, "habitat_types entry")
  if (!is.null(species)) {
    bad <- !grepl("^[A-Za-z]+$", species)
    if (any(bad)) {
      stop(sprintf("species code(s) must be alphabetic only: %s",
                   paste(species[bad], collapse = ", ")), call. = FALSE)
    }
  }

  # Validate habitat_types are columns in `table` so we don't UPDATE
  # mid-loop and crash on a missing column halfway through (partial
  # update, no rollback).
  table_parts <- strsplit(table, "\\.", fixed = FALSE)[[1]]
  if (length(table_parts) != 2L) {
    stop("`table` must be schema-qualified (e.g. 'working.streams_habitat')",
         call. = FALSE)
  }
  table_cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s",
    .frs_quote_string(table_parts[1]),
    .frs_quote_string(table_parts[2])))$column_name
  missing_hab <- setdiff(habitat_types, table_cols)
  if (length(missing_hab) > 0) {
    stop(sprintf(
      "habitat_types not found as columns in %s: %s",
      table, paste(missing_hab, collapse = ", ")), call. = FALSE)
  }

  # --- Discover species set ---
  if (is.null(species)) {
    species <- DBI::dbGetQuery(conn, sprintf(
      "SELECT DISTINCT species_code FROM %s ORDER BY species_code",
      table))$species_code
    if (length(species) == 0) {
      if (verbose) cat("frs_habitat_overlay: table is empty, nothing to do.\n")
      return(invisible(conn))
    }
  }

  # --- Discover known-table columns once (to skip missing per-species cols) ---
  known_parts <- strsplit(known, "\\.", fixed = FALSE)[[1]]
  if (length(known_parts) != 2L) {
    stop("`known` must be schema-qualified (e.g. 'working.user_habitat_classification')",
         call. = FALSE)
  }
  known_cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s",
    .frs_quote_string(known_parts[1]),
    .frs_quote_string(known_parts[2])))$column_name
  if (length(known_cols) == 0) {
    stop(sprintf("known table %s not found or has no columns", known),
         call. = FALSE)
  }

  # --- Long format: validate required columns up front ---
  if (format == "long") {
    required_long <- c(by, "species_code", "habitat_type", long_value_col)
    missing_long <- setdiff(required_long, known_cols)
    if (length(missing_long) > 0) {
      stop(sprintf(
        "long-format known table %s missing required columns: %s",
        known, paste(missing_long, collapse = ", ")), call. = FALSE)
    }
  }

  join_pred <- paste(sprintf("h.%s = k.%s", by, by), collapse = " AND ")

  # --- OR in flags per (habitat_type, species) ---
  total_updates <- 0L
  for (sp in species) {
    sp_lower <- tolower(sp)
    for (hab in habitat_types) {

      sql <- if (format == "wide") {
        col <- paste0(hab, "_", sp_lower)
        if (!col %in% known_cols) {
          if (verbose) {
            cat(sprintf("  skip %s/%s (no column `%s` in %s)\n",
                        sp, hab, col, known))
          }
          next
        }
        sprintf(
          "UPDATE %s AS h
           SET %s = TRUE
           FROM %s AS k
           WHERE %s
             AND h.species_code = %s
             AND k.%s IS TRUE
             AND (h.%s IS NULL OR h.%s = FALSE)",
          table, hab, known, join_pred,
          .frs_quote_string(sp),
          col, hab, hab)
      } else {
        # long format: filter by species + habitat_type, accept boolean
        # OR text 'TRUE' for the indicator column.
        sprintf(
          "UPDATE %s AS h
           SET %s = TRUE
           FROM %s AS k
           WHERE %s
             AND h.species_code = %s
             AND k.species_code = %s
             AND k.habitat_type = %s
             AND (lower(trim(k.%s::text)) IN ('true', 't'))
             AND (h.%s IS NULL OR h.%s = FALSE)",
          table, hab, known, join_pred,
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
