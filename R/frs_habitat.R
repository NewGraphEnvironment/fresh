#' Run Habitat Pipeline
#'
#' Orchestrate the full habitat pipeline: generate gradient access
#' barriers, segment the network via [frs_network_segment()], classify
#' habitat via [frs_habitat_classify()], and persist results.
#'
#' Supports three modes:
#' - **WSG mode** (`wsg`): one or more watershed group codes. Species
#'   auto-detected. Parallelizes across WSGs.
#' - **Custom AOI** (`aoi` + `species`): any spatial extent with explicit
#'   species. For sub-basins, territories, or cross-WSG study areas.
#' - **WSG + custom AOI** (`wsg` + `aoi`): WSG for species lookup and
#'   table naming, custom AOI for spatial extent.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param wsg Character or `NULL`. One or more watershed group codes.
#'   When provided, species are auto-detected via [frs_wsg_species()].
#' @param aoi AOI specification or `NULL`. Overrides the spatial extent.
#'   Accepts anything [frs_extract()] handles: `sf` polygon, character
#'   WSG code, WHERE clause string, or named list. When `NULL` with
#'   `wsg`, uses the WSG polygon.
#' @param species Character or `NULL`. Species codes to classify
#'   (e.g. `c("CO", "BT")`). When `NULL` with `wsg`, auto-detected.
#'   Required when `wsg` is `NULL`.
#' @param label Character or `NULL`. Short label for working table names.
#'   Auto-generated from `wsg` when available. Required when `wsg` is
#'   `NULL` and `aoi` is provided.
#' @param to_streams Character or `NULL`. Schema-qualified table for
#'   persistent stream segments. Accumulates across runs.
#' @param to_habitat Character or `NULL`. Schema-qualified table for
#'   habitat classifications. Long format: one row per segment x species.
#' @param break_sources List of additional break source specs (falls,
#'   crossings, etc.), or `NULL`. Gradient access barriers are generated
#'   automatically from species parameters.
#' @param workers Integer. Number of parallel workers. Default `1`.
#'   Values > 1 require the `mirai` package. Only used in WSG mode.
#' @param password Character. Database password for parallel workers.
#' @param cleanup Logical. Drop working tables when done. Default `TRUE`.
#' @param verbose Logical. Print progress. Default `TRUE`.
#'
#' @return A data frame with columns `label`, `n_segments`, `n_species`,
#'   `elapsed_s`.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # WSG mode — species auto-detected
#' frs_habitat(conn, "BULK",
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat",
#'   break_sources = list(
#'     list(table = "working.falls", where = "barrier_ind = TRUE",
#'          label = "blocked")))
#'
#' # Custom AOI — sub-basin via ltree filter
#' frs_habitat(conn,
#'   aoi = "wscode_ltree <@ '100.190442.999098'::ltree",
#'   species = c("BT", "CO"),
#'   label = "richfield",
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat")
#'
#' # WSG + custom AOI — WSG for species, polygon for extent
#' frs_habitat(conn, "ADMS",
#'   aoi = my_study_area_polygon,
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat")
#'
#' # Multiple WSGs, parallel
#' frs_habitat(conn, c("BULK", "MORR", "ZYMO"),
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat",
#'   workers = 4, password = "postgres",
#'   break_sources = list(
#'     list(table = "working.falls", label = "blocked")))
#'
#' DBI::dbDisconnect(conn)
#' }
frs_habitat <- function(conn, wsg = NULL,
                        aoi = NULL, species = NULL, label = NULL,
                        to_streams = NULL, to_habitat = NULL,
                        break_sources = NULL,
                        gate = TRUE,
                        workers = 1L,
                        password = "",
                        cleanup = TRUE, verbose = TRUE) {

  t_total <- proc.time()

  # -- Load parameters --------------------------------------------------------
  params_all <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"))
  params_fresh <- utils::read.csv(system.file("extdata",
    "parameters_fresh.csv", package = "fresh"), stringsAsFactors = FALSE)

  # -- Build job specs ---------------------------------------------------------
  if (!is.null(wsg)) {
    stopifnot(is.character(wsg), length(wsg) > 0)

    wsg_specs <- lapply(wsg, function(w) {
      # Species: explicit or auto-detect from WSG
      sp <- if (!is.null(species)) {
        species
      } else {
        sp_df <- frs_wsg_species(w)
        sp_df <- sp_df[!is.na(sp_df$view), ]
        sp_df <- sp_df[sp_df$species_code %in% names(params_all) &
                       sp_df$species_code %in% params_fresh$species_code, ]
        sp_df <- sp_df[!duplicated(sp_df$species_code), ]
        sp_df$species_code
      }
      if (length(sp) == 0) return(NULL)

      # AOI: explicit or WSG code
      job_aoi <- if (!is.null(aoi)) aoi else w
      job_label <- tolower(w)

      list(label = job_label, aoi = job_aoi, species = sp, wsg = w)
    })
    wsg_specs <- Filter(Negate(is.null), wsg_specs)
  } else {
    # Custom AOI mode — no WSG
    if (is.null(species)) {
      stop("species is required when wsg is not provided", call. = FALSE)
    }
    if (is.null(aoi)) {
      stop("aoi is required when wsg is not provided", call. = FALSE)
    }
    if (is.null(label)) {
      stop("label is required when wsg is not provided", call. = FALSE)
    }

    # Validate species against params
    valid_sp <- intersect(species, names(params_all))
    valid_sp <- intersect(valid_sp, params_fresh$species_code)
    if (length(valid_sp) == 0) {
      stop("No valid species codes found in parameters", call. = FALSE)
    }
    missing <- setdiff(species, valid_sp)
    if (length(missing) > 0) {
      warning("Species not in parameters (skipped): ",
              paste(missing, collapse = ", "), call. = FALSE)
    }

    wsg_specs <- list(list(label = label, aoi = aoi,
                           species = valid_sp, wsg = NULL))
  }

  if (length(wsg_specs) == 0) {
    stop("No modelable species found", call. = FALSE)
  }

  if (verbose) {
    for (spec in wsg_specs) {
      cat(spec$wsg, ": ", paste(spec$species, collapse = ", "), "\n", sep = "")
    }
  }

  # -- Parallel setup ---------------------------------------------------------
  workers <- as.integer(workers)
  use_parallel <- workers > 1L
  if (use_parallel && !requireNamespace("mirai", quietly = TRUE)) {
    stop("mirai package required for parallel execution (workers > 1)",
         call. = FALSE)
  }
  conn_params <- if (use_parallel) .frs_conn_params(conn, password) else NULL

  # -- Per-job worker function -------------------------------------------------
  .run_job <- function(spec, conn_params, break_sources, params_all,
                       params_fresh, to_streams, to_habitat, verbose) {
    # Connect (parallel) or reuse (sequential)
    if (!is.null(conn_params)) {
      library(fresh)
      w_conn <- do.call(DBI::dbConnect,
        c(list(drv = RPostgres::Postgres()), conn_params))
      on.exit(DBI::dbDisconnect(w_conn))
    } else {
      w_conn <- conn
    }

    job_label <- spec$label
    job_aoi <- spec$aoi
    species <- spec$species
    wsg_code <- spec$wsg  # NULL for custom AOI mode
    t0 <- proc.time()

    # 1. Determine unique access thresholds for this job's species
    access_thresholds <- sort(unique(
      params_fresh$access_gradient_max[
        params_fresh$species_code %in% species]))

    # 2. Generate gradient barriers at each threshold
    streams_tbl <- paste0("working.streams_", job_label)

    # Temp extract for barrier detection — use AOI
    tmp_tbl <- paste0(streams_tbl, "_tmp")
    if (is.character(job_aoi) && length(job_aoi) == 1 &&
        grepl("^[A-Z]{4}$", job_aoi)) {
      frs_extract(w_conn,
        from = "whse_basemapping.fwa_stream_networks_sp",
        to = tmp_tbl,
        where = paste0("watershed_group_code = ",
                       .frs_quote_string(job_aoi)),
        overwrite = TRUE)
    } else if (is.character(job_aoi) && length(job_aoi) == 1) {
      # WHERE clause string (e.g. ltree filter)
      frs_extract(w_conn,
        from = "whse_basemapping.fwa_stream_networks_sp",
        to = tmp_tbl,
        where = job_aoi,
        overwrite = TRUE)
    } else {
      frs_extract(w_conn,
        from = "whse_basemapping.fwa_stream_networks_sp",
        to = tmp_tbl,
        aoi = job_aoi,
        overwrite = TRUE)
    }

    all_sources <- if (!is.null(break_sources)) break_sources else list()
    barrier_tables <- character(0)

    for (thr in access_thresholds) {
      thr_tbl <- sprintf("working.barriers_%s_%d",
                         job_label, as.integer(thr * 100))
      frs_break_find(w_conn, tmp_tbl,
        attribute = "gradient", threshold = thr,
        to = thr_tbl)
      all_sources <- c(all_sources, list(list(
        table = thr_tbl,
        label = sprintf("gradient_%d", as.integer(thr * 100)))))
      barrier_tables <- c(barrier_tables, thr_tbl)
    }

    .frs_db_execute(w_conn, sprintf("DROP TABLE IF EXISTS %s", tmp_tbl))

    # 3. Segment network
    frs_network_segment(w_conn, aoi = job_aoi,
      to = streams_tbl,
      break_sources = all_sources,
      verbose = verbose && is.null(conn_params))

    n_seg <- DBI::dbGetQuery(w_conn,
      sprintf("SELECT count(*)::int AS n FROM %s", streams_tbl))$n

    # 4. Classify habitat
    habitat_tbl <- if (!is.null(to_habitat)) {
      to_habitat
    } else {
      paste0(streams_tbl, "_habitat")
    }

    frs_habitat_classify(w_conn,
      table = streams_tbl,
      to = habitat_tbl,
      species = species,
      params = params_all,
      params_fresh = params_fresh,
      gate = gate,
      verbose = verbose && is.null(conn_params))

    # 5. Persist streams (if to_streams provided)
    if (!is.null(to_streams)) {
      .frs_db_execute(w_conn, sprintf(
        "CREATE TABLE IF NOT EXISTS %s AS SELECT * FROM %s LIMIT 0",
        to_streams, streams_tbl))
      # Partition delete: by WSG if available, otherwise by id_segment
      if (!is.null(wsg_code)) {
        .frs_db_execute(w_conn, sprintf(
          "DELETE FROM %s WHERE watershed_group_code = %s",
          to_streams, .frs_quote_string(wsg_code)))
      } else {
        .frs_db_execute(w_conn, sprintf(
          "DELETE FROM %s WHERE id_segment IN (SELECT id_segment FROM %s)",
          to_streams, streams_tbl))
      }
      .frs_db_execute(w_conn, sprintf(
        "INSERT INTO %s SELECT * FROM %s",
        to_streams, streams_tbl))
    }

    # 6. Cleanup working tables
    .frs_db_execute(w_conn, sprintf(
      "DROP TABLE IF EXISTS %s", paste0(streams_tbl, "_breaks")))
    for (tbl in barrier_tables) {
      .frs_db_execute(w_conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
    }
    if (!is.null(to_streams)) {
      .frs_db_execute(w_conn, sprintf("DROP TABLE IF EXISTS %s", streams_tbl))
    }

    elapsed <- (proc.time() - t0)["elapsed"]
    data.frame(label = job_label, n_segments = n_seg,
               n_species = length(species), elapsed_s = elapsed,
               stringsAsFactors = FALSE)
  }

  # -- Run jobs ---------------------------------------------------------------
  if (use_parallel) {
    if (verbose) cat("\nRunning ", length(wsg_specs), " job(s) on ",
                     workers, " workers...\n", sep = "")
    mirai::daemons(workers)
    on.exit(mirai::daemons(0), add = TRUE)

    result_list <- mirai::mirai_map(wsg_specs, function(spec) {
      library(fresh)
      w_conn <- do.call(DBI::dbConnect,
        c(list(drv = RPostgres::Postgres()), conn_params))
      on.exit(DBI::dbDisconnect(w_conn))

      job_label <- spec$label
      job_aoi <- spec$aoi
      species <- spec$species
      wsg_code <- spec$wsg
      t0 <- proc.time()

      access_thresholds <- sort(unique(
        params_fresh$access_gradient_max[
          params_fresh$species_code %in% species]))

      streams_tbl <- paste0("working.streams_", job_label)
      tmp_tbl <- paste0(streams_tbl, "_tmp")

      # Extract for barrier detection
      if (is.character(job_aoi) && length(job_aoi) == 1 &&
          grepl("^[A-Z]{4}$", job_aoi)) {
        frs_extract(w_conn,
          from = "whse_basemapping.fwa_stream_networks_sp",
          to = tmp_tbl,
          where = paste0("watershed_group_code = '", job_aoi, "'"),
          overwrite = TRUE)
      } else if (is.character(job_aoi) && length(job_aoi) == 1) {
        frs_extract(w_conn,
          from = "whse_basemapping.fwa_stream_networks_sp",
          to = tmp_tbl, where = job_aoi, overwrite = TRUE)
      } else {
        frs_extract(w_conn,
          from = "whse_basemapping.fwa_stream_networks_sp",
          to = tmp_tbl, aoi = job_aoi, overwrite = TRUE)
      }

      all_sources <- if (!is.null(break_sources)) break_sources else list()
      barrier_tables <- character(0)
      for (thr in access_thresholds) {
        thr_tbl <- sprintf("working.barriers_%s_%d",
                           job_label, as.integer(thr * 100))
        frs_break_find(w_conn, tmp_tbl,
          attribute = "gradient", threshold = thr, to = thr_tbl)
        all_sources <- c(all_sources, list(list(
          table = thr_tbl,
          label = sprintf("gradient_%d", as.integer(thr * 100)))))
        barrier_tables <- c(barrier_tables, thr_tbl)
      }

      DBI::dbExecute(w_conn, sprintf("DROP TABLE IF EXISTS %s", tmp_tbl))

      frs_network_segment(w_conn, aoi = job_aoi,
        to = streams_tbl, break_sources = all_sources, verbose = FALSE)

      n_seg <- DBI::dbGetQuery(w_conn,
        sprintf("SELECT count(*)::int AS n FROM %s", streams_tbl))$n

      habitat_tbl <- if (!is.null(to_habitat)) to_habitat else
        paste0(streams_tbl, "_habitat")

      frs_habitat_classify(w_conn, table = streams_tbl, to = habitat_tbl,
        species = species, params = params_all, params_fresh = params_fresh,
        gate = gate, verbose = FALSE)

      if (!is.null(to_streams)) {
        DBI::dbExecute(w_conn, sprintf(
          "CREATE TABLE IF NOT EXISTS %s AS SELECT * FROM %s LIMIT 0",
          to_streams, streams_tbl))
        if (!is.null(wsg_code)) {
          DBI::dbExecute(w_conn, sprintf(
            "DELETE FROM %s WHERE watershed_group_code = '%s'",
            to_streams, wsg_code))
        } else {
          DBI::dbExecute(w_conn, sprintf(
            "DELETE FROM %s WHERE id_segment IN (SELECT id_segment FROM %s)",
            to_streams, streams_tbl))
        }
        DBI::dbExecute(w_conn, sprintf(
          "INSERT INTO %s SELECT * FROM %s", to_streams, streams_tbl))
      }

      DBI::dbExecute(w_conn, sprintf(
        "DROP TABLE IF EXISTS %s", paste0(streams_tbl, "_breaks")))
      for (tbl in barrier_tables) {
        DBI::dbExecute(w_conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
      }
      if (!is.null(to_streams)) {
        DBI::dbExecute(w_conn, sprintf("DROP TABLE IF EXISTS %s", streams_tbl))
      }

      elapsed <- (proc.time() - t0)["elapsed"]
      data.frame(label = job_label, n_segments = n_seg,
                 n_species = length(species), elapsed_s = elapsed,
                 stringsAsFactors = FALSE)
    },
      conn_params = conn_params, break_sources = break_sources,
      params_all = params_all, params_fresh = params_fresh,
      to_streams = to_streams, to_habitat = to_habitat,
      gate = gate, verbose = verbose)[]

    errs <- vapply(result_list, inherits, logical(1), "miraiError")
    if (any(errs)) {
      msgs <- vapply(which(errs), function(i) {
        paste0(wsg_specs[[i]]$label, ": ", conditionMessage(result_list[[i]]))
      }, character(1))
      stop("Pipeline failed:\n  ", paste(msgs, collapse = "\n  "),
           call. = FALSE)
    }
  } else {
    result_list <- lapply(wsg_specs, function(spec) {
      res <- .run_job(spec, conn_params = NULL,
        break_sources = break_sources,
        params_all = params_all, params_fresh = params_fresh,
        to_streams = to_streams, to_habitat = to_habitat,
        verbose = verbose)
      if (verbose) {
        cat("  ", res$label, ": ", res$n_segments, " segs, ",
            res$n_species, " spp, ", round(res$elapsed_s, 1), "s\n", sep = "")
      }
      res
    })
  }

  results <- do.call(rbind, result_list)
  rownames(results) <- NULL

  if (verbose && use_parallel) {
    for (i in seq_len(nrow(results))) {
      cat("  ", results$label[i], ": ", results$n_segments[i], " segs, ",
          results$n_species[i], " spp, ", round(results$elapsed_s[i], 1),
          "s\n", sep = "")
    }
  }

  total_s <- (proc.time() - t_total)["elapsed"]
  if (verbose) {
    cat("Total: ", round(total_s, 1), "s\n", sep = "")
  }

  invisible(results)
}


#' Prepare a Partition for Habitat Classification
#'
#' Extract a stream network subset, enrich with channel width, and
#' pre-compute access and habitat gradient breaks. Returns a list of
#' species classification jobs ready for [frs_habitat_species()].
#'
#' A partition is any spatial subset of a stream network — a watershed
#' group, a custom polygon, a study area. The function does not assume
#' the partition is a BC watershed group; that fish-specific lookup
#' happens in [frs_habitat()] before calling this function.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param aoi AOI specification passed to [frs_extract()]. Character
#'   watershed group code, `sf` polygon, named list, or `NULL`.
#' @param label Character. Short label for table naming
#'   (e.g. `"bulk"`, `"study_area"`). Used in table names like
#'   `working.streams_{label}`, `working.breaks_access_{label}_{thr}`.
#' @param species Data frame with columns `species_code`,
#'   `access_gradient`, and `spawn_gradient_max`. One row per species.
#' @param params_all Named list from [frs_params()].
#' @param params_fresh Data frame from `parameters_fresh.csv`.
#' @param source Character. Source table for the stream network. Default
#'   `"whse_basemapping.fwa_stream_networks_sp"`.
#' @param break_sources List of break source specs passed to
#'   [frs_habitat_access()], or `NULL` for gradient-only. See
#'   [frs_habitat_access()] for spec format.
#' @param verbose Logical. Print progress. Default `TRUE`.
#'
#' @return A list with:
#'   \describe{
#'     \item{jobs}{List of job specs for [frs_habitat_species()]}
#'     \item{cleanup_tables}{Character vector of intermediate table names}
#'   }
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#' params_all <- frs_params(csv = system.file("extdata",
#'   "parameters_habitat_thresholds.csv", package = "fresh"))
#' params_fresh <- read.csv(system.file("extdata",
#'   "parameters_fresh.csv", package = "fresh"))
#'
#' # Prepare BULK partition
#' species <- data.frame(
#'   species_code = c("CO", "BT"),
#'   access_gradient = c(0.15, 0.25),
#'   spawn_gradient_max = c(0.0549, 0.0549))
#'
#' prep <- frs_habitat_partition(conn, aoi = "BULK", label = "bulk",
#'   species = species, params_all = params_all,
#'   params_fresh = params_fresh)
#'
#' # Run one species from the prepared jobs
#' job <- prep$jobs[[1]]
#' frs_habitat_species(conn, job$species_code, job$base_tbl,
#'   breaks = job$acc_tbl, breaks_habitat = job$hab_tbl,
#'   params_sp = job$params_sp, fresh_sp = job$fresh_sp,
#'   to = job$to)
#'
#' DBI::dbDisconnect(conn)
#' }
frs_habitat_partition <- function(conn, aoi, label, species,
                                  params_all, params_fresh,
                                  source = "whse_basemapping.fwa_stream_networks_sp",
                                  break_sources = NULL,
                                  verbose = TRUE) {
  stopifnot(is.character(label), length(label) == 1)
  stopifnot(is.data.frame(species), nrow(species) > 0)
  stopifnot(all(c("species_code", "access_gradient", "spawn_gradient_max")
                %in% names(species)))

  cleanup_tables <- character(0)

  # -- Extract base network --------------------------------------------------
  base_tbl <- paste0("working.streams_", label)
  cleanup_tables <- c(cleanup_tables, base_tbl)

  t0 <- proc.time()

  # Build where clause: character aoi uses column filter, others use spatial
  if (is.character(aoi) && length(aoi) == 1 &&
      grepl("^[A-Z]{4}$", aoi)) {
    # Looks like a WSG code — use fast column filter
    frs_extract(conn, from = source, to = base_tbl,
      where = paste0("watershed_group_code = ", .frs_quote_string(aoi)),
      overwrite = TRUE)
  } else {
    frs_extract(conn, from = source, to = base_tbl,
      aoi = aoi, overwrite = TRUE)
  }

  frs_col_join(conn, base_tbl,
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")

  if (verbose) {
    n <- DBI::dbGetQuery(conn,
      sprintf("SELECT count(*)::int AS n FROM %s", base_tbl))$n
    cat("  Base: ", n, " segments (",
        round((proc.time() - t0)["elapsed"], 1), "s)\n", sep = "")
  }

  # -- Access barriers (grouped by threshold) --------------------------------
  for (thr in sort(unique(species$access_gradient))) {
    thr_label <- .frs_thr_label(thr)
    breaks_tbl <- paste0("working.breaks_access_", label, "_", thr_label)
    cleanup_tables <- c(cleanup_tables, breaks_tbl)

    t0 <- proc.time()
    frs_habitat_access(conn, base_tbl, threshold = thr,
      to = breaks_tbl, break_sources = break_sources)

    if (verbose) {
      spp <- species$species_code[species$access_gradient == thr]
      cat("  Access ", thr * 100, "%: ",
          round((proc.time() - t0)["elapsed"], 1),
          "s (", paste(spp, collapse = ", "), ")\n", sep = "")
    }
  }

  # -- Habitat breaks (grouped by spawn_gradient_max) ------------------------
  for (thr in sort(unique(species$spawn_gradient_max))) {
    thr_label <- .frs_thr_label(thr)
    breaks_tbl <- paste0("working.breaks_habitat_", label, "_", thr_label)
    cleanup_tables <- c(cleanup_tables, breaks_tbl)

    t0 <- proc.time()
    frs_break_find(conn, base_tbl,
      attribute = "gradient", threshold = thr,
      to = breaks_tbl)

    if (verbose) {
      spp <- species$species_code[species$spawn_gradient_max == thr]
      cat("  Habitat ", thr * 100, "%: ",
          round((proc.time() - t0)["elapsed"], 1),
          "s (", paste(spp, collapse = ", "), ")\n", sep = "")
    }
  }

  # -- Build jobs ------------------------------------------------------------
  jobs <- lapply(seq_len(nrow(species)), function(i) {
    sc <- species$species_code[i]
    list(
      partition = label,
      species_code = sc,
      base_tbl = base_tbl,
      access_threshold = species$access_gradient[i],
      habitat_threshold = species$spawn_gradient_max[i],
      acc_tbl = paste0("working.breaks_access_", label, "_",
                       .frs_thr_label(species$access_gradient[i])),
      hab_tbl = paste0("working.breaks_habitat_", label, "_",
                       .frs_thr_label(species$spawn_gradient_max[i])),
      to = paste0("working.streams_", label, "_", tolower(sc)),
      params_sp = params_all[[sc]],
      fresh_sp = params_fresh[params_fresh$species_code == sc, ]
    )
  })

  list(jobs = jobs, cleanup_tables = cleanup_tables)
}


#' Compute Access Breaks at a Gradient Threshold
#'
#' Find gradient-based access breaks and append break points from external
#' sources (e.g. falls, crossings, dams). This is the expensive step in the
#' habitat pipeline — `fwa_slopealonginterval()` runs on every blue line key.
#' Species that share the same `access_gradient_max` can reuse the same
#' breaks table, avoiding redundant computation.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Working schema table with the stream network
#'   (from [frs_extract()]).
#' @param threshold Numeric. Access gradient threshold (e.g. `0.15` for 15%).
#' @param to Character. Destination table for break points. Default
#'   `"working.breaks_access"`.
#' @param break_sources List of break source specs, or `NULL` to skip
#'   external sources (gradient-only). Each spec is a list with:
#'   \describe{
#'     \item{table}{Schema-qualified table name with `blue_line_key` and
#'       `downstream_route_measure` columns.}
#'     \item{where}{SQL predicate to filter rows (optional).}
#'     \item{label}{Static label string for all rows (optional).}
#'     \item{label_col}{Column name to read labels from (optional).}
#'     \item{label_map}{Named character vector mapping `label_col` values
#'       to output labels (optional).}
#'   }
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
#' # Gradient-only (no external break sources)
#' frs_habitat_access(conn, "working.streams_bulk", threshold = 0.15,
#'   to = "working.breaks_access_bulk_015")
#'
#' # With falls and PSCIS crossings
#' frs_habitat_access(conn, "working.streams_bulk", threshold = 0.15,
#'   to = "working.breaks_access_bulk_015",
#'   break_sources = list(
#'     list(table = "working.falls", where = "barrier_ind = TRUE",
#'          label = "blocked"),
#'     list(table = "working.pscis",
#'          label_col = "barrier_status",
#'          label_map = c("BARRIER" = "blocked",
#'                        "POTENTIAL" = "potential"))
#'   ))
#'
#' DBI::dbDisconnect(conn)
#' }
frs_habitat_access <- function(conn, table, threshold,
                               to = "working.breaks_access",
                               break_sources = NULL) {
  .frs_validate_identifier(table, "source table")
  .frs_validate_identifier(to, "destination table")
  stopifnot(is.numeric(threshold), length(threshold) == 1)

  frs_break_find(conn, table,
    attribute = "gradient", threshold = threshold,
    to = to)

  if (!is.null(break_sources)) {
    for (src in break_sources) {
      .frs_validate_identifier(src$table, "break source table")
      frs_break_find(conn, table,
        points_table = src$table,
        where = src$where,
        label = src$label,
        label_col = src$label_col,
        label_map = src$label_map,
        col_blk = if (is.null(src$col_blk)) "blue_line_key" else src$col_blk,
        col_measure = if (is.null(src$col_measure)) "downstream_route_measure" else src$col_measure,
        to = to, overwrite = FALSE, append = TRUE)
    }
  }

  # Enrich breaks with ltree codes for fast cross-BLK classification
  .frs_enrich_breaks(conn, to)

  .frs_index_working(conn, to)

  invisible(conn)
}


#' Enrich breaks table with ltree codes from FWA base network
#'
#' Adds `wscode_ltree` and `localcode_ltree` columns by joining each break
#' point to the FWA stream segment it falls within. These columns enable
#' fast cross-BLK classification via ltree comparison instead of joining
#' back to the 4.9M row `fwa_stream_networks_sp` table at classify time.
#'
#' @param conn DBI connection.
#' @param breaks Schema-qualified breaks table name.
#' @noRd
.frs_enrich_breaks <- function(conn, breaks) {
  .frs_db_execute(conn, sprintf(
    "ALTER TABLE %s ADD COLUMN IF NOT EXISTS wscode_ltree ltree", breaks))
  .frs_db_execute(conn, sprintf(
    "ALTER TABLE %s ADD COLUMN IF NOT EXISTS localcode_ltree ltree", breaks))

  .frs_db_execute(conn, sprintf(
    "UPDATE %s b SET
       wscode_ltree = f.wscode_ltree,
       localcode_ltree = f.localcode_ltree
     FROM whse_basemapping.fwa_stream_networks_sp f
     WHERE b.blue_line_key = f.blue_line_key
       AND b.downstream_route_measure >= f.downstream_route_measure
       AND b.downstream_route_measure < f.upstream_route_measure",
    breaks))
}


#' Classify Habitat for One Species
#'
#' Copy a base stream network, apply pre-computed access barriers, then
#' classify spawning, rearing, and lake rearing habitat for a single species.
#' Each species gets its own output table because break points modify segment
#' geometry.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param species_code Character. Uppercase species code (e.g. `"CO"`, `"BT"`).
#' @param base_tbl Character. Schema-qualified base table with the enriched
#'   stream network (from [frs_extract()] + [frs_col_join()]).
#' @param breaks Character. Schema-qualified access breaks table from
#'   [frs_habitat_access()].
#' @param breaks_habitat Character or `NULL`. Schema-qualified habitat gradient
#'   breaks table. When provided, skips the per-species gradient scan and
#'   applies this pre-computed table instead. Default `NULL` computes on the
#'   fly.
#' @param params_sp Named list. Species parameters from [frs_params()]
#'   (e.g. `frs_params()$CO`).
#' @param fresh_sp Data frame row. Species row from `parameters_fresh.csv`
#'   with `access_gradient_max`, `spawn_gradient_min`.
#' @param to Character or `NULL`. Output table name. Default `NULL` uses
#'   `working.streams_{sp}`.
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
#' frs_habitat_species(conn, "CO", "working.streams_bulk",
#'   breaks = "working.breaks_access_bulk_015",
#'   breaks_habitat = "working.breaks_habitat_bulk_00549",
#'   params_sp = params$CO,
#'   fresh_sp = fresh[fresh$species_code == "CO", ],
#'   to = "working.streams_bulk_co")
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
    breaks_hab_tmp <- paste0(to, "_breaks_habitat")
    frs_break(conn, to,
      attribute = "gradient", threshold = spawn_gradient_max,
      to = breaks_hab_tmp)
    .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", breaks_hab_tmp))
  } else {
    frs_break_apply(conn, to, breaks = breaks_habitat)
  }

  # -- Habitat classification -------------------------------------------------
  frs_classify(conn, to, label = paste0(sp, "_spawning"),
    ranges = list(
      gradient = c(spawn_gradient_min, spawn_gradient_max),
      channel_width = params_sp$ranges$spawn$channel_width),
    where = "accessible IS TRUE")

  if (!is.null(params_sp$ranges$rear)) {
    cols_rear <- intersect(c("gradient", "channel_width"),
                           names(params_sp$ranges$rear))
    frs_classify(conn, to, label = paste0(sp, "_rearing"),
      ranges = params_sp$ranges$rear[cols_rear],
      where = "accessible IS TRUE")

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
