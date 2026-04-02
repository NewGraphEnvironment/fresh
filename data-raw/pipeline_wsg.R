# Run the fresh habitat pipeline for all species in a watershed group
#
# Extracts the enriched stream network from bcfishpass.streams_vw (already
# has channel_width, gradient, mad, wscode/localcode), then runs the fresh
# pipeline (break → classify → categorize) per species.
#
# Usage:
#   Rscript data-raw/pipeline_wsg.R              # default: BULK
#   Rscript data-raw/pipeline_wsg.R MORR         # single WSG
#   Rscript data-raw/pipeline_wsg.R BULK MORR    # multiple WSGs (sequential)
#
# Parallelism:
#   - Across WSGs: furrr::future_map with plan(multisession), each worker
#     gets its own DB connection
#   - Within a WSG: species are independent (separate working tables), but
#     the bottleneck is PostgreSQL (geometry splits in frs_break), so
#     concurrent species can saturate PG workers
#   - PostgreSQL tuning: max_parallel_workers_per_gather, work_mem
#
# TODO: benchmark sequential vs parallel, profile PG-side bottlenecks

devtools::load_all()
library(sf)

sf_use_s2(FALSE)

# ============================================================================
# Configuration
# ============================================================================
args <- commandArgs(trailingOnly = TRUE)
wsg_codes <- if (length(args) > 0) args else "BULK"

cat("=== fresh habitat pipeline ===\n")
cat("Watershed groups:", paste(wsg_codes, collapse = ", "), "\n")
cat("Started:", format(Sys.time()), "\n\n")

# Load parameters once
params_all <- frs_params(csv = system.file("extdata",
  "parameters_habitat_thresholds.csv", package = "fresh"))
params_fresh <- read.csv(system.file("extdata",
  "parameters_fresh.csv", package = "fresh"))

# ============================================================================
# Pipeline for a single species (operates on its own working table)
# ============================================================================
#' @param conn DB connection
#' @param wsg Watershed group code (e.g. "BULK")
#' @param species_code Uppercase species code (e.g. "CO")
#' @param base_tbl Schema-qualified base table (enriched network, shared)
#' @param params_sp Species params from frs_params() (e.g. params_all$CO)
#' @param fresh_sp Row from parameters_fresh.csv
#' @return Named list with timings
run_species <- function(conn, wsg, species_code, base_tbl, params_sp,
                        fresh_sp) {
  sp <- tolower(species_code)
  tbl <- paste0("working.", tolower(wsg), "_", sp)
  breaks_tbl <- paste0(tbl, "_breaks_access")
  breaks_hab_tbl <- paste0(tbl, "_breaks_habitat")

  timings <- list(species = species_code, wsg = wsg)

  # -- Copy base network for this species ------------------------------------
  # Each species needs its own table because frs_break_apply modifies geometry
  t0 <- proc.time()
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s AS SELECT * FROM %s",
                               tbl, base_tbl))
  # gradient as generated column so it recomputes after geometry splits
  frs_col_generate(conn, tbl)
  timings$copy_s <- (proc.time() - t0)["elapsed"]

  n_segments <- DBI::dbGetQuery(conn,
    sprintf("SELECT count(*) AS n FROM %s", tbl))$n
  cat("  ", species_code, ": ", n_segments, " segments\n", sep = "")

  # -- Access barriers -------------------------------------------------------
  t0 <- proc.time()
  access_gradient <- fresh_sp$access_gradient_max

  frs_break_find(conn, tbl,
    attribute = "gradient", threshold = access_gradient,
    to = breaks_tbl)

  # Barrier falls
  frs_break_find(conn, tbl,
    points_table = "bcfishpass.falls_vw",
    where = "barrier_ind = TRUE", aoi = wsg,
    to = breaks_tbl, append = TRUE)

  frs_break_apply(conn, tbl, breaks = breaks_tbl)
  frs_classify(conn, tbl, label = "accessible", breaks = breaks_tbl)
  timings$access_s <- (proc.time() - t0)["elapsed"]

  # -- Habitat classification ------------------------------------------------
  t0 <- proc.time()
  spawn_gradient_max <- params_sp$spawn_gradient_max
  spawn_gradient_min <- fresh_sp$spawn_gradient_min

  # Break at habitat gradient threshold
  frs_break(conn, tbl,
    attribute = "gradient", threshold = spawn_gradient_max,
    to = breaks_hab_tbl)

  # Spawning — with minimum gradient from parameters_fresh
  frs_classify(conn, tbl, label = paste0(sp, "_spawning"),
    ranges = list(
      gradient = c(spawn_gradient_min, spawn_gradient_max),
      channel_width = params_sp$ranges$spawn$channel_width),
    where = "accessible IS TRUE")

  # Rearing (if species has rearing thresholds)
  if (!is.null(params_sp$ranges$rear)) {
    frs_classify(conn, tbl, label = paste0(sp, "_rearing"),
      ranges = params_sp$ranges$rear[c("gradient", "channel_width")],
      where = "accessible IS TRUE")

    # Lake rearing
    frs_classify(conn, tbl, label = paste0(sp, "_lake_rearing"),
      ranges = list(channel_width = params_sp$ranges$rear$channel_width),
      where = paste0("accessible IS TRUE AND waterbody_key IN ",
                     "(SELECT waterbody_key FROM whse_basemapping.fwa_lakes_poly)"))
  }
  timings$classify_s <- (proc.time() - t0)["elapsed"]

  # -- Categorize ------------------------------------------------------------
  t0 <- proc.time()
  cols_cat <- paste0(sp, "_spawning")
  vals_cat <- paste0(toupper(sp), "_SPAWNING")

  if (!is.null(params_sp$ranges$rear)) {
    cols_cat <- c(cols_cat, paste0(sp, "_rearing"), paste0(sp, "_lake_rearing"))
    vals_cat <- c(vals_cat, paste0(toupper(sp), "_REARING"),
                  paste0(toupper(sp), "_LAKE_REARING"))
  }
  cols_cat <- c(cols_cat, "accessible")
  vals_cat <- c(vals_cat, "ACCESSIBLE")

  frs_categorize(conn, tbl, label = "habitat_type",
    cols = cols_cat, values = vals_cat, default = "INACCESSIBLE")
  timings$categorize_s <- (proc.time() - t0)["elapsed"]

  timings$total_s <- timings$copy_s + timings$access_s +
    timings$classify_s + timings$categorize_s

  timings
}

# ============================================================================
# Run one watershed group (all species)
# ============================================================================
run_wsg <- function(wsg) {
  cat("\n--- ", wsg, " ---\n", sep = "")
  t_wsg <- proc.time()

  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")

  # -- Extract base network once (bcfishpass.streams_vw has everything) ------
  base_tbl <- paste0("working.", tolower(wsg), "_base")
  t0 <- proc.time()
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", base_tbl))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT * FROM bcfishpass.streams_vw
     WHERE watershed_group_code = %s",
    base_tbl, .frs_quote_string(wsg)))
  extract_s <- (proc.time() - t0)["elapsed"]
  n_base <- DBI::dbGetQuery(conn,
    sprintf("SELECT count(*) AS n FROM %s", base_tbl))$n
  cat("Base network: ", n_base, " segments (", round(extract_s, 1), "s)\n",
      sep = "")

  # -- Species to model ------------------------------------------------------
  sp_df <- frs_wsg_species(wsg)
  sp_df <- sp_df[!is.na(sp_df$view), ]  # drop gr (no bcfishpass view)

  # Deduplicate: ct/dv/rb share a view, but each has its own params
  cat("Species to model:", paste(sp_df$species_code, collapse = ", "), "\n")

  all_timings <- list()

  for (i in seq_len(nrow(sp_df))) {
    species_code <- sp_df$species_code[i]
    params_sp <- params_all[[species_code]]

    if (is.null(params_sp)) {
      cat("  ", species_code, ": no params in thresholds CSV, skipping\n",
          sep = "")
      next
    }

    fresh_sp <- params_fresh[params_fresh$species_code == species_code, ]
    if (nrow(fresh_sp) == 0) {
      cat("  ", species_code, ": no fresh params, skipping\n", sep = "")
      next
    }

    t <- run_species(conn, wsg, species_code, base_tbl, params_sp, fresh_sp)
    all_timings[[species_code]] <- t
    cat("  ", species_code, " done: ",
        round(t$total_s, 1), "s",
        " (copy=", round(t$copy_s, 1),
        " access=", round(t$access_s, 1),
        " classify=", round(t$classify_s, 1),
        " categorize=", round(t$categorize_s, 1), ")\n", sep = "")
  }

  wsg_elapsed <- (proc.time() - t_wsg)["elapsed"]
  cat(wsg, " total: ", round(wsg_elapsed, 1), "s (",
      length(all_timings), " species)\n", sep = "")

  list(wsg = wsg, elapsed_s = wsg_elapsed, extract_s = extract_s,
       n_segments = n_base, species = all_timings)
}

# ============================================================================
# Run all WSGs — sequential
# ============================================================================
results <- lapply(wsg_codes, run_wsg)

# ============================================================================
# Summary
# ============================================================================
cat("\n=== Summary ===\n")
for (r in results) {
  cat(r$wsg, ": ", r$n_segments, " segments, ",
      round(r$elapsed_s, 1), "s total (",
      round(r$extract_s, 1), "s extract)\n", sep = "")
  for (sp_name in names(r$species)) {
    t <- r$species[[sp_name]]
    cat("  ", sp_name, ": ", round(t$total_s, 1), "s\n", sep = "")
  }
}
cat("\nFinished:", format(Sys.time()), "\n")


# ============================================================================
# Parallel execution with furrr (uncomment to use)
# ============================================================================
# The bottleneck is PostgreSQL, not R. Parallelism helps when:
#   1. Multiple WSGs → each worker gets its own connection + PG backend
#   2. PG has spare capacity (check max_connections, max_worker_processes)
#
# Within a single WSG, species write to separate tables (no conflicts),
# but frs_break_find calls fwa_slopealonginterval() which is CPU-heavy
# on PG. Too many concurrent species saturate PG workers.
#
# Strategy: parallelize across WSGs first (coarser grain, less contention).
# Within each WSG, species run sequentially.
#
# library(furrr)
# plan(multisession, workers = 4)  # tune to PG capacity
#
# results <- future_map(wsg_codes, run_wsg, .options = furrr_options(
#   seed = TRUE,
#   packages = c("fresh", "sf", "DBI")
# ))
#
# plan(sequential)

# ============================================================================
# PostgreSQL optimization notes
# ============================================================================
# Heavy server-side operations (in order of cost):
#
# 1. frs_break_find (gradient mode)
#    - fwa_slopealonginterval() per blue_line_key — CPU-bound on PG
#    - Tuning: work_mem, max_parallel_workers_per_gather
#
# 2. frs_break_apply (geometry splits)
#    - ST_LineSubstring / ST_LocateAlong per break point
#    - Benefits from: effective_cache_size, shared_buffers
#
# 3. frs_classify (breaks mode — fwa_downstream traversal)
#    - ltree containment check per segment
#    - Benefits from GiST index on wscode_ltree
#
# To profile:
#   DBI::dbExecute(conn, "SET log_min_duration_statement = 0")
#   -- then check pg_stat_statements or the PG log
#
# To check PG parallelism settings:
#   DBI::dbGetQuery(conn, "SHOW max_parallel_workers_per_gather")
#   DBI::dbGetQuery(conn, "SHOW work_mem")
#   DBI::dbGetQuery(conn, "SHOW shared_buffers")
