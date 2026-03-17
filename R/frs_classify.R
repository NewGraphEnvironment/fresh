#' Classify Features by Attribute Ranges, Breaks, or Overrides
#'
#' Label features in a working table by any combination of: attribute ranges
#' (e.g. gradient between 0 and 0.025), spatial relationship to break points
#' (accessible vs not), and manual overrides from a corrections table.
#' At least one of `ranges`, `breaks`, or `overrides` is required.
#'
#' Pipeable for multi-step labelling — call once per label column:
#'
#' ```
#' conn |>
#'   frs_classify("working.streams", label = "accessible",
#'                breaks = "working.breaks") |>
#'   frs_classify("working.streams", label = "spawning",
#'                ranges = list(gradient = c(0, 0.025)))
#' ```
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Working schema table to classify
#'   (from [frs_extract()]).
#' @param label Character. Column name to add or update with the
#'   classification result (e.g. `"spawning"`, `"accessible"`).
#' @param ranges Named list or `NULL`. Each element is a column name mapped
#'   to a `c(min, max)` range. All conditions must be met (AND). Example:
#'   `list(gradient = c(0, 0.025), channel_width = c(2, 20))`.
#' @param breaks Character or `NULL`. Table name containing break points.
#'   Segments with no downstream break are labelled `TRUE` (accessible).
#'   Uses `fwa_downstream()` for network position check.
#' @param overrides Character or `NULL`. Table name containing manual
#'   corrections. Must have a column matching `label` and a join column
#'   matching the working table (default: `blue_line_key` +
#'   `downstream_route_measure`).
#' @param value Logical. Value to set when conditions are met. Default
#'   `TRUE`. Use `FALSE` for exclusion labels.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' # --- Concept: multi-attribute classification (bundled data) ---
#' d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
#' streams <- d$streams
#'
#' # Classify spawning habitat: gradient 0-2.5% AND stream order >= 3
#' spawning <- !is.na(streams$gradient) &
#'   streams$gradient >= 0 & streams$gradient <= 0.025 &
#'   !is.na(streams$stream_order) & streams$stream_order >= 3
#' streams$spawning <- spawning
#' message(sum(spawning), " of ", nrow(streams),
#'         " segments are spawning habitat")
#'
#' # Rearing habitat: different thresholds on the same network
#' rearing <- !is.na(streams$gradient) &
#'   streams$gradient >= 0 & streams$gradient <= 0.05
#' streams$rearing <- rearing
#' message(sum(rearing), " of ", nrow(streams),
#'         " segments are rearing habitat")
#'
#' # Plot both — this is what piped frs_classify calls produce
#' oldpar <- par(mfrow = c(1, 2))
#' plot(streams["spawning"], main = "Spawning (gradient 0-2.5%)",
#'      pal = c("grey80", "steelblue"), key.pos = NULL)
#' plot(streams["rearing"], main = "Rearing (gradient 0-5%)",
#'      pal = c("grey80", "darkorange"), key.pos = NULL)
#' par(oldpar)
#'
#' \dontrun{
#' # --- Live DB: piped multi-label classification ---
#' conn <- frs_db_conn()
#' aoi <- d$aoi
#'
#' # Extract, generate columns, then classify with multiple labels
#' conn |>
#'   frs_extract("whse_basemapping.fwa_stream_networks_sp",
#'     "working.demo_classify", aoi = aoi, overwrite = TRUE) |>
#'   frs_col_generate("working.demo_classify") |>
#'   frs_classify("working.demo_classify", label = "spawning",
#'     ranges = list(gradient = c(0, 0.025))) |>
#'   frs_classify("working.demo_classify", label = "rearing",
#'     ranges = list(gradient = c(0, 0.05)))
#'
#' # Read back and compare
#' result <- frs_db_query(conn,
#'   "SELECT spawning, rearing, gradient, geom FROM working.demo_classify")
#' message("Spawning: ", sum(result$spawning, na.rm = TRUE), " segments")
#' message("Rearing: ", sum(result$rearing, na.rm = TRUE), " segments")
#'
#' par(mfrow = c(1, 2))
#' plot(result["spawning"], main = "Spawning")
#' plot(result["rearing"], main = "Rearing")
#' par(mfrow = c(1, 1))
#'
#' # Clean up
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_classify")
#' DBI::dbDisconnect(conn)
#' }
frs_classify <- function(conn, table, label,
                         ranges = NULL, breaks = NULL,
                         overrides = NULL, value = TRUE) {
  .frs_validate_identifier(table, "table")
  .frs_validate_identifier(label, "label column")

  has_ranges <- !is.null(ranges)
  has_breaks <- !is.null(breaks)
  has_overrides <- !is.null(overrides)

  if (!has_ranges && !has_breaks && !has_overrides) {
    stop("At least one of ranges, breaks, or overrides is required",
         call. = FALSE)
  }

  # Add the label column if it doesn't exist
  sql_add <- sprintf(
    "ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s boolean DEFAULT NULL",
    table, label
  )
  .frs_db_execute(conn, sql_add)

  # Apply ranges classification
  if (has_ranges) {
    .frs_classify_ranges(conn, table, label, ranges, value)
  }

  # Apply breaks classification (accessibility)
  if (has_breaks) {
    .frs_classify_breaks(conn, table, label, breaks, value)
  }

  # Apply manual overrides
  if (has_overrides) {
    .frs_classify_overrides(conn, table, label, overrides)
  }

  invisible(conn)
}


#' Classify by attribute ranges
#'
#' Sets `label = value` where all range conditions are met (AND).
#'
#' @noRd
.frs_classify_ranges <- function(conn, table, label, ranges, value) {
  stopifnot(is.list(ranges), length(ranges) > 0)

  conditions <- vapply(names(ranges), function(col) {
    .frs_validate_identifier(col, "range column")
    r <- ranges[[col]]
    stopifnot(is.numeric(r), length(r) == 2)
    sprintf("%s BETWEEN %s AND %s", col, r[1], r[2])
  }, character(1))

  where <- paste(conditions, collapse = " AND ")

  sql <- sprintf("UPDATE %s SET %s = %s WHERE %s",
                 table, label, ifelse(value, "TRUE", "FALSE"), where)
  .frs_db_execute(conn, sql)
}


#' Classify by break accessibility
#'
#' Segments with no downstream break point are labelled as accessible.
#' Uses `fwa_downstream()` to check if any break is downstream of
#' each segment.
#'
#' @noRd
.frs_classify_breaks <- function(conn, table, label, breaks, value) {
  .frs_validate_identifier(breaks, "breaks table")

  # Segments are accessible if no break point is downstream
  sql <- sprintf(
    "UPDATE %s s SET %s = %s
     WHERE NOT EXISTS (
       SELECT 1 FROM %s b
       JOIN whse_basemapping.fwa_stream_networks_sp f
         ON b.blue_line_key = f.blue_line_key
         AND b.downstream_route_measure >= f.downstream_route_measure
         AND b.downstream_route_measure < f.upstream_route_measure
       WHERE fwa_downstream(
         f.wscode_ltree, f.localcode_ltree,
         s.wscode_ltree, s.localcode_ltree
       )
     )",
    table, label, ifelse(value, "TRUE", "FALSE"), breaks
  )
  .frs_db_execute(conn, sql)
}


#' Apply manual overrides
#'
#' Joins the overrides table to the working table on
#' `blue_line_key` + `downstream_route_measure` and copies the
#' override label value.
#'
#' @noRd
.frs_classify_overrides <- function(conn, table, label, overrides) {
  .frs_validate_identifier(overrides, "overrides table")

  sql <- sprintf(
    "UPDATE %s s SET %s = o.%s
     FROM %s o
     WHERE s.blue_line_key = o.blue_line_key
       AND s.downstream_route_measure = o.downstream_route_measure",
    table, label, label, overrides
  )
  .frs_db_execute(conn, sql)
}
