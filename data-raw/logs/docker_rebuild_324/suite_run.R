# Full test suite against one local fwapg, for the #324 comparison of the
# rebuild (port 5433) with the live database (5432), test by test.
# Run from the repo root:
#   Rscript data-raw/logs/docker_rebuild_324/suite_run.R <port> <GEOS prefix> <out.csv>
# e.g. 5432 3.9.0 .../suite_5432.csv and 5433 3.13.1 .../suite_5433.csv.
#
# A user ~/.Renviron can set PG* to another host, and R's environment wins
# over the shell's, so all five are set here, before any connection. The
# FRESH_PG* group (the fwapg gate tests) is aimed at the same database.
# PG_*_SHARE (the bcfishpass tests) is left as it is, the same for both runs.
args <- commandArgs(TRUE)
port <- args[1]
geos <- args[2]
out <- args[3]
stopifnot(length(args) == 3L)

Sys.setenv(PGHOST = "localhost", PGPORT = port, PGDATABASE = "fwapg",
           PGUSER = "postgres", PGPASSWORD = "postgres",
           FRESH_PGHOST = "localhost", FRESH_PGPORT = port,
           FRESH_PGDATABASE = "fwapg", FRESH_PGUSER = "postgres",
           FRESH_PGPASSWORD = "postgres")
Sys.unsetenv(c("PGSERVICE", "FRESH_FWAPG_CURRENT", "FRESH_FWAPG_TRIAL"))

# Connect once with the dev package, so a wrong target errors here instead of
# turning every live test into a skip, and prove which database it is.
devtools::load_all(quiet = TRUE)
conn <- frs_db_conn()
g <- DBI::dbGetQuery(conn, "SELECT postgis_geos_version() AS g")$g
v <- tryCatch(DBI::dbGetQuery(conn, "SELECT tag FROM fwapg.db_version")$tag,
              error = function(e) NA_character_)
v <- if (length(v)) max(v) else NA_character_
DBI::dbDisconnect(conn)
cat(sprintf("target: port %s, GEOS %s, fwapg.db_version %s\n", port, g, v))
if (!startsWith(g, geos)) stop("GEOS ", g, " is not the expected ", geos, ": wrong database")

testthat::set_max_fails(Inf)
t0 <- Sys.time()
r <- as.data.frame(devtools::test(stop_on_failure = FALSE))
cat(sprintf("suite took %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
keep <- c("file", "context", "test", "nb", "failed", "skipped", "error", "warning", "passed")
r <- r[intersect(keep, names(r))]
write.csv(r[order(r$file, r$test, method = "radix"), ], out, row.names = FALSE)
# The frame has one row per test_that() block, so these count blocks; a file-level skip
# adds no row. The reporter's [ FAIL | WARN | SKIP | PASS ] line above counts expectations.
cat(sprintf("%s: %d test blocks, %d with a failure, %d errored, %d with a skip\n", out, nrow(r),
            sum(r$failed > 0), sum(r$error), sum(r$skipped)))
