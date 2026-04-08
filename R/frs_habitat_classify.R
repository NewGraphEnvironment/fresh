#' Classify Habitat for Multiple Species
#'
#' Classify segments in a segmented stream network for one or more
#' species. Produces a long-format output table with one row per
#' segment x species, containing accessibility and habitat type
#' booleans.
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
#' # gradient barriers labeled "gradient_15", "gradient_20", "gradient_25".
#' # See frs_network_segment() for the full setup.
#'
#' # Classify CO, BT, ST — each gets species-specific accessibility.
#' # CO (15% access) is blocked by gradient_15, gradient_20, gradient_25.
#' # BT (25% access) is only blocked by gradient_25.
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
#'   SELECT s.*, h.accessible, h.spawning, h.rearing, h.lake_rearing
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
                                 overwrite = TRUE,
                                 verbose = TRUE) {
  .frs_validate_identifier(table, "streams table")
  .frs_validate_identifier(to, "output table")
  stopifnot(is.character(species), length(species) > 0)
  stopifnot(is.logical(gate), length(gate) == 1)

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
       lake_rearing boolean
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

      label_filter <- .frs_access_label_filter(conn, breaks_tbl, thr)

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

    # Spawning
    spawn_cond <- sprintf("s.gradient >= %s AND s.gradient <= %s",
      .frs_sql_num(sp_params$spawn_gradient_min),
      .frs_sql_num(sp_params$spawn_gradient_max))
    if (!is.null(params_sp$ranges$spawn$channel_width)) {
      cw <- params_sp$ranges$spawn$channel_width
      spawn_cond <- paste0(spawn_cond, sprintf(
        " AND s.channel_width >= %s AND s.channel_width <= %s",
        .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
    }

    # Rearing
    rear_cond <- "FALSE"
    if (!is.null(params_sp$ranges$rear)) {
      parts <- character(0)
      if (!is.null(params_sp$ranges$rear$gradient)) {
        g <- params_sp$ranges$rear$gradient
        parts <- c(parts, sprintf("s.gradient <= %s", .frs_sql_num(g[2])))
      }
      if (!is.null(params_sp$ranges$rear$channel_width)) {
        cw <- params_sp$ranges$rear$channel_width
        parts <- c(parts, sprintf(
          "s.channel_width >= %s AND s.channel_width <= %s",
          .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
      }
      if (length(parts) > 0) rear_cond <- paste(parts, collapse = " AND ")
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

    # INSERT joining pre-computed accessibility
    sql <- sprintf(
      "INSERT INTO %s (id_segment, watershed_group_code, species_code, accessible, spawning, rearing, lake_rearing)
       SELECT
         s.id_segment,
         s.watershed_group_code,
         %s,
         a.accessible,
         CASE WHEN a.accessible AND (%s) THEN TRUE ELSE FALSE END,
         CASE WHEN a.accessible AND (%s) THEN TRUE ELSE FALSE END,
         CASE WHEN a.accessible AND (%s) THEN TRUE ELSE FALSE END
       FROM %s s
       INNER JOIN %s a ON s.id_segment = a.id_segment",
      to, .frs_quote_string(sp),
      spawn_cond, rear_cond, lake_rear_cond,
      table, acc_tbl)

    .frs_db_execute(conn, sql)

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
#' gradient threshold. Gradient labels like `"gradient_15"` are parsed
#' to extract the threshold value. Labels >= the species' threshold
#' block that species. Non-gradient labels (e.g. `"blocked"`) always
#' block.
#'
#' @param conn DBI connection.
#' @param breaks_tbl Breaks table name.
#' @param access_gradient Numeric. Species access gradient max.
#' @return SQL predicate string for filtering breaks.
#' @noRd
.frs_access_label_filter <- function(conn, breaks_tbl, access_gradient) {
  # Get distinct labels from breaks table
  labels <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT label FROM %s", breaks_tbl))$label

  # Determine which labels block this species
  # Only two patterns block:
  #   "blocked" — explicit block label
  #   "gradient_N" — blocks species with access threshold <= N%
  # Everything else (passable, potential, observed, custom labels) does not block
  blocking <- vapply(labels, function(lbl) {
    if (is.na(lbl)) return(FALSE)
    if (identical(lbl, "blocked")) return(TRUE)
    m <- regmatches(lbl, regexec("^gradient_(\\d+)$", lbl))[[1]]
    if (length(m) == 2) {
      return(as.numeric(m[2]) / 100 >= access_gradient)
    }
    FALSE
  }, logical(1))

  blocking_labels <- labels[blocking]

  if (length(blocking_labels) == 0) {
    return("FALSE")  # nothing blocks — all accessible
  }

  quoted <- paste(vapply(blocking_labels, .frs_quote_string, character(1)),
                  collapse = ", ")
  sprintf("b.label IN (%s)", quoted)
}
