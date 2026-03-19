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
#' @param where Character or `NULL`. Optional SQL predicate to scope which
#'   rows are classified. Only rows matching `where` are considered; others
#'   remain `NULL`. Example: `"edge_type IN (1050)"` to classify only lake
#'   segments. Consistent with [frs_aggregate()] `where` parameter.
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
#' # Plot each — this is what piped frs_classify calls produce
#' plot(streams["spawning"], main = paste(
#'   "Spawning:", sum(spawning), "of", nrow(streams), "(gradient 0-2.5%)"),
#'   pal = c("grey80", "steelblue"), key.pos = 1)
#' plot(streams["rearing"], main = paste(
#'   "Rearing:", sum(rearing), "of", nrow(streams), "(gradient 0-5%)"),
#'   pal = c("grey80", "darkorange"), key.pos = 1)
#'
#' \dontrun{
#' # --- Live DB: Richfield Creek — falls, params, accessibility ---
#' # Full pipeline: load params → extract → break at falls → classify
#' conn <- frs_db_conn()
#'
#' # Load coho thresholds from bundled CSV
#' params <- frs_params(csv = system.file("testdata", "test_params.csv",
#'   package = "fresh"))
#' params$CO$ranges$spawn  # gradient 0-5.5%, channel_width 2+
#'
#' # 1. Extract Richfield Creek from fwapg enriched streams
#' # fwa_streams_vw has channel_width (from fwapg regression model)
#' # and uses wscode/localcode (not _ltree suffix). Set options
#' # so classify knows the column names:
#' options(fresh.wscode_col = "wscode",
#'         fresh.localcode_col = "localcode")
#'
#' richfield <- frs_db_query(conn,
#'   "SELECT ST_Union(geom) AS geom
#'    FROM whse_basemapping.fwa_stream_networks_sp
#'    WHERE blue_line_key = 360788426")
#'
#' conn |>
#'   frs_extract("whse_basemapping.fwa_streams_vw",
#'     "working.demo_classify",
#'     cols = c("linear_feature_id", "blue_line_key",
#'              "downstream_route_measure", "upstream_route_measure",
#'              "wscode", "localcode",
#'              "gradient", "channel_width", "geom"),
#'     aoi = richfield, overwrite = TRUE)
#'
#' # 2. Plot BEFORE — all segments with falls location
#' before <- frs_db_query(conn,
#'   "SELECT gradient, geom FROM working.demo_classify")
#' falls_pt <- sf::st_zm(frs_point_locate(conn,
#'   blue_line_key = 360788426, downstream_route_measure = 3461))
#'
#' plot(sf::st_geometry(before), col = "steelblue",
#'      main = paste("Richfield Creek:", nrow(before), "segments"))
#' plot(sf::st_geometry(falls_pt), add = TRUE, pch = 17, col = "red", cex = 2)
#' legend("topright", legend = "Falls", pch = 17, col = "red")
#'
#' # 3. Break at the falls (measure 3461)
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_breaks")
#' DBI::dbExecute(conn,
#'   "CREATE TABLE working.demo_breaks AS
#'    SELECT 360788426 AS blue_line_key,
#'           3460.97::double precision AS downstream_route_measure")
#'
#' # 4. Classify: accessibility + coho spawning (gradient AND channel_width)
#' # Skeena uses channel_width as habitat predictor (MAD not applied here)
#' co_spawn_ranges <- params$CO$ranges$spawn[c("gradient", "channel_width")]
#' conn |>
#'   frs_classify("working.demo_classify", label = "accessible",
#'     breaks = "working.demo_breaks") |>
#'   frs_classify("working.demo_classify", label = "co_spawning",
#'     ranges = co_spawn_ranges)
#'
#' # 5. Plot AFTER — accessibility with falls marker
#' after <- frs_db_query(conn,
#'   "SELECT accessible, co_spawning, gradient, channel_width, geom
#'    FROM working.demo_classify")
#'
#' n_acc <- sum(after$accessible, na.rm = TRUE)
#' n_blk <- sum(is.na(after$accessible))
#' cols_acc <- ifelse(after$accessible %in% TRUE, "steelblue", "grey80")
#' plot(sf::st_geometry(after), col = cols_acc,
#'      main = paste("Accessible:", n_acc, "| Blocked:", n_blk))
#' plot(sf::st_geometry(falls_pt), add = TRUE, pch = 17, col = "red", cex = 2)
#' legend("topright",
#'        legend = c("Accessible", "Blocked", "Falls"),
#'        col = c("steelblue", "grey80", "red"),
#'        lwd = c(2, 2, NA), pch = c(NA, NA, 17))
#'
#' # 6. Accessible coho spawning habitat
#' after$co_spawning_accessible <- after$co_spawning & after$accessible
#' n_sp <- sum(after$co_spawning_accessible, na.rm = TRUE)
#' cols_sp <- ifelse(after$co_spawning_accessible %in% TRUE, "darkorange", "grey80")
#' plot(sf::st_geometry(after), col = cols_sp,
#'      main = paste("Accessible CO spawning:", n_sp, "segments"))
#' plot(sf::st_geometry(falls_pt), add = TRUE, pch = 17, col = "red", cex = 2)
#' legend("topright",
#'        legend = c("CO spawning", "Not habitat", "Falls"),
#'        col = c("darkorange", "grey80", "red"),
#'        lwd = c(2, 2, NA), pch = c(NA, NA, 17))
#'
#' # Clean up
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_classify")
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_breaks")
#' DBI::dbDisconnect(conn)
#' }
frs_classify <- function(conn, table, label,
                         ranges = NULL, breaks = NULL,
                         overrides = NULL, where = NULL,
                         value = TRUE) {
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
    .frs_classify_ranges(conn, table, label, ranges, value, where)
  }

  # Apply breaks classification (accessibility)
  if (has_breaks) {
    .frs_classify_breaks(conn, table, label, breaks, value, where)
  }

  # Apply manual overrides
  if (has_overrides) {
    .frs_classify_overrides(conn, table, label, overrides, where)
  }

  invisible(conn)
}


#' Classify by attribute ranges
#'
#' Sets `label = value` where all range conditions are met (AND).
#'
#' @noRd
.frs_classify_ranges <- function(conn, table, label, ranges, value,
                                 where = NULL) {
  stopifnot(is.list(ranges), length(ranges) > 0)

  conditions <- vapply(names(ranges), function(col) {
    .frs_validate_identifier(col, "range column")
    r <- ranges[[col]]
    stopifnot(is.numeric(r), length(r) == 2)
    sprintf("%s BETWEEN %s AND %s", col, r[1], r[2])
  }, character(1))

  range_clause <- paste(conditions, collapse = " AND ")

  # Append user-supplied where filter
  if (!is.null(where)) {
    range_clause <- paste(range_clause, "AND", where)
  }

  sql <- sprintf("UPDATE %s SET %s = %s WHERE %s",
                 table, label, ifelse(value, "TRUE", "FALSE"), range_clause)
  .frs_db_execute(conn, sql)
}


#' Classify by break accessibility
#'
#' Segments with no downstream break point are labelled as accessible.
#' Uses measure-level precision on the same `blue_line_key` (for split
#' segments that share ltree codes) and `fwa_downstream()` for cross-BLK
#' barriers.
#'
#' @noRd
.frs_classify_breaks <- function(conn, table, label, breaks, value,
                                 where = NULL) {
  .frs_validate_identifier(breaks, "breaks table")

  wsc <- .frs_opt("wscode_col")
  loc <- .frs_opt("localcode_col")
  blk <- .frs_opt("blk_col")
  mds <- .frs_opt("measure_ds_col")
  mus <- .frs_opt("measure_us_col")

  # Segments are accessible if no break is downstream of them.
  # A segment is BLOCKED (upstream of break) when:
  # 1. Same BLK: segment measure >= break measure (break is downstream)
  # 2. Different BLK: fwa_upstream(break_pos, segment) = TRUE
  #    (segment is upstream of the break on the network)
  sql <- sprintf(
    "UPDATE %s s SET %s = %s
     WHERE NOT EXISTS (
       SELECT 1 FROM %s b
       WHERE (
         -- Same BLK: segment is upstream of break if its measure >= break measure
         b.%s = s.%s
         AND b.%s <= s.%s
       )
       OR (
         -- Different BLK: is segment upstream of the break?
         b.%s != s.%s
         AND EXISTS (
           SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp f
           WHERE f.%s = b.%s
             AND b.%s >= f.%s
             AND b.%s < f.%s
             AND fwa_upstream(
               f.wscode_ltree, f.localcode_ltree,
               s.%s, s.%s
             )
         )
       )
     )",
    table, label, ifelse(value, "TRUE", "FALSE"), breaks,
    blk, blk,      # same BLK check
    mds, mds,      # measure comparison
    blk, blk,      # different BLK check
    blk, blk,      # join to FWA
    mds, mds,      # measure range check (ds)
    mds, mus,      # measure range check (us)
    wsc, loc       # ltree columns on working table
  )

  # Append user-supplied where filter to scope which rows get classified
  if (!is.null(where)) {
    sql <- paste(sql, "AND", where)
  }

  .frs_db_execute(conn, sql)
}


#' Apply manual overrides
#'
#' Joins the overrides table to the working table on
#' `blue_line_key` + `downstream_route_measure` and copies the
#' override label value.
#'
#' @noRd
.frs_classify_overrides <- function(conn, table, label, overrides,
                                    where = NULL) {
  .frs_validate_identifier(overrides, "overrides table")

  sql <- sprintf(
    "UPDATE %s s SET %s = o.%s
     FROM %s o
     WHERE s.blue_line_key = o.blue_line_key
       AND s.downstream_route_measure = o.downstream_route_measure",
    table, label, label, overrides
  )

  # Append user-supplied where filter
  if (!is.null(where)) {
    sql <- paste(sql, "AND", where)
  }

  .frs_db_execute(conn, sql)
}
