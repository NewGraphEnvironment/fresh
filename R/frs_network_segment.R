#' Segment a Stream Network at Break Points
#'
#' Build a segmented stream network by extracting base streams, enriching
#' with channel width, and splitting at break points from any number of
#' sources. Assigns a unique `id_segment` to each sub-segment.
#'
#' This function is domain-agnostic — it segments a network at points
#' without knowing what those points represent. Use [frs_break_find()]
#' to generate gradient barriers, then pass the result as a break source
#' alongside falls, crossings, or any other point table.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param aoi AOI specification passed to [frs_extract()]. Character
#'   watershed group code, `sf` polygon, or `NULL`.
#' @param to Character. Schema-qualified output table name
#'   (e.g. `"fresh.streams"`).
#' @param source Character. Source table for the stream network. Default
#'   `"whse_basemapping.fwa_stream_networks_sp"`.
#' @param break_sources List of break source specs, or `NULL` (no
#'   breaking). Each spec is a list with `table`, and optionally `where`,
#'   `label`, `label_col`, `label_map`, `col_blk`, `col_measure`.
#'   See [frs_break_find()] for details.
#' @param overwrite Logical. If `TRUE`, drop `to` before creating.
#'   Default `TRUE`.
#' @param verbose Logical. Print progress. Default `TRUE`.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # --- Full workflow: barriers → segment → classify ---
#' #
#' # Species codes: CO = Coho, CH = Chinook, SK = Sockeye,
#' #   ST = Steelhead, BT = Bull Trout, RB = Rainbow Trout
#'
#' # 1. Generate gradient access barriers at each species threshold.
#' #    CO/CH/SK can't pass 15%, ST can't pass 20%, BT/RB can't pass 25%.
#' #    Thresholds come from parameters_fresh.csv (access_gradient_max).
#' #    frs_break_find needs an extracted network table to get BLK list.
#' frs_extract(conn,
#'   from = "whse_basemapping.fwa_stream_networks_sp",
#'   to = "working.tmp_bulk",
#'   where = "watershed_group_code = 'BULK'")
#'
#' frs_break_find(conn, "working.tmp_bulk",
#'   attribute = "gradient", threshold = 0.15,
#'   to = "working.barriers_15")
#' frs_break_find(conn, "working.tmp_bulk",
#'   attribute = "gradient", threshold = 0.20,
#'   to = "working.barriers_20")
#' frs_break_find(conn, "working.tmp_bulk",
#'   attribute = "gradient", threshold = 0.25,
#'   to = "working.barriers_25")
#'
#' # 2. Segment the network at ALL barrier points + falls.
#' #    One table, one copy of geometry, shared across all species.
#' #    Labels control which species each barrier blocks — gradient_15
#' #    blocks CO but not BT; gradient_25 blocks both.
#' #    Falls (from inst/extdata/falls.csv, loaded to working.falls)
#' #    block all species.
#' frs_network_segment(conn, aoi = "BULK",
#'   to = "fresh.streams",
#'   break_sources = list(
#'     list(table = "working.barriers_15", label = "gradient_15"),
#'     list(table = "working.barriers_20", label = "gradient_20"),
#'     list(table = "working.barriers_25", label = "gradient_25"),
#'     list(table = "working.falls",
#'          where = "barrier_ind = TRUE", label = "blocked")
#'   ))
#'
#' # 3. Classify habitat — see frs_habitat_classify() for details.
#' #    Writes to fresh.streams_habitat (long format, no geometry).
#' #    id_segment links back to fresh.streams for mapping.
#' frs_habitat_classify(conn,
#'   table = "fresh.streams",
#'   to = "fresh.streams_habitat",
#'   species = c("CO", "BT", "ST"))
#'
#' # Check results
#' DBI::dbGetQuery(conn, "
#'   SELECT species_code,
#'          count(*) FILTER (WHERE accessible) as accessible,
#'          count(*) FILTER (WHERE spawning) as spawning
#'   FROM fresh.streams_habitat
#'   GROUP BY species_code")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_network_segment <- function(conn, aoi, to,
                                source = "whse_basemapping.fwa_stream_networks_sp",
                                break_sources = NULL,
                                overwrite = TRUE,
                                verbose = TRUE) {
  .frs_validate_identifier(to, "output table")

  t0 <- proc.time()

  # -- Extract base network --------------------------------------------------
  if (overwrite) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  }

  if (is.character(aoi) && length(aoi) == 1 && grepl("^[A-Z]{4}$", aoi)) {
    frs_extract(conn, from = source, to = to,
      where = paste0("watershed_group_code = ", .frs_quote_string(aoi)),
      overwrite = FALSE)
  } else {
    frs_extract(conn, from = source, to = to,
      aoi = aoi, overwrite = FALSE)
  }

  if (verbose) {
    n <- DBI::dbGetQuery(conn,
      sprintf("SELECT count(*)::int AS n FROM %s", to))$n
    cat("  Base: ", n, " segments (",
        round((proc.time() - t0)["elapsed"], 1), "s)\n", sep = "")
  }

  # -- Enrich with channel width ---------------------------------------------
  frs_col_join(conn, to,
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")

  # -- Add id_segment --------------------------------------------------------
  .frs_add_id_segment(conn, to)

  # -- Apply break sources ---------------------------------------------------
  if (!is.null(break_sources) && length(break_sources) > 0) {
    breaks_tbl <- paste0(to, "_breaks")

    for (i in seq_along(break_sources)) {
      src <- break_sources[[i]]
      .frs_validate_identifier(src$table, "break source table")
      t1 <- proc.time()

      frs_feature_find(conn, to,
        points_table = src$table,
        where = src$where,
        label = src$label,
        label_col = src$label_col,
        label_map = src$label_map,
        col_blk = if (is.null(src$col_blk)) "blue_line_key" else src$col_blk,
        col_measure = if (is.null(src$col_measure)) "downstream_route_measure" else src$col_measure,
        to = breaks_tbl,
        overwrite = (i == 1), append = (i > 1))

      if (verbose) {
        n_brk <- DBI::dbGetQuery(conn,
          sprintf("SELECT count(*)::int AS n FROM %s WHERE source = %s",
                  breaks_tbl, .frs_quote_string(src$table)))$n
        cat("  Breaks from ", src$table, ": ", n_brk, " (",
            round((proc.time() - t1)["elapsed"], 1), "s)\n", sep = "")
      }
    }

    # Enrich breaks with ltree for classify + index
    .frs_enrich_breaks(conn, breaks_tbl)
    .frs_index_working(conn, breaks_tbl)

    # Apply breaks to geometry
    t1 <- proc.time()
    frs_break_apply(conn, to, breaks = breaks_tbl, segment_id = "id_segment")

    if (verbose) {
      n <- DBI::dbGetQuery(conn,
        sprintf("SELECT count(*)::int AS n FROM %s", to))$n
      cat("  Segmented: ", n, " segments (",
          round((proc.time() - t1)["elapsed"], 1), "s)\n", sep = "")
    }

    # Recompute gradient/measures from new geometry
    frs_col_generate(conn, to)

    # Keep breaks table for frs_habitat_classify (accessibility check)
    # Caller or frs_habitat can clean up later
  }

  # -- Index -----------------------------------------------------------------
  .frs_index_working(conn, to)

  if (verbose) {
    total <- round((proc.time() - t0)["elapsed"], 1)
    cat("  Total: ", total, "s\n", sep = "")
  }

  invisible(conn)
}
