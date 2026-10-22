# Live check for fresh#262: frs_near_river() by channel width and by stream
# order on one watershed group.
#
# The walk's distances were checked by measure-agnostic means in #259
# (data-raw/near_river_check.R): against an independent route-measure walk
# that reads discharge, kept outside this repo. That reference cannot read
# width or order, so this script checks what #262 changed, the column the
# walk reads, by equivalence:
#   for each of width and order, the walk by that measure at threshold T
#   must equal, row for row (id_segment, dist_m), the discharge walk at T
#   on a copy of the table whose mad_m3s holds that measure's values.
# Any difference is a defect in the column threading, since the walk SQL is
# otherwise the one #259 validated.
#
# It also reports, per main-flow edge type, how many rows carry each
# measure (the coverage that decides which rivers each measure can see),
# how many segments each measure finds within 1 km, and the walk time.
#
# Discharge is wet's annual pick (discharge.fwa_v1_segment_monthly,
# scenario 'historical', month 0, pick; 0 read as no value), as in
# near_river_check.R.
#
# Usage (from the fresh repo root):
#   Rscript data-raw/near_river_measure_check.R [WSG] [Q] [WIDTH] [ORDER] [D]
#   Rscript data-raw/near_river_measure_check.R BULK 3 20 5 1000
# Writes data-raw/logs/near_river_262/<wsg>_{coverage,found,equivalence}.csv
# and <wsg>_stamp.txt, then drops the scratch schema.

pkgload::load_all(".", quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
arg <- function(i, default) if (length(args) >= i) args[i] else default
wsg <- toupper(arg(1, "BULK"))
q <- as.numeric(arg(2, 3))
w <- as.numeric(arg(3, 20))
o <- as.numeric(arg(4, 5))
d <- as.numeric(arg(5, 1000))
stopifnot(grepl("^[A-Z]{4}$", wsg), all(is.finite(c(q, w, o, d))),
          all(c(q, w, o, d) > 0))
out_dir <- file.path("data-raw", "logs", "near_river_262")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

conn <- frs_db_conn()
schema <- "near_river_measure_check"
tbl <- paste0(schema, ".streams")
DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", schema))

frs_network_segment(conn, aoi = wsg, to = tbl, verbose = FALSE)
DBI::dbExecute(conn, sprintf(
  "UPDATE %s s SET mad_m3s = (
     SELECT nullif(q.q_m3s, 0) FROM discharge.fwa_v1_segment_monthly q
     WHERE q.linear_feature_id = s.linear_feature_id
       AND q.scenario = 'historical' AND q.month = 0 AND q.pick)", tbl))

coverage <- DBI::dbGetQuery(conn, sprintf(
  "SELECT edge_type, count(*)::int AS rows,
     count(mad_m3s)::int AS with_discharge,
     count(channel_width)::int AS with_channel_width,
     count(stream_order)::int AS with_stream_order
   FROM %s WHERE blue_line_key = watershed_key
     AND edge_type IN (1000, 1050, 1200, 1250)
   GROUP BY edge_type ORDER BY edge_type", tbl))
coverage$watershed_group_code <- wsg

runs <- data.frame(measure = c("discharge", "channel_width", "stream_order"),
                   threshold = c(q, w, o), stringsAsFactors = FALSE)
found <- list()
for (i in seq_len(nrow(runs))) {
  to <- sprintf("%s.near_%s", schema, runs$measure[i])
  t0 <- proc.time()
  frs_near_river(conn, tbl, to, threshold = runs$threshold[i],
                 distance_max = d, measure = runs$measure[i], verbose = TRUE)
  secs <- (proc.time() - t0)[["elapsed"]]
  n <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n, coalesce(sum(s.length_metre), 0) / 1000 AS km
     FROM %s n JOIN %s s USING (id_segment, watershed_group_code)", to, tbl))
  coffin <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s n JOIN %s s
       USING (id_segment, watershed_group_code)
     WHERE s.gnis_name = 'Coffin Creek'", to, tbl))$n
  found[[i]] <- data.frame(watershed_group_code = wsg,
    measure = runs$measure[i], threshold = runs$threshold[i],
    distance_max = d, segments_found = n$n, km_found = round(n$km, 1),
    coffin_creek_segments_found = coffin, walk_s = round(secs, 1))
}
found <- do.call(rbind, found)

equivalence <- list()
for (m in c("channel_width", "stream_order")) {
  thr <- runs$threshold[runs$measure == m]
  copy <- sprintf("%s.streams_as_%s", schema, m)
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", copy))
  # LIKE ... INCLUDING ALL keeps the network indexes; a bare CREATE TABLE AS
  # leaves FWA_Downstream()'s join unindexed and the walk runs for hours.
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s (LIKE %s INCLUDING ALL)",
                               copy, tbl))
  DBI::dbExecute(conn, sprintf("INSERT INTO %s SELECT * FROM %s", copy, tbl))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s SET mad_m3s = %s::double precision", copy, m))
  via <- sprintf("%s.near_via_discharge_%s", schema, m)
  frs_near_river(conn, copy, via, threshold = thr, distance_max = d,
                 measure = "discharge", verbose = FALSE)
  direct <- sprintf("%s.near_%s", schema, m)
  diff_sql <- function(a, b) sprintf(
    "SELECT count(*)::int AS n FROM (
       SELECT id_segment, round(dist_m::numeric, 6) FROM %s
       EXCEPT SELECT id_segment, round(dist_m::numeric, 6) FROM %s) x", a, b)
  equivalence[[m]] <- data.frame(watershed_group_code = wsg, measure = m,
    threshold = thr, distance_max = d,
    rows_direct = DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int AS n FROM %s", direct))$n,
    only_direct = DBI::dbGetQuery(conn, diff_sql(direct, via))$n,
    only_via_discharge = DBI::dbGetQuery(conn, diff_sql(via, direct))$n)
}
equivalence <- do.call(rbind, equivalence)
rownames(equivalence) <- NULL

stem <- file.path(out_dir, tolower(wsg))
utils::write.csv(coverage, paste0(stem, "_coverage.csv"), row.names = FALSE)
utils::write.csv(found, paste0(stem, "_found.csv"), row.names = FALSE)
utils::write.csv(equivalence, paste0(stem, "_equivalence.csv"),
                 row.names = FALSE)
writeLines(c(
  sprintf("date_utc: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
  sprintf("fresh: %s", as.character(utils::packageVersion("fresh"))),
  sprintf("fresh_sha: %s", system("git rev-parse --short HEAD", intern = TRUE)),
  sprintf("args: %s", paste(c(wsg, q, w, o, d), collapse = " ")),
  sprintf("wet_rows: %s", DBI::dbGetQuery(conn,
    "SELECT count(*) FROM discharge.fwa_v1_segment_monthly")[[1]])),
  paste0(stem, "_stamp.txt"))

DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
DBI::dbDisconnect(conn)
print(coverage)
print(found)
print(equivalence)
stopifnot(all(equivalence$only_direct == 0),
          all(equivalence$only_via_discharge == 0))
