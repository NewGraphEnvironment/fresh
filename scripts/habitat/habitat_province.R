# Province-wide habitat pipeline
#
# Runs frs_habitat across all WSGs sequentially.
# Each WSG: generates gradient barriers, segments, classifies, persists.
#
# Usage:
#   PGPASSWORD=postgres nohup Rscript scripts/habitat/habitat_province.R \
#     > scripts/habitat/logs/$(date +%Y%m%d)_habitat_province.txt 2>&1 &

library(fresh)

t_total <- proc.time()

conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432,
  dbname = "fwapg", user = "postgres", password = "postgres")

DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS fresh")
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")

# All WSGs
wsg_presence <- read.csv(system.file("extdata",
  "wsg_species_presence.csv", package = "fresh"), stringsAsFactors = FALSE)
all_wsgs <- sort(unique(wsg_presence$watershed_group_code))

cat("=== Province-wide habitat pipeline ===\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("WSGs:", length(all_wsgs), "\n\n")

# Run all WSGs — frs_habitat handles species lookup, barriers, segmentation
result <- frs_habitat(conn, all_wsgs,
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  break_sources = list(
    list(table = "working.falls", where = "barrier_ind = TRUE",
         label = "blocked")))

total_elapsed <- (proc.time() - t_total)["elapsed"]

cat("\n=== Summary ===\n")
cat("Total time:", round(total_elapsed / 60, 1), "minutes\n")
cat("WSGs processed:", nrow(result), "\n")
cat("Total segments:", sum(result$n_segments), "\n")
print(result)

DBI::dbDisconnect(conn)
