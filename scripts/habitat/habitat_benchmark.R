# Benchmark frs_habitat on a watershed group
#
# Usage:
#   Rscript scripts/habitat/habitat_benchmark.R                # ADMS, 1 worker
#   Rscript scripts/habitat/habitat_benchmark.R ADMS 3         # ADMS, 3 workers
#   Rscript scripts/habitat/habitat_benchmark.R BULK 4         # BULK, 4 workers
#
# Output to log:
#   Rscript scripts/habitat/habitat_benchmark.R ADMS 1 2>&1 | \
#     tee scripts/habitat/logs/$(date +%Y%m%d)_habitat_benchmark-sequential.txt
#   Rscript scripts/habitat/habitat_benchmark.R ADMS 3 2>&1 | \
#     tee scripts/habitat/logs/$(date +%Y%m%d)_habitat_benchmark-furrr-3w.txt

devtools::load_all()
library(sf)

sf_use_s2(FALSE)

args <- commandArgs(trailingOnly = TRUE)
wsg <- if (length(args) > 0) args[1] else "ADMS"
workers <- if (length(args) > 1) as.integer(args[2]) else 1L

method <- if (workers > 1L) paste0("furrr (", workers, " workers)") else "sequential"

cat("=== frs_habitat benchmark ===\n")
cat("WSG:", wsg, "\n")
cat("Method:", method, "\n")
cat("Commit:", system("git rev-parse --short HEAD", intern = TRUE), "\n")
cat("Date:", format(Sys.time()), "\n\n")

conn <- frs_db_conn()
on.exit(DBI::dbDisconnect(conn))

result <- frs_habitat(conn, wsg, workers = workers, cleanup = TRUE)

cat("\n")
print(result)
