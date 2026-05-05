# Benchmark: island-based gradient breaks vs old interval method
#
# Compares segment counts and pipeline timing for ADMS using the
# island approach (entry + exit breaks per steep section).
#
# Usage:
#   Rscript scripts/habitat/habitat_benchmark_island.R 2>&1 |
#     tee scripts/habitat/logs/$(date +%Y%m%d)_habitat_benchmark-island.txt

library(fresh)

conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432,
  dbname = "fwapg", user = "postgres", password = "postgres")

cat("=== Island gradient breaks benchmark ===\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("DB: local Docker fwapg\n\n")

# --- Break count comparison ---
cat("--- Break counts (ADMS, island method) ---\n")
frs_extract(conn, from = "whse_basemapping.fwa_stream_networks_sp",
  to = "working.bench_island",
  where = "watershed_group_code = 'ADMS'", overwrite = TRUE)

n_base <- DBI::dbGetQuery(conn,
  "SELECT count(*)::int n FROM working.bench_island")$n
cat("Base segments:", n_base, "\n\n")

thresholds <- c(0.0249, 0.0449, 0.0549, 0.0649, 0.15, 0.20, 0.25)
for (thr in thresholds) {
  t0 <- proc.time()
  frs_break_find(conn, "working.bench_island",
    attribute = "gradient", threshold = thr,
    to = "working.bench_breaks_tmp")
  elapsed <- round((proc.time() - t0)["elapsed"], 1)
  n <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int n FROM working.bench_breaks_tmp")$n
  cat(sprintf("  %5.2f%%: %6d breaks (%ss)\n", thr * 100, n, elapsed))
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.bench_breaks_tmp")
}

DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.bench_island")

# --- Full pipeline ---
cat("\n--- Full pipeline: ADMS with falls ---\n")
t_total <- proc.time()
result <- frs_habitat(conn, "ADMS", break_sources = list(
  list(table = "working.falls", where = "barrier_ind = TRUE",
       label = "blocked")
))
elapsed_total <- round((proc.time() - t_total)["elapsed"], 1)

print(result)

# Segment counts per species
cat("\n--- Segment counts ---\n")
for (i in seq_len(nrow(result))) {
  tbl <- result$table_name[i]
  n <- DBI::dbGetQuery(conn,
    sprintf("SELECT count(*)::int n FROM %s", tbl))$n
  cat(sprintf("  %s: %d segments\n", tbl, n))
}

cat("\nTotal pipeline time:", elapsed_total, "s\n")

# --- Comparison reference ---
cat("\n--- Comparison (old interval method) ---\n")
cat("Old break counts (from v0.7.0):\n")
cat("  15.00%: 28960 breaks\n")
cat("   5.49%: 39161 breaks\n")
cat("Old CO segments: 48186\n")
cat("Old pipeline time: 90s\n")

DBI::dbDisconnect(conn)
