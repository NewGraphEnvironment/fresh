#' Run Habitat Pipeline for a Watershed Group
#'
#' Orchestrate the full habitat pipeline for all species present in one or
#' more watershed groups. Extracts the base stream network once, computes
#' access barriers once per unique access gradient threshold, habitat breaks
#' once per unique spawn gradient threshold, then classifies habitat per
#' species. Both break types are deduplicated across species that share the
#' same thresholds.
#'
#' Output tables mirror bcfishpass naming: `working.streams_co`,
#' `working.streams_bt`, etc. Each species gets its own table because break
#' points create different segment geometries per threshold group.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param wsg Character. One or more watershed group codes
#'   (e.g. `"BULK"`, `c("BULK", "MORR")`).
#' @param base_tbl Character. Name for the base stream network table. Default
#'   `"working.streams"`.
#' @param workers Integer. Number of parallel workers for the per-species
#'   classification step. Default `1` (sequential). Values > 1 require
#'   the `furrr` package and use `future::plan(multisession)`. Each worker
#'   opens its own database connection.
#' @param cleanup Logical. Drop intermediate tables (base network, break
#'   tables) when done. Default `TRUE`.
#' @param verbose Logical. Print progress and timing. Default `TRUE`.
#'
#' @return A data frame summarising the run: one row per species with columns
#'   `species_code`, `access_threshold`, `habitat_threshold`, `elapsed_s`,
#'   and `table_name`.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Single watershed group
#' result <- frs_habitat(conn, "BULK")
#' result
#'
#' # Multiple watershed groups
#' result <- frs_habitat(conn, c("BULK", "MORR"))
#'
#' DBI::dbDisconnect(conn)
#' }
frs_habitat <- function(conn, wsg, base_tbl = "working.streams",
                        workers = 1L, cleanup = TRUE, verbose = TRUE) {
  stopifnot(is.character(wsg), length(wsg) > 0)
  .frs_validate_identifier(base_tbl, "base table")

  t_total <- proc.time()

  # -- Load parameters --------------------------------------------------------
  params_all <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"))
  params_fresh <- utils::read.csv(system.file("extdata",
    "parameters_fresh.csv", package = "fresh"), stringsAsFactors = FALSE)

  # -- Species to model -------------------------------------------------------
  sp_df <- frs_wsg_species(wsg)
  sp_df <- sp_df[!is.na(sp_df$view), ]

  # Only species with both threshold and fresh params
  sp_df <- sp_df[sp_df$species_code %in% names(params_all) &
                 sp_df$species_code %in% params_fresh$species_code, ]

  if (nrow(sp_df) == 0) {
    stop("No modelable species found for WSG: ", paste(wsg, collapse = ", "),
         call. = FALSE)
  }

  sp_df <- sp_df[!duplicated(sp_df$species_code), ]

  # Add threshold columns for grouping
  sp_df$access_gradient <- vapply(sp_df$species_code, function(sc) {
    params_fresh[params_fresh$species_code == sc, "access_gradient_max"]
  }, numeric(1))

  sp_df$spawn_gradient_max <- vapply(sp_df$species_code, function(sc) {
    params_all[[sc]]$spawn_gradient_max
  }, numeric(1))

  if (verbose) {
    cat("Species:", paste(sp_df$species_code, collapse = ", "), "\n")
  }

  # -- Extract base network ---------------------------------------------------
  t0 <- proc.time()
  where_wsg <- paste0("watershed_group_code IN (",
    paste(vapply(wsg, .frs_quote_string, character(1)), collapse = ", "), ")")

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = base_tbl,
    where = where_wsg,
    overwrite = TRUE)

  frs_col_join(conn, base_tbl,
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")

  extract_s <- (proc.time() - t0)["elapsed"]
  if (verbose) {
    n <- DBI::dbGetQuery(conn,
      sprintf("SELECT count(*)::int AS n FROM %s", base_tbl))$n
    cat("Base network: ", n, " segments (", round(extract_s, 1), "s)\n",
        sep = "")
  }

  # -- Pre-compute access barriers (grouped by threshold) ---------------------
  access_thresholds <- sort(unique(sp_df$access_gradient))
  breaks_access <- character(0)

  for (thr in access_thresholds) {
    thr_label <- .frs_thr_label(thr)
    tbl <- paste0("working.breaks_access_", thr_label)
    breaks_access <- c(breaks_access, tbl)

    t0 <- proc.time()
    frs_habitat_access(conn, base_tbl, threshold = thr, to = tbl, aoi = wsg)

    if (verbose) {
      spp <- sp_df$species_code[sp_df$access_gradient == thr]
      cat("Access ", thr * 100, "%: ", round((proc.time() - t0)["elapsed"], 1),
          "s (", paste(spp, collapse = ", "), ")\n", sep = "")
    }
  }

  # -- Pre-compute habitat breaks (grouped by spawn_gradient_max) -------------
  habitat_thresholds <- sort(unique(sp_df$spawn_gradient_max))
  breaks_habitat <- character(0)

  for (thr in habitat_thresholds) {
    thr_label <- .frs_thr_label(thr)
    tbl <- paste0("working.breaks_habitat_", thr_label)
    breaks_habitat <- c(breaks_habitat, tbl)

    t0 <- proc.time()
    frs_break_find(conn, base_tbl,
      attribute = "gradient", threshold = thr,
      to = tbl)

    if (verbose) {
      spp <- sp_df$species_code[sp_df$spawn_gradient_max == thr]
      cat("Habitat ", thr * 100, "%: ",
          round((proc.time() - t0)["elapsed"], 1),
          "s (", paste(spp, collapse = ", "), ")\n", sep = "")
    }
  }

  # -- Classify per species ---------------------------------------------------
  # Build job list: one row per species with its break table names
  jobs <- lapply(seq_len(nrow(sp_df)), function(i) {
    list(
      species_code = sp_df$species_code[i],
      access_threshold = sp_df$access_gradient[i],
      habitat_threshold = sp_df$spawn_gradient_max[i],
      acc_tbl = paste0("working.breaks_access_",
                       .frs_thr_label(sp_df$access_gradient[i])),
      hab_tbl = paste0("working.breaks_habitat_",
                       .frs_thr_label(sp_df$spawn_gradient_max[i])),
      params_sp = params_all[[sp_df$species_code[i]]],
      fresh_sp = params_fresh[params_fresh$species_code ==
                                sp_df$species_code[i], ]
    )
  })

  # Worker function: opens its own connection, classifies, returns timing
  .run_one_species <- function(job, base_tbl) {
    worker_conn <- frs_db_conn()
    on.exit(DBI::dbDisconnect(worker_conn))
    t0 <- proc.time()
    frs_habitat_species(worker_conn, job$species_code, base_tbl,
      breaks = job$acc_tbl,
      breaks_habitat = job$hab_tbl,
      params_sp = job$params_sp,
      fresh_sp = job$fresh_sp)
    elapsed <- (proc.time() - t0)["elapsed"]
    data.frame(
      species_code = job$species_code,
      access_threshold = job$access_threshold,
      habitat_threshold = job$habitat_threshold,
      elapsed_s = elapsed,
      table_name = paste0("working.streams_", tolower(job$species_code)),
      stringsAsFactors = FALSE
    )
  }

  workers <- as.integer(workers)
  if (workers > 1L) {
    if (!requireNamespace("furrr", quietly = TRUE)) {
      stop("furrr package required for parallel execution (workers > 1)",
           call. = FALSE)
    }
    if (verbose) cat("Classifying ", nrow(sp_df), " species (",
                     workers, " workers)...\n", sep = "")
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
    result_list <- furrr::future_map(jobs, .run_one_species,
      base_tbl = base_tbl,
      .options = furrr::furrr_options(
        seed = TRUE,
        packages = "fresh"
      ))
  } else {
    result_list <- lapply(jobs, function(job) {
      res <- .run_one_species(job, base_tbl)
      if (verbose) {
        cat("  ", res$species_code, ": ", round(res$elapsed_s, 1),
            "s -> ", res$table_name, "\n", sep = "")
      }
      res
    })
  }

  results <- do.call(rbind, result_list)
  if (verbose && workers > 1L) {
    for (i in seq_len(nrow(results))) {
      cat("  ", results$species_code[i], ": ", round(results$elapsed_s[i], 1),
          "s -> ", results$table_name[i], "\n", sep = "")
    }
  }

  # -- Cleanup ----------------------------------------------------------------
  if (cleanup) {
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", base_tbl))
    for (bt in c(breaks_access, breaks_habitat)) {
      .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", bt))
    }
  }

  total_s <- (proc.time() - t_total)["elapsed"]
  if (verbose) {
    cat("Total: ", round(total_s, 1), "s\n", sep = "")
  }

  invisible(results)
}


#' Compute Access Barriers at a Gradient Threshold
#'
#' Find gradient-based access barriers and barrier falls, write them to a
#' breaks table. This is the expensive step in the habitat pipeline —
#' `fwa_slopealonginterval()` runs on every blue line key. Species that share
#' the same `access_gradient_max` can reuse the same breaks table, avoiding
#' redundant computation.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Working schema table with the stream network
#'   (from [frs_extract()]).
#' @param threshold Numeric. Access gradient threshold (e.g. `0.15` for 15%).
#' @param to Character. Destination table for break points. Default
#'   `"working.breaks_access"`.
#' @param falls Character or `NULL`. Schema-qualified table of falls with
#'   `barrier_ind` column. Default `"bcfishpass.falls_vw"`. Set to `NULL`
#'   to skip falls barriers.
#' @param falls_where Character. SQL predicate to filter falls. Default
#'   `"barrier_ind = TRUE"`.
#' @param aoi AOI specification for filtering falls (passed to
#'   [frs_break_find()]). Default `NULL`.
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
#' # Compute access barriers at 15% gradient (coho/chinook/pink/sockeye)
#' frs_habitat_access(conn, "working.streams", threshold = 0.15,
#'   to = "working.breaks_access_015", aoi = "BULK")
#'
#' # Reuse for all species in that group
#' frs_habitat_species(conn, "CO", "working.streams",
#'   breaks = "working.breaks_access_015")
#' frs_habitat_species(conn, "CH", "working.streams",
#'   breaks = "working.breaks_access_015")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_habitat_access <- function(conn, table, threshold,
                               to = "working.breaks_access",
                               falls = "bcfishpass.falls_vw",
                               falls_where = "barrier_ind = TRUE",
                               aoi = NULL) {
  .frs_validate_identifier(table, "source table")
  .frs_validate_identifier(to, "destination table")
  stopifnot(is.numeric(threshold), length(threshold) == 1)

  # Gradient barriers
  frs_break_find(conn, table,
    attribute = "gradient", threshold = threshold,
    to = to)

  # Falls barriers (append to same table)
  if (!is.null(falls)) {
    .frs_validate_identifier(falls, "falls table")
    frs_break_find(conn, table,
      points_table = falls,
      where = falls_where, aoi = aoi,
      to = to, append = TRUE)
  }

  invisible(conn)
}


#' Classify Habitat for One Species
#'
#' Copy a base stream network, apply pre-computed access barriers, then
#' classify spawning, rearing, and lake rearing habitat for a single species.
#' Each species gets its own output table because break points modify segment
#' geometry.
#'
#' Uses parameters from [frs_params()] (habitat thresholds from bcfishpass) and
#' `parameters_fresh.csv` (access gradients, spawn gradient min). The output
#' table mirrors bcfishpass naming: `working.streams_co`, `working.streams_bt`,
#' etc.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param species_code Character. Uppercase species code (e.g. `"CO"`, `"BT"`).
#' @param base_tbl Character. Schema-qualified base table with the enriched
#'   stream network (from [frs_extract()] + [frs_col_join()]).
#' @param breaks Character. Schema-qualified access breaks table from
#'   [frs_habitat_access()].
#' @param breaks_habitat Character or `NULL`. Schema-qualified habitat gradient
#'   breaks table. When provided, skips the per-species gradient scan and
#'   applies this pre-computed table instead. Species that share the same
#'   `spawn_gradient_max` can reuse the same habitat breaks. Default `NULL`
#'   computes breaks on the fly.
#' @param params_sp Named list. Species parameters from [frs_params()]
#'   (e.g. `frs_params()$CO`).
#' @param fresh_sp Data frame row. Species row from `parameters_fresh.csv`
#'   with `access_gradient_max`, `spawn_gradient_min`.
#' @param to Character or `NULL`. Output table name. Default `NULL` uses
#'   `working.streams_{sp}` (e.g. `working.streams_co`).
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
#' params <- frs_params(csv = system.file("extdata",
#'   "parameters_habitat_thresholds.csv", package = "fresh"))
#' fresh <- read.csv(system.file("extdata",
#'   "parameters_fresh.csv", package = "fresh"))
#'
#' # With pre-computed habitat breaks (fast — no gradient scan)
#' frs_habitat_species(conn, "CO", "working.streams",
#'   breaks = "working.breaks_access_015",
#'   breaks_habitat = "working.breaks_habitat_00549",
#'   params_sp = params$CO,
#'   fresh_sp = fresh[fresh$species_code == "CO", ])
#'
#' # Without pre-computed habitat breaks (computes on the fly)
#' frs_habitat_species(conn, "CO", "working.streams",
#'   breaks = "working.breaks_access_015",
#'   params_sp = params$CO,
#'   fresh_sp = fresh[fresh$species_code == "CO", ])
#'
#' DBI::dbDisconnect(conn)
#' }
frs_habitat_species <- function(conn, species_code, base_tbl, breaks,
                                breaks_habitat = NULL,
                                params_sp, fresh_sp, to = NULL) {
  stopifnot(is.character(species_code), length(species_code) == 1)
  .frs_validate_identifier(base_tbl, "base table")
  .frs_validate_identifier(breaks, "breaks table")
  if (!is.null(breaks_habitat)) {
    .frs_validate_identifier(breaks_habitat, "habitat breaks table")
  }

  sp <- tolower(species_code)
  if (is.null(to)) to <- paste0("working.streams_", sp)
  .frs_validate_identifier(to, "output table")

  # -- Copy base network -----------------------------------------------------
  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  .frs_db_execute(conn, sprintf("CREATE TABLE %s AS SELECT * FROM %s",
                                to, base_tbl))
  frs_col_generate(conn, to)

  # -- Apply access barriers --------------------------------------------------
  frs_break_apply(conn, to, breaks = breaks)
  frs_classify(conn, to, label = "accessible", breaks = breaks)

  # -- Habitat breaks ---------------------------------------------------------
  spawn_gradient_max <- params_sp$spawn_gradient_max
  spawn_gradient_min <- if (is.null(fresh_sp$spawn_gradient_min) ||
                           is.na(fresh_sp$spawn_gradient_min)) {
    0
  } else {
    fresh_sp$spawn_gradient_min
  }

  if (is.null(breaks_habitat)) {
    # Compute on the fly (slow path)
    breaks_hab_tmp <- paste0(to, "_breaks_habitat")
    frs_break(conn, to,
      attribute = "gradient", threshold = spawn_gradient_max,
      to = breaks_hab_tmp)
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", breaks_hab_tmp))
  } else {
    # Apply pre-computed habitat breaks (fast path)
    frs_break_apply(conn, to, breaks = breaks_habitat)
  }

  # -- Habitat classification -------------------------------------------------
  # Spawning
  frs_classify(conn, to, label = paste0(sp, "_spawning"),
    ranges = list(
      gradient = c(spawn_gradient_min, spawn_gradient_max),
      channel_width = params_sp$ranges$spawn$channel_width),
    where = "accessible IS TRUE")

  # Rearing (if species has rearing thresholds)
  if (!is.null(params_sp$ranges$rear)) {
    cols_rear <- intersect(c("gradient", "channel_width"),
                           names(params_sp$ranges$rear))
    frs_classify(conn, to, label = paste0(sp, "_rearing"),
      ranges = params_sp$ranges$rear[cols_rear],
      where = "accessible IS TRUE")

    # Lake rearing
    frs_classify(conn, to, label = paste0(sp, "_lake_rearing"),
      ranges = list(channel_width = params_sp$ranges$rear$channel_width),
      where = paste0("accessible IS TRUE AND waterbody_key IN ",
                     "(SELECT waterbody_key FROM whse_basemapping.fwa_lakes_poly)"))
  }

  # -- Categorize --------------------------------------------------------------
  cols_cat <- paste0(sp, "_spawning")
  vals_cat <- paste0(toupper(sp), "_SPAWNING")

  if (!is.null(params_sp$ranges$rear)) {
    cols_cat <- c(cols_cat, paste0(sp, "_rearing"), paste0(sp, "_lake_rearing"))
    vals_cat <- c(vals_cat, paste0(toupper(sp), "_REARING"),
                  paste0(toupper(sp), "_LAKE_REARING"))
  }
  cols_cat <- c(cols_cat, "accessible")
  vals_cat <- c(vals_cat, "ACCESSIBLE")

  frs_categorize(conn, to, label = "habitat_type",
    cols = cols_cat, values = vals_cat, default = "INACCESSIBLE")

  invisible(conn)
}


#' Format a threshold value as a table name label
#'
#' @param thr Numeric. Threshold value (e.g. 0.15, 0.0549).
#' @return Character. Digits only, no dot (e.g. "015", "00549").
#' @noRd
.frs_thr_label <- function(thr) {
  gsub("\\.", "", format(thr, scientific = FALSE))
}
