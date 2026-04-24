#' Classify Habitat for Multiple Species
#'
#' Fish-habitat convenience wrapper. Classifies segments in a segmented
#' stream network for one or more species into a fixed output schema of
#' `accessible / spawning / rearing / lake_rearing / wetland_rearing`
#' booleans keyed by `species_code`. Produces long-format output: one
#' row per segment x species.
#'
#' For non-fish domains — thermal refugia, riparian connectivity,
#' sediment-transport models, any classification that doesn't fit the
#' fixed output schema above — compose [frs_classify()] directly on
#' your own output table. `frs_classify()` is pipeable, takes any
#' `label` column name, and has no assumptions about what's being
#' modelled.
#'
#' Requires a segmented streams table (from [frs_network_segment()])
#' with `id_segment`, gradient, channel width, and ltree columns, plus
#' a breaks table (`{streams_table}_breaks`) for accessibility checks.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Schema-qualified segmented streams table
#'   (from [frs_network_segment()]).
#' @param to Character. Schema-qualified output table for habitat
#'   classifications (e.g. `"fresh.streams_habitat"`).
#' @param species Character vector. Species codes to classify
#'   (e.g. `c("CO", "BT")`).
#' @param params Named list from [frs_params()]. Default reads from
#'   bundled CSV.
#' @param params_fresh Data frame from `parameters_fresh.csv`. Default
#'   reads from bundled CSV.
#' @param gate Logical. If `TRUE` (default), breaks restrict
#'   classification — segments downstream of blocking breaks are marked
#'   inaccessible. If `FALSE`, all segments are classified regardless of
#'   breaks (raw habitat potential).
#' @param label_block Character vector. Labels that always block
#'   access. Default `"blocked"`. Gradient labels (`gradient_NNNN`,
#'   the canonical 4-digit basis-point format like `gradient_1500` for
#'   15%, or the legacy `gradient_N` like `gradient_15`) are always
#'   threshold-aware regardless of this parameter. Set to
#'   `c("blocked", "potential")` for conservative analysis.
#' @param barrier_overrides Character or `NULL`. Schema-qualified table
#'   of per-species barrier overrides (a "skip list") with columns
#'   `blue_line_key`, `downstream_route_measure`, `species_code`.
#'   Prepared by [link::lnk_barrier_overrides()] or equivalent. When
#'   provided and `gate = TRUE`, any blocking break whose position +
#'   species matches a row in this table is ignored during access
#'   gating — observations or habitat confirmations upstream have
#'   overridden the barrier for that species. Default `NULL` (no
#'   overrides; every blocking break restricts access).
#' @param overwrite Logical. If `TRUE`, replace existing rows for
#'   these species in the output table. Default `TRUE`.
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
#' # Assumes fresh.streams built by frs_network_segment() with
#' # gradient barriers labeled "gradient_1500", "gradient_2000",
#' # "gradient_2500" (15%, 20%, 25% — see frs_network_segment()).
#'
#' # Classify CO, BT, ST — each gets species-specific accessibility.
#' # CO (15% access) is blocked by gradient_1500, gradient_2000,
#' # gradient_2500. BT (25% access) is only blocked by gradient_2500.
#' # Result: BT has ~2x the accessible habitat of CO on the same network.
#' frs_habitat_classify(conn,
#'   table = "fresh.streams",
#'   to = "fresh.streams_habitat",
#'   species = c("CO", "BT", "ST"))
#'
#' # Query results — one table, all species, no geometry
#' DBI::dbGetQuery(conn, "
#'   SELECT species_code,
#'          count(*) FILTER (WHERE accessible) as accessible,
#'          count(*) FILTER (WHERE spawning) as spawning,
#'          count(*) FILTER (WHERE rearing) as rearing
#'   FROM fresh.streams_habitat
#'   GROUP BY species_code")
#'
#' # Join geometry back for mapping — id_segment links the two tables
#' DBI::dbExecute(conn, "
#'   CREATE OR REPLACE VIEW fresh.streams_co_vw AS
#'   SELECT s.*, h.accessible, h.spawning, h.rearing, h.lake_rearing, h.wetland_rearing
#'   FROM fresh.streams s
#'   JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
#'   WHERE h.species_code = 'CO'")
#'
#' # Re-running is safe — existing rows for these species are replaced.
#' # Run more WSGs later and both tables accumulate.
#'
#' DBI::dbDisconnect(conn)
#' }
frs_habitat_classify <- function(conn, table, to,
                                 species,
                                 params = NULL,
                                 params_fresh = NULL,
                                 gate = TRUE,
                                 label_block = "blocked",
                                 barrier_overrides = NULL,
                                 overwrite = TRUE,
                                 verbose = TRUE) {
  .frs_validate_identifier(table, "streams table")
  .frs_validate_identifier(to, "output table")
  stopifnot(is.character(species), length(species) > 0)
  stopifnot(is.logical(gate), length(gate) == 1)
  if (!is.null(barrier_overrides)) {
    .frs_validate_identifier(barrier_overrides, "barrier_overrides table")
  }

  breaks_tbl <- paste0(table, "_breaks")

  # Load parameters
  if (is.null(params)) {
    params <- frs_params(csv = system.file("extdata",
      "parameters_habitat_thresholds.csv", package = "fresh"))
  }
  if (is.null(params_fresh)) {
    params_fresh <- utils::read.csv(system.file("extdata",
      "parameters_fresh.csv", package = "fresh"), stringsAsFactors = FALSE)
  }

  # Ensure input tables are indexed — critical when called directly
  # (bypassing frs_habitat which indexes during frs_network_segment)
  .frs_index_working(conn, table)
  if (gate) .frs_index_working(conn, breaks_tbl)

  # Get WSG codes from streams table (for idempotent delete)
  wsg_codes <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT watershed_group_code FROM %s", table
  ))$watershed_group_code

  # Create output table if not exists
  .frs_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s (
       id_segment integer,
       watershed_group_code character varying(4),
       species_code text,
       accessible boolean,
       spawning boolean,
       rearing boolean,
       lake_rearing boolean,
       wetland_rearing boolean
     )", to))

  # Delete existing rows for these WSGs — fast column filter, no subquery
  if (overwrite) {
    for (wsg in wsg_codes) {
      .frs_db_execute(conn, sprintf(
        "DELETE FROM %s WHERE watershed_group_code = %s",
        to, .frs_quote_string(wsg)))
    }
  }

  # -- Pre-compute accessibility per unique threshold -------------------------
  # Species sharing the same access_gradient_max get identical accessibility.
  # Compute once per threshold, store in temp tables, reuse across species.
  species_params <- lapply(species, function(sp) {
    ps <- params[[sp]]
    fp <- params_fresh[params_fresh$species_code == sp, ]
    if (is.null(ps) || nrow(fp) == 0) return(NULL)
    list(
      species_code = sp,
      access_gradient = fp$access_gradient_max,
      spawn_gradient_max = ps$spawn_gradient_max,
      spawn_gradient_min = if (is.null(fp$spawn_gradient_min) ||
                               is.na(fp$spawn_gradient_min)) 0 else
        fp$spawn_gradient_min,
      params_sp = ps)
  })
  species_params <- Filter(Negate(is.null), species_params)

  access_thresholds <- sort(unique(vapply(species_params,
    function(x) x$access_gradient, numeric(1))))

  # Compute accessibility once per threshold (or skip if gate = FALSE)
  access_tables <- list()

  if (!gate) {
    # Ungated: all segments accessible — classify based on attributes alone
    acc_tbl <- paste0(table, "_acc_all")
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", acc_tbl))
    .frs_db_execute(conn, sprintf(
      "CREATE TABLE %s AS SELECT id_segment, TRUE AS accessible FROM %s",
      acc_tbl, table))
    .frs_db_execute(conn, sprintf("CREATE INDEX ON %s (id_segment)", acc_tbl))
    for (thr in access_thresholds) {
      access_tables[[as.character(thr)]] <- acc_tbl
    }
    if (verbose) cat("  Ungated: all segments accessible\n")
  } else {
    for (thr in access_thresholds) {
      t0 <- proc.time()
      thr_key <- as.character(thr)
      acc_tbl <- paste0(table, "_acc_", gsub("\\.", "", thr_key))

      label_filter <- .frs_access_label_filter(conn, breaks_tbl, thr,
                                                label_block)

      .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", acc_tbl))
      .frs_db_execute(conn, sprintf(
        "CREATE TABLE %s AS
         SELECT s.id_segment,
           NOT EXISTS (
             SELECT 1 FROM %s b
             WHERE (%s)
               AND b.blue_line_key = s.blue_line_key
               AND b.downstream_route_measure <= s.downstream_route_measure
           )
           AND NOT EXISTS (
             SELECT 1 FROM %s b
             WHERE (%s)
               AND b.blue_line_key != s.blue_line_key
               AND b.wscode_ltree IS NOT NULL
               AND fwa_upstream(b.wscode_ltree, b.localcode_ltree,
                                s.wscode_ltree, s.localcode_ltree)
           ) AS accessible
         FROM %s s",
        acc_tbl, breaks_tbl, label_filter, breaks_tbl, label_filter, table))

    .frs_db_execute(conn, sprintf("CREATE INDEX ON %s (id_segment)", acc_tbl))

    access_tables[[thr_key]] <- acc_tbl

    if (verbose) {
      n_acc <- DBI::dbGetQuery(conn, sprintf(
        "SELECT count(*) FILTER (WHERE accessible)::int AS n FROM %s",
        acc_tbl))$n
      cat("  Access ", thr * 100, "%%: ", n_acc, " accessible (",
          round((proc.time() - t0)["elapsed"], 1), "s)\n", sep = "")
    }
  }
  }  # end gate if/else

  # -- Classify each species using pre-computed accessibility -----------------
  for (sp_params in species_params) {
    t0 <- proc.time()
    sp <- sp_params$species_code
    thr_key <- as.character(sp_params$access_gradient)
    acc_tbl <- access_tables[[thr_key]]
    params_sp <- sp_params$params_sp

    # Edge type filter helper
    edge_filter <- function(types_str) {
      if (is.null(types_str) || is.na(types_str) || !nzchar(types_str)) {
        return(NULL)
      }
      cats <- trimws(strsplit(types_str, ",")[[1]])
      codes <- unlist(lapply(cats, function(cat) {
        frs_edge_types(category = cat)$edge_type
      }))
      if (length(codes) == 0) return(NULL)
      sprintf("s.edge_type IN (%s)", paste(codes, collapse = ", "))
    }

    # Spawning — rules YAML path or CSV ranges path
    if (!is.null(params_sp[["rules"]]) &&
        !is.null(params_sp[["rules"]][["spawn"]])) {
      # Rules path: build CSV thresholds (with spawn min) for inheritance
      csv_thresholds_spawn <- list(
        gradient = c(sp_params$spawn_gradient_min,
                     sp_params$spawn_gradient_max),
        channel_width = params_sp$ranges$spawn$channel_width)
      spawn_cond <- .frs_rules_to_sql(params_sp[["rules"]][["spawn"]],
                                      csv_thresholds_spawn)
    } else {
      # CSV ranges path (pre-rules behavior)
      spawn_cond <- sprintf("s.gradient >= %s AND s.gradient <= %s",
        .frs_sql_num(sp_params$spawn_gradient_min),
        .frs_sql_num(sp_params$spawn_gradient_max))
      if (!is.null(params_sp$ranges$spawn$channel_width)) {
        cw <- params_sp$ranges$spawn$channel_width
        spawn_cond <- paste0(spawn_cond, sprintf(
          " AND s.channel_width >= %s AND s.channel_width <= %s",
          .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
      }
      spawn_et <- edge_filter(params_sp$spawn_edge_types)
      if (!is.null(spawn_et)) {
        spawn_cond <- paste(spawn_cond, "AND", spawn_et)
      }
    }

    # Rearing — rules YAML path or CSV ranges path
    if (!is.null(params_sp[["rules"]]) &&
        !is.null(params_sp[["rules"]][["rear"]])) {
      # Rules path: csv_thresholds use rear gradient (min=0) and cw
      rear_g <- params_sp$ranges$rear$gradient
      csv_thresholds_rear <- list(
        gradient = if (is.null(rear_g)) NULL else c(0, rear_g[2]),
        channel_width = params_sp$ranges$rear$channel_width)
      rear_cond <- .frs_rules_to_sql(params_sp[["rules"]][["rear"]],
                                     csv_thresholds_rear)
    } else {
      # CSV ranges path (pre-rules behavior)
      rear_cond <- "FALSE"
      if (!is.null(params_sp$ranges$rear)) {
        parts <- character(0)
        if (!is.null(params_sp$ranges$rear$gradient)) {
          g <- params_sp$ranges$rear$gradient
          parts <- c(parts, sprintf("s.gradient <= %s",
                                    .frs_sql_num(g[2])))
        }
        if (!is.null(params_sp$ranges$rear$channel_width)) {
          cw <- params_sp$ranges$rear$channel_width
          parts <- c(parts, sprintf(
            "s.channel_width >= %s AND s.channel_width <= %s",
            .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
        }
        rear_et <- edge_filter(params_sp$rear_edge_types)
        if (!is.null(rear_et)) parts <- c(parts, rear_et)
        if (length(parts) > 0) rear_cond <- paste(parts, collapse = " AND ")
      }
    }

    # Barrier overrides: if a barrier_overrides table is provided,
    # recompute access for this species excluding overridden barriers.
    # The overrides table has (blue_line_key, downstream_route_measure,
    # species_code) — prepared by link via lnk_barrier_overrides().
    acc_tbl_sp <- acc_tbl  # default: use the shared threshold-based table
    if (gate && !is.null(barrier_overrides)) {
      sp_label_filter <- .frs_access_label_filter(
        conn, breaks_tbl, sp_params$access_gradient, label_block)
      acc_tbl_sp <- .frs_access_with_overrides(
        conn, table, breaks_tbl, barrier_overrides,
        sp_label_filter, sp, acc_tbl)
    }

    # Lake rearing
    lake_rear_cond <- "FALSE"
    if (!is.null(params_sp$ranges$rear$channel_width)) {
      cw <- params_sp$ranges$rear$channel_width
      lake_rear_cond <- sprintf(
        "s.channel_width >= %s AND s.channel_width <= %s
         AND s.waterbody_key IN (
           SELECT waterbody_key FROM whse_basemapping.fwa_lakes_poly)",
        .frs_sql_num(cw[1]), .frs_sql_num(cw[2]))
    }

    # Wetland rearing — mirrors lake rearing, joined to fwa_wetlands_poly
    # instead. Per-species opt-in via rules YAML / dimensions.csv lands on
    # top of this column; this is the raw "segment is a wetland under the
    # species' rear channel-width window" flag.
    wetland_rear_cond <- "FALSE"
    if (!is.null(params_sp$ranges$rear$channel_width)) {
      cw <- params_sp$ranges$rear$channel_width
      wetland_rear_cond <- sprintf(
        "s.channel_width >= %s AND s.channel_width <= %s
         AND s.waterbody_key IN (
           SELECT waterbody_key FROM whse_basemapping.fwa_wetlands_poly)",
        .frs_sql_num(cw[1]), .frs_sql_num(cw[2]))
    }

    # INSERT joining pre-computed accessibility
    sql <- sprintf(
      "INSERT INTO %s (id_segment, watershed_group_code, species_code, accessible, spawning, rearing, lake_rearing, wetland_rearing)
       SELECT
         s.id_segment,
         s.watershed_group_code,
         %s,
         a.accessible,
         CASE WHEN a.accessible AND (%s) THEN TRUE ELSE FALSE END,
         CASE WHEN a.accessible AND (%s) THEN TRUE ELSE FALSE END,
         CASE WHEN a.accessible AND (%s) THEN TRUE ELSE FALSE END,
         CASE WHEN a.accessible AND (%s) THEN TRUE ELSE FALSE END
       FROM %s s
       INNER JOIN %s a ON s.id_segment = a.id_segment",
      to, .frs_quote_string(sp),
      spawn_cond, rear_cond, lake_rear_cond, wetland_rear_cond,
      table, acc_tbl_sp)

    .frs_db_execute(conn, sql)

    # Clean up per-species access table if observation override created one
    if (acc_tbl_sp != acc_tbl) {
      .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", acc_tbl_sp))
    }

    if (verbose) {
      elapsed <- round((proc.time() - t0)["elapsed"], 1)
      stats <- DBI::dbGetQuery(conn, sprintf(
        "SELECT count(*) FILTER (WHERE accessible)::int AS acc,
                count(*) FILTER (WHERE spawning)::int AS spn,
                count(*) FILTER (WHERE rearing)::int AS rr
         FROM %s WHERE species_code = %s",
        to, .frs_quote_string(sp)))
      cat("  ", sp, ": ", elapsed, "s (",
          stats$acc, " accessible, ",
          stats$spn, " spawning, ",
          stats$rr, " rearing)\n", sep = "")
    }
  }

  # Clean up accessibility temp tables
  for (acc_tbl in access_tables) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", acc_tbl))
  }

  .frs_index_working(conn, to)

  invisible(conn)
}


#' Build SQL label filter for species-specific accessibility
#'
#' Determines which break labels block a species based on its access
#' gradient threshold. Gradient labels like `"gradient_1500"` (new
#' 4-digit basis-point format) or `"gradient_15"` (legacy) are parsed
#' to extract the threshold value. Labels >= the species' threshold
#' block that species. Non-gradient labels (e.g. `"blocked"`) always
#' block.
#'
#' @param conn DBI connection.
#' @param breaks_tbl Breaks table name.
#' @param access_gradient Numeric. Species access gradient max.
#' @return SQL predicate string for filtering breaks.
#' @noRd
.frs_access_label_filter <- function(conn, breaks_tbl, access_gradient,
                                     label_block = "blocked") {
  # Get distinct labels from breaks table
  labels <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT label FROM %s", breaks_tbl))$label

  # Determine which labels block this species
  # Patterns recognized:
  #   label_block — user-configured labels that always block
  #   "gradient_NNNN" — new format (4-digit basis points * 10).
  #     Parsed as N / 10000. Resolution 0.0001.
  #   "gradient_N"  — legacy format (integer percent, 1-3 digits).
  #     Parsed as N / 100. Backward compat for user-supplied labels
  #     like `frs_break_find(label = "gradient_15")`.
  # Everything else does not block
  blocking <- vapply(labels, function(lbl) {
    if (is.na(lbl)) return(FALSE)
    if (lbl %in% label_block) return(TRUE)
    # New format: gradient_NNNN
    m4 <- regmatches(lbl, regexec("^gradient_(\\d{4})$", lbl))[[1]]
    if (length(m4) == 2) {
      return(as.numeric(m4[2]) / 10000 >= access_gradient)
    }
    # Legacy format: gradient_N (1-3 digits)
    m_legacy <- regmatches(lbl, regexec("^gradient_(\\d{1,3})$", lbl))[[1]]
    if (length(m_legacy) == 2) {
      return(as.numeric(m_legacy[2]) / 100 >= access_gradient)
    }
    FALSE
  }, logical(1))

  labels_matched <- labels[blocking]

  if (length(labels_matched) == 0) {
    return("FALSE")  # nothing blocks — all accessible
  }

  quoted <- paste(vapply(labels_matched, .frs_quote_string, character(1)),
                  collapse = ", ")
  sprintf("b.label IN (%s)", quoted)
}


#' Recompute accessibility excluding overridden barriers
#'
#' For a species with entries in the `barrier_overrides` table, exclude
#' those barriers from the access computation. The overrides table has
#' `(blue_line_key, downstream_route_measure, species_code)` — prepared
#' by link via `lnk_barrier_overrides()`.
#'
#' @param conn DBI connection.
#' @param table Streams table.
#' @param breaks_tbl Breaks table.
#' @param barrier_overrides Overrides table name.
#' @param label_filter SQL predicate for blocking labels.
#' @param sp Species code.
#' @param base_acc_tbl The shared access table (for table naming).
#' @return Character. Name of the per-species access table.
#' @noRd
.frs_access_with_overrides <- function(conn, table, breaks_tbl,
                                       barrier_overrides, label_filter,
                                       sp, base_acc_tbl) {
  sp_quoted <- .frs_quote_string(sp)
  acc_tbl_sp <- sprintf("%s_ovr_%s", base_acc_tbl, tolower(sp))

  # Check if this species has any overrides
  n_ovr <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s WHERE species_code = %s",
    barrier_overrides, sp_quoted))$n

  if (n_ovr == 0) return(base_acc_tbl)

  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", acc_tbl_sp))
  .frs_db_execute(conn, sprintf(
    "CREATE TABLE %s AS
     SELECT s.id_segment,
       NOT EXISTS (
         SELECT 1 FROM %s b
         WHERE (%s)
           AND b.blue_line_key = s.blue_line_key
           AND b.downstream_route_measure <= s.downstream_route_measure
           AND NOT EXISTS (
             SELECT 1 FROM %s ovr
             WHERE ovr.blue_line_key = b.blue_line_key
               AND ovr.downstream_route_measure = b.downstream_route_measure
               AND ovr.species_code = %s
           )
       )
       AND NOT EXISTS (
         SELECT 1 FROM %s b
         WHERE (%s)
           AND b.blue_line_key != s.blue_line_key
           AND b.wscode_ltree IS NOT NULL
           AND fwa_upstream(b.wscode_ltree, b.localcode_ltree,
                            s.wscode_ltree, s.localcode_ltree)
           AND NOT EXISTS (
             SELECT 1 FROM %s ovr
             WHERE ovr.blue_line_key = b.blue_line_key
               AND ovr.downstream_route_measure = b.downstream_route_measure
               AND ovr.species_code = %s
           )
       ) AS accessible
     FROM %s s",
    acc_tbl_sp,
    breaks_tbl, label_filter, barrier_overrides, sp_quoted,
    breaks_tbl, label_filter, barrier_overrides, sp_quoted,
    table))

  .frs_db_execute(conn, sprintf("CREATE INDEX ON %s (id_segment)",
                                acc_tbl_sp))

  acc_tbl_sp
}
