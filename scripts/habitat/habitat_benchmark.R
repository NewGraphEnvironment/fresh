# Benchmark frs_habitat on a watershed group
#
# Usage:
#   Rscript scripts/habitat/habitat_benchmark.R              # default: ADMS
#   Rscript scripts/habitat/habitat_benchmark.R BULK
#
# Output to log:
#   Rscript scripts/habitat/habitat_benchmark.R ADMS 2>&1 | \
#     tee scripts/habitat/logs/$(date +%Y%m%d)_habitat_benchmark-sequential.txt

devtools::load_all()
library(sf)

sf_use_s2(FALSE)

args <- commandArgs(trailingOnly = TRUE)
wsg <- if (length(args) > 0) args[1] else "ADMS"

cat("=== frs_habitat benchmark ===\n")
cat("WSG:", wsg, "\n")
cat("Method: sequential, access+habitat dedup\n")
cat("Commit:", system("git rev-parse --short HEAD", intern = TRUE), "\n")
cat("Date:", format(Sys.time()), "\n\n")

conn <- frs_db_conn()
on.exit(DBI::dbDisconnect(conn))

result <- frs_habitat(conn, wsg, cleanup = TRUE)

cat("\n")
print(result)
