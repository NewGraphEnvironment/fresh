# Live check for fresh#259: frs_near_river() on one watershed group,
# against an independent walk.
#
# Segments the group with frs_network_segment() (no breaks) into a scratch
# schema, sets mad_m3s to wet's annual pick (discharge.fwa_v1_segment_monthly,
# scenario 'historical', month 0, pick; 0 read as no value), and runs
# frs_near_river() at DISCHARGE m3/s with a 20 km reach, so the group's
# outlet is the only cap that matters. Times the walk at 1 km and 20 km.
#
# The reference is an independent walk on route measures over raw FWA and
# the same discharge: a SQL function pg_temp.ch_dist_profile(blk, drm,
# qmins, src) returning, per q, the distance to the centreline of the first
# primary-flow segment (connectors allowed) with flow >= q, its id, edge
# type, waterbody_key, status and the largest gap it jumped between lines
# (max_entry_gap_m). Its SQL file is passed as REFERENCE; without it the
# script stops after the timings.
#
# Each start's residual (fresh's bank distance minus the reference) is
# attributed to a measured cause, using two more runs of fresh's walk SQL
# (.frs_near_river_walk_sql()): the centreline distance (bank rule off)
# and the centreline distance without jumps. The script also checks that
# the 1 km and 20 km walks agree on every segment within 1 km, and that no
# distance is negative.
#
# Starts: up to 2,000 main-flow segments below DISCHARGE with a local code,
# sampled at random, plus up to 500 that frs_near_river() places within
# 200 m of a river, where the bank rule matters most. Classes, first match:
#   agree        both find nothing, or within 1 m
#   bank         fresh's centreline agrees within 1 m (or lies just past
#                the reach); the bank rule's subtraction is the whole
#                difference. The subtraction is fresh's own, so the class
#                also counts bank distances shorter than the straight line
#                from the segment to the target's polygon, an independent
#                lower bound (expected 0)
#   beyond       the reference's distance is past the 20 km reach
#   truncation   the reference's target is outside the group's table
#   connector    the reference stopped on a connector (1400/1450), which
#                fresh never takes as a target
#   nested_code  fresh's path holds a main-flow row whose local code nests
#                under a tributary's code, which FWA_Downstream() places
#                downstream of that tributary wherever it lies
#   entry        within twice fresh's jumps plus the reference's largest
#                gap: the two walks enter a parent line at different
#                points (fresh at the first row FWA_Downstream() returns,
#                where the local code puts the confluence, counting the
#                straight jump; the reference at the nearest point,
#                counting nothing). Either sign: where the code puts the
#                confluence below where the lines meet, fresh is shorter. The two entry points are at most about
#                a jump plus a gap apart along the line. Includes a walk
#                the jumps carry past the reach
#   ref_none     the reference found no river where fresh did
#   unexplained  anything else
#
# Usage (from the fresh repo root):
#   Rscript data-raw/near_river_check.R [WSG] [DISCHARGE] [REFERENCE]
#   Rscript data-raw/near_river_check.R BULK 3 /path/to/ch_dist_profile.sql
# Writes data-raw/logs/near_river_259/<wsg>_compare.csv,
# <wsg>_summary.csv and <wsg>_stamp.txt, then drops the scratch schema.

pkgload::load_all(".", quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
wsg <- if (length(args) >= 1) toupper(args[1]) else "BULK"
q <- if (length(args) >= 2) as.numeric(args[2]) else 3
ref_sql <- if (length(args) >= 3) args[3] else NA_character_
stopifnot(grepl("^[A-Z]{4}$", wsg), is.finite(q), q > 0)
if (!is.na(ref_sql) && !file.exists(ref_sql)) {
  stop("reference SQL not found: ", ref_sql, call. = FALSE)
}
d_far <- 20000
out_dir <- file.path("data-raw", "logs", "near_river_259")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

conn <- frs_db_conn()
schema <- "near_river_check"
tbl <- paste0(schema, ".streams")
near <- paste0(schema, ".near")
q_sql <- .frs_sql_num(q)

DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", schema))

frs_network_segment(conn, aoi = wsg, to = tbl, verbose = FALSE)
DBI::dbExecute(conn, sprintf(
  "UPDATE %s s SET mad_m3s = (
     SELECT nullif(q.q_m3s, 0) FROM discharge.fwa_v1_segment_monthly q
     WHERE q.linear_feature_id = s.linear_feature_id
       AND q.scenario = 'historical' AND q.month = 0 AND q.pick)", tbl))
counts <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS segments, count(mad_m3s)::int AS with_mad,
     count(*) FILTER (WHERE mad_m3s >= %s)::int AS at_or_above_q,
     count(*) FILTER (WHERE localcode_ltree IS NULL)::int AS no_local_code
   FROM %s", q_sql, tbl))

walk_timed <- function(d) {
  t0 <- proc.time()
  frs_near_river(conn, tbl, near, discharge_min = q, distance_max = d,
                 verbose = TRUE)
  (proc.time() - t0)[["elapsed"]]
}
timing <- walk_timed(1000)
DBI::dbExecute(conn, sprintf("CREATE TABLE %s.near_1km AS SELECT * FROM %s",
                             schema, near))
timing <- c(timing, walk_timed(d_far))
mismatch_1km <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS n FROM (
     SELECT id_segment, round(dist_m::numeric, 6) FROM %s WHERE dist_m <= 1000
     EXCEPT SELECT id_segment, round(dist_m::numeric, 6) FROM %s.near_1km) a", near, schema))$n +
  DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS n FROM (
     SELECT id_segment, round(dist_m::numeric, 6) FROM %s.near_1km
     EXCEPT SELECT id_segment, round(dist_m::numeric, 6) FROM %s WHERE dist_m <= 1000) a",
  schema, near))$n

# Centreline walk: the same SQL with the bank rule off.
lens <- DBI::dbGetQuery(conn, sprintf(
  "SELECT coalesce(max(l) FILTER (WHERE main), 0)::double precision AS on_path,
     coalesce(max(l) FILTER (WHERE NOT main), 0)::double precision AS side
   FROM (SELECT blue_line_key = watershed_key AS main, sum(length_metre) AS l
         FROM %s WHERE edge_type IN (1400, 1450) AND waterbody_key IS NOT NULL
         GROUP BY waterbody_key, blue_line_key, watershed_key) x", tbl))
DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.frs_near_river_walk")
DBI::dbExecute(conn, .frs_near_river_walk_sql(tbl,
  "pg_temp.frs_near_river_walk", q, d_far, conn_max = 0,
  entry_max = 0, bank = FALSE))
DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s.centre AS SELECT origin_id AS id_segment, dist_m
   FROM pg_temp.frs_near_river_walk WHERE discharge_min IS NOT NULL", schema))
DBI::dbExecute(conn, "DROP TABLE pg_temp.frs_near_river_walk")
DBI::dbExecute(conn, .frs_near_river_walk_sql(tbl,
  "pg_temp.frs_near_river_walk", q, d_far, conn_max = 0,
  entry_max = 0, bank = FALSE, jumps = FALSE))
DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s.nojump AS SELECT origin_id AS id_segment, dist_m
   FROM pg_temp.frs_near_river_walk WHERE discharge_min IS NOT NULL", schema))
offsets <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS both_found,
     count(*) FILTER (WHERE c.dist_m - n.dist_m > 0.001)::int AS offset_n,
     coalesce(avg(c.dist_m - n.dist_m) FILTER (
       WHERE c.dist_m - n.dist_m > 0.001), 0) AS offset_mean,
     coalesce(max(c.dist_m - n.dist_m), 0) AS offset_max,
     count(*) FILTER (WHERE c.dist_m - n.dist_m < -0.001)::int AS bank_longer
   FROM %s n JOIN %s.centre c USING (id_segment)", near, schema))

n_near <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*) FILTER (WHERE dist_m <= 1000)::int AS within_1km,
     count(*)::int AS within_20km,
     count(*) FILTER (WHERE dist_m < 0)::int AS negative
   FROM %s", near))

# Side channels with no local code beside a river at or above q: they
# never walk, so this sizes what the no-code limit costs.
side_nocode <- DBI::dbGetQuery(conn, sprintf(
  "SELECT o.edge_type, count(*)::int AS n,
     count(*) FILTER (WHERE EXISTS (
       SELECT 1 FROM %s t WHERE t.blue_line_key = t.watershed_key
         AND t.mad_m3s >= %s
         AND ST_DWithin(t.geom, ST_StartPoint(o.geom), 1)))::int
       AS joins_river
   FROM %s o WHERE o.localcode_ltree IS NULL
     AND o.edge_type IN (1100, 1150, 1350, 2300)
   GROUP BY o.edge_type ORDER BY o.edge_type", tbl, q_sql, tbl))

stamp <- c(
  sprintf("fresh %s @ %s%s", utils::packageVersion("fresh"),
          system("git rev-parse --short HEAD", intern = TRUE),
          if (length(system("git status --porcelain -- R tests DESCRIPTION",
                            intern = TRUE)) > 0) " (dirty)" else ""),
  sprintf("date %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")),
  sprintf("group %s, discharge %s m3/s, reach %s m", wsg, q, d_far),
  sprintf("segments %d, with mad %d, at or above q %d, no local code %d",
          counts$segments, counts$with_mad, counts$at_or_above_q,
          counts$no_local_code),
  sprintf("walk time: 1 km %.1f s, 20 km %.1f s", timing[1], timing[2]),
  sprintf("within 1 km %d, within 20 km %d, negative distances %d",
          n_near$within_1km, n_near$within_20km, n_near$negative),
  sprintf("1 km and 20 km walks disagree on %d segments within 1 km",
          mismatch_1km),
  sprintf(paste0("bank offsets: %d of %d found by both, mean %.1f m, ",
                 "max %.1f m (bound %.1f m); bank longer than centreline %d"),
          offsets$offset_n, offsets$both_found, offsets$offset_mean,
          offsets$offset_max, lens$on_path + lens$side, offsets$bank_longer),
  sprintf("side channels with no local code (edge n joins_river): %s",
          paste(sprintf("%d %d %d", side_nocode$edge_type, side_nocode$n,
                        side_nocode$joins_river), collapse = "; ")))
# link#364's example: Coffin Creek (BULK), 0.23 m3/s through a wetland,
# 5.3 km from the nearest 3 m3/s river by that issue's walk.
if (wsg == "BULK") {
  coffin <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n, count(n.dist_m)::int AS measured,
       min(n.dist_m) AS min_m, max(n.dist_m) AS max_m,
       count(*) FILTER (WHERE n.dist_m <= 1000)::int AS within_1km,
       min(n.dist_m) FILTER (WHERE s.waterbody_key IN (
         SELECT waterbody_key FROM whse_basemapping.fwa_wetlands_poly))
         AS wetland_min_m,
       max(n.dist_m) FILTER (WHERE s.waterbody_key IN (
         SELECT waterbody_key FROM whse_basemapping.fwa_wetlands_poly))
         AS wetland_max_m
     FROM %s s LEFT JOIN %s n USING (id_segment)
     WHERE s.gnis_name = 'Coffin Creek' AND s.mad_m3s < %s",
    tbl, near, q_sql))
  stamp <- c(stamp, sprintf(paste0(
    "Coffin Creek: %d segments below q, %d measured, %.0f to %.0f m, ",
    "%d within 1 km; through wetlands %.0f to %.0f m"), coffin$n,
    coffin$measured, coffin$min_m, coffin$max_m, coffin$within_1km,
    coffin$wetland_min_m, coffin$wetland_max_m))
}
own_q <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS n FROM %s n JOIN %s s USING (id_segment)
   WHERE s.mad_m3s >= %s", near, tbl, q_sql))$n
stamp <- c(stamp, sprintf("rows for segments at or above q: %d", own_q))

if (is.na(ref_sql)) {
  writeLines(stamp, file.path(out_dir, paste0(tolower(wsg), "_stamp.txt")))
  writeLines(stamp)
  DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
  DBI::dbDisconnect(conn)
  quit(save = "no")
}

# -- starts ------------------------------------------------------------------
set.seed(259)
pool <- DBI::dbGetQuery(conn, sprintf(
  "SELECT s.id_segment, s.linear_feature_id, s.blue_line_key,
     s.downstream_route_measure, n.dist_m AS bank_m, c.dist_m AS centre_m,
     j.dist_m AS nojump_m
   FROM %s s LEFT JOIN %s n USING (id_segment)
     LEFT JOIN %s.centre c USING (id_segment)
     LEFT JOIN %s.nojump j USING (id_segment)
   WHERE (s.mad_m3s IS NULL OR s.mad_m3s < %s)
     AND s.localcode_ltree IS NOT NULL
     AND s.blue_line_key = s.watershed_key", tbl, near, schema, schema, q_sql))
pick <- function(x, n) x[sample.int(nrow(x), min(n, nrow(x))), , drop = FALSE]
starts <- unique(rbind(pick(pool, 2000),
                       pick(pool[!is.na(pool$bank_m) & pool$bank_m <= 200, ],
                            500)))

# -- reference walk ------------------------------------------------------------
DBI::dbExecute(conn, paste(readLines(ref_sql), collapse = "\n"))
t0 <- proc.time()
ref <- do.call(rbind, lapply(seq_len(nrow(starts)), function(i) {
  r <- DBI::dbGetQuery(conn,
    "SELECT * FROM pg_temp.ch_dist_profile($1::integer, $2, $3::float8[], 'pick')",
    params = list(starts$blue_line_key[i], starts$downstream_route_measure[i],
                  paste0("{", q, "}")))
  data.frame(id_segment = starts$id_segment[i], ref_status = r$status,
             ref_m = as.numeric(r$dist_m), ref_lfid = as.numeric(r$large_lfid),
             ref_edge = as.integer(r$large_edge),
             ref_wbk = as.numeric(r$large_waterbody_key),
             ref_gap = as.numeric(r$max_entry_gap_m))
}))
ref_s <- (proc.time() - t0)[["elapsed"]]
cmp <- merge(starts, ref, by = "id_segment")
cmp$ref_m[cmp$ref_status != "found"] <- NA

DBI::dbWriteTable(conn, DBI::Id(schema = schema, table = "cmp"),
                  data.frame(id_segment = cmp$id_segment,
                             ref_lfid = cmp$ref_lfid,
                             ref_wbk = cmp$ref_wbk,
                             reach = pmax(cmp$centre_m, cmp$ref_m, 0,
                                          na.rm = TRUE) + 1),
                  overwrite = TRUE)
extra <- DBI::dbGetQuery(conn, sprintf(
  "SELECT c.id_segment,
     (SELECT min(ST_Distance(ST_StartPoint(o.geom), p.geom))
        FROM %s p WHERE p.waterbody_key = c.ref_wbk) AS straight_to_polygon_m,
     EXISTS (SELECT 1 FROM %s x
             WHERE x.linear_feature_id = c.ref_lfid) AS ref_in_table,
     EXISTS (SELECT 1 FROM %s t
             WHERE t.blue_line_key = t.watershed_key
               AND nlevel(t.localcode_ltree) > nlevel(t.wscode_ltree) + 1
               AND ST_DWithin(t.geom, o.geom, c.reach)
               AND FWA_Downstream(o.blue_line_key, o.downstream_route_measure,
                     o.wscode_ltree, o.localcode_ltree, t.blue_line_key,
                     t.downstream_route_measure, t.wscode_ltree,
                     t.localcode_ltree)) AS nested_code
   FROM %s.cmp c JOIN %s o USING (id_segment)",
  .frs_near_river_polygons(), tbl, tbl, schema, tbl))
cmp <- merge(cmp, extra, by = "id_segment")

cmp$diff_m <- cmp$bank_m - cmp$ref_m
cmp$centre_diff_m <- cmp$centre_m - cmp$ref_m
cmp$subtracted_m <- cmp$centre_m - cmp$bank_m
cmp$jumps_m <- cmp$centre_m - cmp$nojump_m
cmp$class <- with(cmp, ifelse(
  is.na(bank_m) & is.na(ref_m), "agree",
  ifelse(!is.na(diff_m) & abs(diff_m) <= 1, "agree",
  ifelse(!is.na(centre_diff_m) & abs(centre_diff_m) <= 1, "bank",
  # The centreline walk is capped at the reach, so a bank distance just
  # inside it can have a centreline just past it.
  ifelse(!is.na(bank_m) & is.na(centre_m) & !is.na(ref_m) & ref_m > d_far &
           bank_m < ref_m, "bank",
  ifelse(is.na(bank_m) & !is.na(ref_m) & ref_m > d_far, "beyond",
  ifelse(!is.na(ref_m) & !ref_in_table, "truncation",
  ifelse(!is.na(ref_edge) & ref_edge %in% c(1400L, 1450L) &
           (is.na(bank_m) | bank_m > ref_m), "connector",
  ifelse(nested_code & !is.na(centre_diff_m) & centre_diff_m > 0,
         "nested_code",
  ifelse(!is.na(centre_diff_m) &
           abs(centre_diff_m) <= 2 * jumps_m + ref_gap + 1, "entry",
  # Jumps can carry a walk past the reach: without them it agrees.
  ifelse(is.na(bank_m) & !is.na(nojump_m) & !is.na(ref_m) &
           abs(nojump_m - ref_m) <= ref_gap + 1, "entry",
  ifelse(!is.na(bank_m) & is.na(ref_m), "ref_none",
         "unexplained"))))))))))))

summary <- as.data.frame(table(class = cmp$class), stringsAsFactors = FALSE)
summary$note <- ""
note <- function(cls, txt) summary$note[summary$class == cls] <<- txt
both <- cmp$class == "agree" & !is.na(cmp$bank_m)
note("agree", sprintf("max |residual| %.3f m over %d found by both",
                      max(c(0, abs(cmp$diff_m[both]))), sum(both)))
bk <- cmp$class == "bank"
# Independent of fresh's subtraction: a bank distance can never be shorter
# than the straight line from the segment's downstream end to the polygon.
below_bound <- bk & !is.na(cmp$straight_to_polygon_m) &
  cmp$bank_m < cmp$straight_to_polygon_m - 0.5
note("bank", sprintf(paste0(
  "subtracted mean %.1f m, max %.1f m; %d of %d with a polygon shorter ",
  "than the straight line to it"),
  mean(cmp$subtracted_m[bk], na.rm = TRUE),
  max(c(0, cmp$subtracted_m[bk]), na.rm = TRUE), sum(below_bound),
  sum(bk & !is.na(cmp$straight_to_polygon_m))))
en <- cmp$class == "entry"
note("entry", sprintf("centreline residual median %.1f m, max %.1f m",
                      stats::median(cmp$centre_diff_m[en], na.rm = TRUE),
                      max(c(0, abs(cmp$centre_diff_m[en])), na.rm = TRUE)))
nc <- cmp$class == "nested_code"
note("nested_code", sprintf("%d distinct targets, residual max %.1f m",
                            length(unique(cmp$ref_lfid[nc])),
                            max(c(0, cmp$centre_diff_m[nc]))))

stamp <- c(stamp,
  sprintf("starts %d, reference walk %.0f s", nrow(cmp), ref_s),
  utils::capture.output(print(summary, row.names = FALSE)))
writeLines(stamp, file.path(out_dir, paste0(tolower(wsg), "_stamp.txt")))
utils::write.csv(summary, file.path(out_dir, paste0(tolower(wsg),
  "_summary.csv")), row.names = FALSE)
utils::write.csv(cmp[order(cmp$class, cmp$id_segment), ],
  file.path(out_dir, paste0(tolower(wsg), "_compare.csv")), row.names = FALSE)
writeLines(stamp)

DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
DBI::dbDisconnect(conn)
