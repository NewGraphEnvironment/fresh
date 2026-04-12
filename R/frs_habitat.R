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
#' @param breaks_gradient Numeric vector or `NULL`. Extra gradient
#'   thresholds at which to break the network for sub-segment resolution
#'   (in addition to species access thresholds, which are always
#'   generated). Three modes:
#'   \itemize{
#'     \item `NULL` (default) — auto-derive from `spawn_gradient_max`
#'       and `rear_gradient_max` in `params`. Captures every biologically
#'       meaningful threshold for the species being classified.
#'     \item Numeric vector — explicit list (e.g. `c(0.06, 0.12)`).
#'       Replaces auto-derivation.
#'     \item `numeric(0)` — disable extras. Only access thresholds are
#'       generated (the fresh 0.9.0 behavior).
#'   }
#'   Auto-derived breaks give cluster analysis ([frs_cluster()]) the
#'   gradient resolution to detect within-segment steep sections that
#'   would otherwise be hidden by averaging.
#' @param gradient_recompute Logical. If `TRUE` (default), recompute
#'   gradient from DEM vertices after splitting segments. If `FALSE`,
#'   child segments inherit the parent gradient. See
#'   [frs_network_segment()] for details.
#' @param to_barriers Character or `NULL`. Schema-qualified table for
#'   persisting gradient barriers. Includes `blue_line_key`,
#'   `downstream_route_measure`, `gradient_class`, `label`,
#'   `wscode_ltree`, `localcode_ltree`. Useful for link's
#'   `lnk_barrier_overrides()`. Default `NULL` (barriers dropped after
#'   segmentation).
#' @param barrier_overrides Character or `NULL`. Schema-qualified table
#'   of barrier overrides prepared by link via
#'   `lnk_barrier_overrides()`. Must have columns `blue_line_key`,
#'   `downstream_route_measure`, `species_code`. When provided,
#'   matched barriers are excluded from per-species access gating.
#'   Default `NULL` (no overrides).
#' @param rules Character path to a habitat rules YAML, `FALSE`, or
#'   `NULL`. Default `NULL` uses the bundled
#'   `inst/extdata/parameters_habitat_rules.yaml`. Pass a path string
#'   to load a custom rules file (e.g. one shipped by the `link`
#'   package). Pass `FALSE` to disable rules entirely and use only
#'   the CSV ranges path (the pre-0.12.0 behavior).
#'
#'   Only consulted when `params = NULL`. If you pass your own
#'   `params` from `frs_params()`, the rules are baked into that
#'   object and `rules` here is ignored.
#'
#'   See [frs_params()] for the rules format.
#' @param params Named list from [frs_params()], or `NULL` to use
#'   bundled `parameters_habitat_thresholds.csv` and rules YAML.
#' @param params_fresh Data frame from `parameters_fresh.csv`, or
#'   `NULL` to use bundled default.
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
#' # Custom parameters — project-specific thresholds override bundled
#' # defaults. Use when species have different gradient/channel width
#' # ranges for your study area, or when adding species not in the
#' # default parameter set.
#' frs_habitat(conn, "BULK",
#'   params = frs_params(csv = "path/to/my_thresholds.csv"),
#'   params_fresh = read.csv("path/to/my_fresh_params.csv"),
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat")
#'
#' # --- Custom habitat rules YAML ---
#'
#' # Default: ships parameters_habitat_rules.yaml with NGE-derived
#' # multi-rule species (SK lake-only, CO wetland carve-out, all
#' # anadromous waterbody_type=R spawn). Behavior matches what
#' # consumers like the `link` package expect.
#'
#' # Custom rules from a project: pass a path string
#' frs_habitat(conn, "BULK",
#'   rules = "path/to/project_habitat_rules.yaml",
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat")
#'
#' # Disable rules entirely (pre-0.12.0 behavior — only CSV ranges)
#' frs_habitat(conn, "BULK",
#'   rules = FALSE,
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat")
#'
#' # --- Controlling gradient resolution with breaks_gradient ---
#'
#' # Default: auto-derive breaks from spawn_gradient_max +
#' # rear_gradient_max in params. For BULK with CO/BT/ST that's
#' # roughly: 0.0449, 0.0549, 0.0849, 0.1049 plus access (0.15, 0.20,
#' # 0.25). Every biologically meaningful threshold is captured.
#' # Recommended — gives frs_cluster() the resolution to find
#' # within-segment steep sections.
#' frs_habitat(conn, "BULK",
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat")
#'
#' # Custom override: explicit list. Use when you have project-specific
#' # gradient thresholds (e.g. local channel-type classification scheme)
#' # that aren't tied to a species threshold.
#' frs_habitat(conn, "BULK",
#'   breaks_gradient = c(0.03, 0.06, 0.10, 0.15),
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat")
#'
#' # Disable extras: only species access thresholds (15/20/25). Faster
#' # but coarser — fresh 0.9.0 behavior. Not recommended unless you
#' # specifically don't want sub-segment gradient resolution.
#' frs_habitat(conn, "BULK",
#'   breaks_gradient = numeric(0),
#'   to_streams = "fresh.streams",
#'   to_habitat = "fresh.streams_habitat")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_habitat <- function(conn, wsg = NULL,
                        aoi = NULL, species = NULL, label = NULL,
                        to_streams = NULL, to_habitat = NULL,
                        break_sources = NULL,
                        breaks_gradient = NULL,
                        gate = TRUE,
                        label_block = "blocked",
                        rules = NULL,
                        gradient_recompute = TRUE,
                        measure_precision = 0L,
                        barrier_overrides = NULL,
                        to_barriers = NULL,
                        params = NULL,
                        params_fresh = NULL,
                        workers = 1L,
                        password = "",
                        cleanup = TRUE, verbose = TRUE) {

  if (!is.null(breaks_gradient)) {
    .frs_validate_gradient_thresholds(breaks_gradient, "breaks_gradient")
  }

  t_total <- proc.time()

  # -- Load parameters --------------------------------------------------------
  if (is.null(params)) {
    rules_path <- if (is.null(rules)) {
      # frs_params default points at the bundled rules YAML
      system.file("extdata", "parameters_habitat_rules.yaml",
                  package = "fresh")
    } else if (identical(rules, FALSE)) {
      NULL
    } else {
      rules
    }
    params <- frs_params(
      csv = system.file("extdata", "parameters_habitat_thresholds.csv",
                        package = "fresh"),
      rules_yaml = rules_path)
  }
  if (is.null(params_fresh)) {
    params_fresh <- utils::read.csv(system.file("extdata",
      "parameters_fresh.csv", package = "fresh"), stringsAsFactors = FALSE)
  }

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
        sp_df <- sp_df[sp_df$species_code %in% names(params) &
                       sp_df$species_code %in% params_fresh$species_code, ]
        sp_df <- sp_df[!duplicated(sp_df$species_code), ]
        sp_df$species_code
      }
      if (length(sp) == 0) return(NULL)

      # AOI: when both wsg and aoi are provided, aoi is additive
      # (ANDed with the WSG filter for character WHERE clauses).
      # For sf/list AOIs, the spatial filter handles scoping.
      if (is.null(aoi)) {
        job_aoi <- w
      } else if (is.character(aoi) && length(aoi) == 1) {
        job_aoi <- sprintf(
          "watershed_group_code = %s AND (%s)",
          .frs_quote_string(w), aoi)
      } else {
        job_aoi <- aoi
      }
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
    valid_sp <- intersect(species, names(params))
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
  .run_job <- function(spec, conn_params, break_sources, breaks_gradient,
                       gradient_recompute, measure_precision, params,
                       params_fresh, to_streams, to_habitat, to_barriers,
                       verbose) {
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

    # 1. Determine gradient thresholds at which to break the network
    #
    # Access thresholds (always): from params_fresh, mandatory for
    # accessibility classification.
    access_thresholds <- params_fresh$access_gradient_max[
      params_fresh$species_code %in% species]
    access_thresholds <- access_thresholds[!is.na(access_thresholds)]

    # Extra thresholds (configurable): default = auto-derive from
    # spawn_gradient_max + rear_gradient_max in params; explicit numeric
    # vector overrides; numeric(0) disables extras.
    extra_thresholds <- if (is.null(breaks_gradient)) {
      vals <- unlist(lapply(params[species], function(p) {
        c(p$spawn_gradient_max, p$rear_gradient_max)
      }), use.names = FALSE)
      vals[!is.na(vals)]
    } else {
      as.numeric(breaks_gradient)
    }

    # Union, sort ascending, dedupe on actual numeric value.
    # Distinct biological thresholds (e.g. 0.05 and 0.0549) are
    # preserved — they each get their own break and a unique
    # `gradient_NNNN` label that captures threshold * 10000 padded
    # to 4 digits (resolution of 1 basis point).
    all_thresholds <- sort(unique(c(access_thresholds, extra_thresholds)))

    # Validate combined thresholds — catches collisions from
    # user-supplied custom params even when breaks_gradient is NULL.
    .frs_validate_gradient_thresholds(all_thresholds,
      "combined gradient thresholds")

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

    # Build gradient class breaks from all_thresholds
    # Each threshold becomes a class boundary. Names are the gradient_NNNN
    # labels used for accessibility parsing.
    grad_classes <- all_thresholds
    names(grad_classes) <- vapply(all_thresholds, function(t) {
      as.character(as.integer(round(t * 10000)))
    }, character(1))

    grad_tbl <- sprintf("working.barriers_%s_gradient", job_label)
    frs_break_find(w_conn, tmp_tbl,
      attribute = "gradient",
      classes = grad_classes,
      to = grad_tbl)

    # Add gradient_NNNN label column based on gradient_class
    .frs_db_execute(w_conn, sprintf(
      "ALTER TABLE %s ADD COLUMN IF NOT EXISTS label text", grad_tbl))
    .frs_db_execute(w_conn, sprintf(
      "UPDATE %s SET label = 'gradient_' || lpad(gradient_class::text, 4, '0')",
      grad_tbl))

    all_sources <- c(all_sources, list(list(
      table = grad_tbl,
      label_col = "label")))
    barrier_tables <- c(barrier_tables, grad_tbl)

    .frs_db_execute(w_conn, sprintf("DROP TABLE IF EXISTS %s", tmp_tbl))

    # 3. Segment network
    frs_network_segment(w_conn, aoi = job_aoi,
      to = streams_tbl,
      break_sources = all_sources,
      gradient_recompute = gradient_recompute,
      measure_precision = measure_precision,
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
      params = params,
      params_fresh = params_fresh,
      gate = gate, label_block = label_block,
      barrier_overrides = barrier_overrides,
      verbose = verbose && is.null(conn_params))

    # 4b. Post-classification connectivity checks (requires_connected)
    .frs_run_connectivity(w_conn, streams_tbl, habitat_tbl,
      species, params, params_fresh,
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

    # 5b. Persist gradient barriers (if to_barriers provided)
    if (!is.null(to_barriers)) {
      # Enrich with ltree before persisting
      .frs_enrich_breaks(w_conn, grad_tbl)
      .frs_db_execute(w_conn, sprintf(
        "CREATE TABLE IF NOT EXISTS %s AS SELECT * FROM %s LIMIT 0",
        to_barriers, grad_tbl))
      # Idempotent delete by BLK (works for both WSG and custom AOI)
      .frs_db_execute(w_conn, sprintf(
        "DELETE FROM %s WHERE blue_line_key IN (
           SELECT DISTINCT blue_line_key FROM %s)",
        to_barriers, grad_tbl))
      .frs_db_execute(w_conn, sprintf(
        "INSERT INTO %s SELECT * FROM %s",
        to_barriers, grad_tbl))
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

      # Access thresholds (always) + extra thresholds (configurable).
      # See sequential branch for full explanation.
      access_thresholds <- params_fresh$access_gradient_max[
        params_fresh$species_code %in% species]
      access_thresholds <- access_thresholds[!is.na(access_thresholds)]

      extra_thresholds <- if (is.null(breaks_gradient)) {
        vals <- unlist(lapply(params[species], function(p) {
          c(p$spawn_gradient_max, p$rear_gradient_max)
        }), use.names = FALSE)
        vals[!is.na(vals)]
      } else {
        as.numeric(breaks_gradient)
      }

      all_thresholds <- sort(unique(c(access_thresholds, extra_thresholds)))

      .frs_validate_gradient_thresholds(all_thresholds,
        "combined gradient thresholds")

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

      grad_classes <- all_thresholds
      names(grad_classes) <- vapply(all_thresholds, function(t) {
        as.character(as.integer(round(t * 10000)))
      }, character(1))

      grad_tbl <- sprintf("working.barriers_%s_gradient", job_label)
      frs_break_find(w_conn, tmp_tbl,
        attribute = "gradient",
        classes = grad_classes,
        to = grad_tbl)

      DBI::dbExecute(w_conn, sprintf(
        "ALTER TABLE %s ADD COLUMN IF NOT EXISTS label text", grad_tbl))
      DBI::dbExecute(w_conn, sprintf(
        "UPDATE %s SET label = 'gradient_' || lpad(gradient_class::text, 4, '0')",
        grad_tbl))

      all_sources <- c(all_sources, list(list(
        table = grad_tbl,
        label_col = "label")))
      barrier_tables <- c(barrier_tables, grad_tbl)

      DBI::dbExecute(w_conn, sprintf("DROP TABLE IF EXISTS %s", tmp_tbl))

      frs_network_segment(w_conn, aoi = job_aoi,
        to = streams_tbl, break_sources = all_sources,
        gradient_recompute = gradient_recompute,
        measure_precision = measure_precision, verbose = FALSE)

      n_seg <- DBI::dbGetQuery(w_conn,
        sprintf("SELECT count(*)::int AS n FROM %s", streams_tbl))$n

      habitat_tbl <- if (!is.null(to_habitat)) to_habitat else
        paste0(streams_tbl, "_habitat")

      frs_habitat_classify(w_conn, table = streams_tbl, to = habitat_tbl,
        species = species, params = params, params_fresh = params_fresh,
        gate = gate, label_block = label_block,
        barrier_overrides = barrier_overrides, verbose = FALSE)

      # Post-classification connectivity checks (requires_connected)
      .frs_run_connectivity(w_conn, streams_tbl, habitat_tbl,
        species, params, params_fresh, verbose = FALSE)

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

      # Persist gradient barriers
      if (!is.null(to_barriers)) {
        .frs_enrich_breaks(w_conn, grad_tbl)
        DBI::dbExecute(w_conn, sprintf(
          "CREATE TABLE IF NOT EXISTS %s AS SELECT * FROM %s LIMIT 0",
          to_barriers, grad_tbl))
        DBI::dbExecute(w_conn, sprintf(
          "DELETE FROM %s WHERE blue_line_key IN (
             SELECT DISTINCT blue_line_key FROM %s)",
          to_barriers, grad_tbl))
        DBI::dbExecute(w_conn, sprintf(
          "INSERT INTO %s SELECT * FROM %s",
          to_barriers, grad_tbl))
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
      breaks_gradient = breaks_gradient,
      gradient_recompute = gradient_recompute,
      measure_precision = measure_precision,
      barrier_overrides = barrier_overrides,
      params = params, params_fresh = params_fresh,
      to_streams = to_streams, to_habitat = to_habitat, to_barriers = to_barriers,
      gate = gate, label_block = label_block,
      verbose = verbose)[]

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
        breaks_gradient = breaks_gradient,
        gradient_recompute = gradient_recompute,
        measure_precision = measure_precision,
        params = params, params_fresh = params_fresh,
        to_streams = to_streams, to_habitat = to_habitat, to_barriers = to_barriers,
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
#' @param params Named list from [frs_params()].
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
#' params <- frs_params(csv = system.file("extdata",
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
#'   species = species, params = params,
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
                                  params, params_fresh,
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
      params_sp = params[[sc]],
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


#' Run post-classification connectivity checks
#'
#' Scans species params for rules with `requires_connected`. For each
#' match, calls [frs_cluster()] with the appropriate label swap and
#' cluster parameters from `params_fresh`.
#'
#' @noRd
.frs_run_connectivity <- function(conn, table, habitat,
                                  species, params, params_fresh,
                                  verbose = TRUE) {
  for (sp in species) {
    ps <- params[[sp]]
    if (is.null(ps) || is.null(ps[["rules"]])) next

    fp <- params_fresh[params_fresh$species_code == sp, ]
    if (nrow(fp) == 0) next

    # Check rearing connectivity (cluster_rearing)
    if (isTRUE(fp$cluster_rearing)) {
      dir <- if (is.na(fp$cluster_direction)) "upstream" else fp$cluster_direction
      bg <- if (is.na(fp$cluster_bridge_gradient)) 0.05 else fp$cluster_bridge_gradient
      bd <- if (is.na(fp$cluster_bridge_distance)) 10000 else fp$cluster_bridge_distance
      cm <- if (is.na(fp$cluster_confluence_m)) 10 else fp$cluster_confluence_m
      frs_cluster(conn, table, habitat,
        label_cluster = "rearing", label_connect = "spawning",
        species = sp, direction = dir,
        bridge_gradient = bg, bridge_distance = bd,
        confluence_m = cm, verbose = verbose)
    }

    # Check spawning connectivity (requires_connected: rearing)
    spawn_rules <- ps[["rules"]][["spawn"]]
    has_rc <- length(spawn_rules) > 0 && any(vapply(
      spawn_rules,
      function(rule) !is.null(rule[["requires_connected"]]),
      logical(1)))

    if (has_rc && isTRUE(fp$cluster_spawning)) {
      # Extract connected_distance_max and bridge_gradient from rules
      rc_target <- NULL
      rc_distance <- NULL
      for (rule in spawn_rules) {
        if (!is.null(rule[["requires_connected"]])) {
          rc_target <- rule[["requires_connected"]]
          rc_distance <- rule[["connected_distance_max"]]
          break
        }
      }
      if (!is.null(rc_target)) {
        bg <- if (is.na(fp$cluster_spawn_bridge_gradient)) 0.05 else
          fp$cluster_spawn_bridge_gradient
        bd <- if (!is.null(rc_distance)) rc_distance else
          if (is.na(fp$cluster_spawn_bridge_distance)) 3000 else
            fp$cluster_spawn_bridge_distance

        # Detect lake-connected rearing: use two-phase approach
        rear_rules <- ps[["rules"]][["rear"]]
        has_lake_rear <- length(rear_rules) > 0 && any(vapply(
          rear_rules,
          function(r) identical(r[["waterbody_type"]], "L"),
          logical(1)))

        if (has_lake_rear) {
          # Two-phase: downstream trace + upstream lake proximity
          .frs_connected_spawning(conn, table, habitat,
            species = sp, bridge_gradient = bg,
            distance_max = bd, verbose = verbose)
        } else {
          # Generic cluster approach for non-lake rearing
          dir <- if (is.na(fp$cluster_spawn_direction)) "both" else
            fp$cluster_spawn_direction
          cm <- if (is.na(fp$cluster_spawn_confluence_m)) 10 else
            fp$cluster_spawn_confluence_m
          frs_cluster(conn, table, habitat,
            label_cluster = "spawning", label_connect = rc_target,
            species = sp, direction = dir,
            bridge_gradient = bg, bridge_distance = bd,
            confluence_m = cm, verbose = verbose)
          if (!is.null(rc_distance)) {
            .frs_distance_filter(conn, table, habitat,
              label_cluster = "spawning", label_connect = rc_target,
              species = sp, max_distance = rc_distance,
              verbose = verbose)
          }
        }
      }
    }
  }
}


#' Filter classified segments by distance to connected habitat
#'
#' After [frs_cluster()] removes disconnected clusters, this function
#' removes individual segments within valid clusters whose network
#' distance to the nearest connected segment exceeds `max_distance`.
#'
#' Uses `downstream_route_measure` difference on the same BLK for
#' same-stream distance. Cross-BLK distance uses ltree-based
#' network traversal.
#'
#' @noRd
.frs_distance_filter <- function(conn, table, habitat,
                                 label_cluster, label_connect,
                                 species, max_distance,
                                 verbose = TRUE) {
  sp_quoted <- .frs_quote_string(species)
  dist_m <- .frs_sql_num(max_distance)

  # Count before
  n_before <- 0L
  if (verbose) {
    n_before <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*) FILTER (WHERE %s)::int AS n FROM %s
       WHERE species_code = %s",
      label_cluster, habitat, sp_quoted))$n
  }

  # Remove segments that are DOWNSTREAM of rearing AND beyond the
  # distance cap. Upstream spawning has no distance cap — limited by
  # spawn-eligible contiguity (matching bcfishpass v0.5.0 SK logic).
  #
  # A segment is kept if ANY rearing segment satisfies:
  #   Same-BLK upstream: s.drm >= r.drm (segment above rearing, any distance)
  #   Same-BLK downstream within cap: s.drm < r.drm AND diff <= max
  #   Cross-BLK upstream: fwa_upstream(s, r) (rearing is upstream, any distance)
  #   Cross-BLK downstream within cap: NOT upstream AND Euclidean <= max
  .frs_db_execute(conn, sprintf(
    "UPDATE %s h SET %s = FALSE
     FROM %s s
     WHERE h.id_segment = s.id_segment
       AND h.species_code = %s
       AND h.%s IS TRUE
       AND NOT EXISTS (
         SELECT 1 FROM %s r
         INNER JOIN %s hr ON r.id_segment = hr.id_segment
         WHERE hr.species_code = %s
           AND hr.%s IS TRUE
           AND (
             -- Same-BLK: upstream of rearing (any distance)
             (r.blue_line_key = s.blue_line_key
              AND s.downstream_route_measure >= r.downstream_route_measure)
             OR
             -- Same-BLK: downstream of rearing, within cap
             (r.blue_line_key = s.blue_line_key
              AND s.downstream_route_measure < r.downstream_route_measure
              AND r.downstream_route_measure - s.downstream_route_measure <= %s)
             OR
             -- Cross-BLK: spawning upstream of rearing (any distance)
             -- fwa_upstream(r, s) = TRUE when s is upstream of r
             (r.blue_line_key != s.blue_line_key
              AND s.wscode_ltree IS NOT NULL
              AND r.wscode_ltree IS NOT NULL
              AND fwa_upstream(r.wscode_ltree, r.localcode_ltree,
                               s.wscode_ltree, s.localcode_ltree))
             OR
             -- Cross-BLK: downstream, within Euclidean cap
             (r.blue_line_key != s.blue_line_key
              AND ST_Distance(s.geom, r.geom) <= %s)
           )
       )",
    habitat, label_cluster, table,
    sp_quoted, label_cluster,
    table, habitat,
    sp_quoted, label_connect,
    dist_m, dist_m))

  if (verbose) {
    n_after <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*) FILTER (WHERE %s)::int AS n FROM %s
       WHERE species_code = %s",
      label_cluster, habitat, sp_quoted))$n
    cat("  ", species, ": ", n_before - n_after,
        " beyond ", max_distance, "m removed (",
        n_after, " ", label_cluster, " remaining)\n", sep = "")
  }
}


#' Two-phase connected spawning for lake-rearing species
#'
#' Replaces the generic frs_cluster approach for species where
#' `requires_connected: rearing` targets lake-type rearing (SK, KO).
#'
#' Phase 1 (downstream): trace downstream from rearing lake outlets
#' via `fwa_downstreamtrace()`, cap at `distance_max`, stop at first
#' segment with gradient > `bridge_gradient`. Mainstem only.
#'
#' Phase 2 (upstream): find spawn-eligible segments upstream of
#' rearing via `FWA_Upstream()`, cluster with `ST_ClusterDBSCAN`,
#' keep only clusters within 2m of a qualifying lake polygon
#' (`fwa_lakes_poly` with `area_ha >= lake_ha_min`).
#'
#' @noRd
.frs_connected_spawning <- function(conn, table, habitat,
                                    species, bridge_gradient = 0.05,
                                    distance_max = 3000,
                                    lake_ha_min = 200,
                                    verbose = TRUE) {
  sp_quoted <- .frs_quote_string(species)
  bg <- .frs_sql_num(bridge_gradient)
  dm <- .frs_sql_num(distance_max)
  lhm <- .frs_sql_num(lake_ha_min)

  n_before <- 0L
  if (verbose) {
    n_before <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*) FILTER (WHERE spawning)::int AS n FROM %s
       WHERE species_code = %s", habitat, sp_quoted))$n
  }

  # Build a temp table of qualifying segment IDs from both phases.
  # Then set spawning = FALSE for segments NOT in the temp table.
  # This preserves spawn thresholds from frs_habitat_classify().
  qual_tbl <- sprintf("pg_temp.frs_qual_spawn_%s", tolower(species))
  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", qual_tbl))
  .frs_db_execute(conn, sprintf("CREATE TEMP TABLE %s (id_segment integer)",
                                qual_tbl))

  # Phase 1: Downstream — trace from rearing lake outlets,
  # cap at distance_max, stop at first gradient > bridge_gradient
  .frs_db_execute(conn, sprintf(
    "INSERT INTO %s (id_segment)
     WITH lake_outlets AS (
       SELECT DISTINCT ON (s2.waterbody_key)
         s2.blue_line_key, s2.downstream_route_measure
       FROM %s s2
       INNER JOIN %s hr ON s2.id_segment = hr.id_segment
       WHERE hr.species_code = %s AND hr.rearing IS TRUE
       ORDER BY s2.waterbody_key, s2.downstream_route_measure ASC
     ),
     downstream AS (
       SELECT lo.blue_line_key AS lake_blk,
         t.linear_feature_id, t.gradient, t.wscode,
         t.downstream_route_measure,
         -t.length_metre + SUM(t.length_metre) OVER (
           PARTITION BY lo.blue_line_key
           ORDER BY t.wscode DESC, t.downstream_route_measure DESC
         ) AS dist_to_lake
       FROM lake_outlets lo
       CROSS JOIN LATERAL whse_basemapping.fwa_downstreamtrace(
         lo.blue_line_key, lo.downstream_route_measure) t
       WHERE t.blue_line_key = t.watershed_key
     ),
     downstream_capped AS (
       SELECT row_number() OVER (
         PARTITION BY lake_blk
         ORDER BY wscode DESC, downstream_route_measure DESC
       ) AS rn, *
       FROM downstream WHERE dist_to_lake < %s
     ),
     nearest_barrier AS (
       SELECT DISTINCT ON (lake_blk) *
       FROM downstream_capped WHERE gradient > %s
       ORDER BY lake_blk, wscode DESC, downstream_route_measure DESC
     ),
     valid_downstream AS (
       SELECT d.linear_feature_id FROM downstream_capped d
       LEFT JOIN nearest_barrier nb ON d.lake_blk = nb.lake_blk
       WHERE nb.rn IS NULL OR d.rn < nb.rn
     )
     SELECT seg.id_segment FROM %s seg
     WHERE seg.linear_feature_id IN (
       SELECT linear_feature_id FROM valid_downstream)",
    qual_tbl, table, habitat, sp_quoted, dm, bg, table))

  # Phase 2: Upstream — spawn-eligible segments upstream of rearing,
  # clustered, kept only if cluster touches qualifying lake polygon
  .frs_db_execute(conn, sprintf(
    "INSERT INTO %s (id_segment)
     WITH rearing_segs AS (
       SELECT s2.wscode_ltree, s2.localcode_ltree,
              s2.blue_line_key, s2.downstream_route_measure
       FROM %s s2
       INNER JOIN %s hr ON s2.id_segment = hr.id_segment
       WHERE hr.species_code = %s AND hr.rearing IS TRUE
     ),
     spawn_upstream AS (
       SELECT s3.id_segment, s3.geom
       FROM %s s3
       INNER JOIN %s hs ON s3.id_segment = hs.id_segment
       WHERE hs.species_code = %s AND hs.spawning IS TRUE
         AND EXISTS (
           SELECT 1 FROM rearing_segs r
           WHERE fwa_upstream(r.wscode_ltree, r.localcode_ltree,
                              s3.wscode_ltree, s3.localcode_ltree)
             OR (r.blue_line_key = s3.blue_line_key
                 AND s3.downstream_route_measure >= r.downstream_route_measure))
     ),
     clustered AS (
       SELECT id_segment,
         ST_ClusterDBSCAN(geom, 1, 1) OVER () AS cluster_id
       FROM spawn_upstream
     ),
     cluster_geoms AS (
       SELECT cluster_id, ST_Collect(su.geom) AS geom
       FROM clustered c
       INNER JOIN spawn_upstream su ON c.id_segment = su.id_segment
       GROUP BY cluster_id
     ),
     valid_clusters AS (
       SELECT cg.cluster_id FROM cluster_geoms cg
       WHERE EXISTS (
         SELECT 1 FROM whse_basemapping.fwa_lakes_poly lp
         WHERE lp.area_ha >= %s AND ST_DWithin(cg.geom, lp.geom, 2))
     )
     SELECT c.id_segment FROM clustered c
     WHERE c.cluster_id IN (SELECT cluster_id FROM valid_clusters)",
    qual_tbl, table, habitat, sp_quoted,
    table, habitat, sp_quoted, lhm))

  # Subtractive: remove spawning NOT found in either phase
  .frs_db_execute(conn, sprintf(
    "UPDATE %s SET spawning = FALSE
     WHERE species_code = %s AND spawning IS TRUE
       AND id_segment NOT IN (SELECT id_segment FROM %s)",
    habitat, sp_quoted, qual_tbl))

  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", qual_tbl))

  if (verbose) {
    n_after <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*) FILTER (WHERE spawning)::int AS n FROM %s
       WHERE species_code = %s", habitat, sp_quoted))$n
    cat("  ", species, ": connected spawning ",
        n_before, " -> ", n_after, "\n", sep = "")
  }
}
