#!/usr/bin/env Rscript
# Measure what fresh#294 is really about: on a blue line that spans two
# watershed groups, what a second group's job leaves in a shared to_barriers
# table for the first group.
#
#   Rscript data-raw/barrier_span_294.R [out_dir]
#
# Writes lines.csv (one row per sampled line) and summary.csv into out_dir,
# default data-raw/logs/barrier_span_294/. Connects with frs_db_conn(), so
# the database is whatever the PG* variables name; it reads the Freshwater
# Atlas and writes only session temp tables.
#
# Why this shape. frs_habitat() finds gradient barriers with the multiclass
# arm of frs_break_find(), which takes the blue lines from the job's extract
# and then reads EVERY segment of those lines from fwa_stream_networks_sp --
# no watershed-group filter. So a job's barriers cover the whole line, and the
# old delete by blue_line_key matched exactly what its insert wrote back:
# nothing was lost. What differs between two groups' jobs is the gradient
# classes, which come from each group's species thresholds. The last job to
# run on a line therefore owned the first group's barriers too, at its own
# classes. This script counts how often that changes the first group's rows.
#
# For each sampled line (mainstem, blue_line_key = watershed_key, as
# frs_habitat()'s default blk_filter samples; exactly two groups whose
# threshold sets differ), it runs frs_break_find() from each group's extract
# with that group's thresholds -- built the way frs_habitat() builds them --
# and compares, inside group A, job A's own barriers with job B's.
#
#   a_own                 job A's barriers in group A
#   a_rows_wrong_after_b  positions in group A where job B's barrier is
#                         missing, extra, or at a different class
#   unmatched             barriers of either job no FWA segment contains under
#                         .frs_enrich_breaks()'s [downstream, upstream) rule

pkgload::load_all(quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[[1]] else
  file.path("data-raw", "logs", "barrier_span_294")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

conn <- frs_db_conn()
DBI::dbExecute(conn, "SET statement_timeout = 300000")

params <- frs_params(csv = system.file("extdata",
  "parameters_habitat_thresholds.csv", package = "fresh"))
params_fresh <- utils::read.csv(system.file("extdata", "parameters_fresh.csv",
  package = "fresh"), stringsAsFactors = FALSE)

# The thresholds frs_habitat() derives for a group's job when species is NULL.
thr <- function(w) {
  sp <- frs_wsg_species(w)
  sp <- unique(sp$species_code[sp$species_code %in% names(params) &
                                 sp$species_code %in% params_fresh$species_code])
  a <- params_fresh$access_gradient_max[params_fresh$species_code %in% sp]
  e <- unlist(lapply(params[sp], function(p) {
    c(p$spawn_gradient_max, p$rear_gradient_max)
  }), use.names = FALSE)
  t <- sort(unique(c(a[!is.na(a)], e[!is.na(e)])))
  names(t) <- as.character(as.integer(round(t * 10000)))
  t
}

span <- DBI::dbGetQuery(conn, "
  SELECT blue_line_key,
         array_to_string(array_agg(DISTINCT watershed_group_code
                                   ORDER BY watershed_group_code), ',') AS wsgs,
         round(sum(length_metre)) AS len
  FROM whse_basemapping.fwa_stream_networks_sp
  WHERE blue_line_key = watershed_key AND edge_type <> 6010
  GROUP BY blue_line_key
  HAVING count(DISTINCT watershed_group_code) > 1")
span$n_groups <- lengths(strsplit(span$wsgs, ","))
span$differ <- vapply(strsplit(span$wsgs, ","), function(g) {
  length(unique(lapply(g, thr))) > 1
}, logical(1))

job <- function(blk, w, tag) {
  out <- paste0("pg_temp.b294_brk_", tag)
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.b294_ext")
  DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE b294_ext AS
     SELECT * FROM whse_basemapping.fwa_stream_networks_sp
     WHERE watershed_group_code = %s AND blue_line_key = %d",
    DBI::dbQuoteString(conn, w), as.integer(blk)))
  frs_break_find(conn, "pg_temp.b294_ext", attribute = "gradient",
                 classes = thr(w), to = out)
  DBI::dbExecute(conn, sprintf(
    "ALTER TABLE %s ADD COLUMN wsg text, ADD COLUMN lfid bigint", out))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s b SET wsg = f.watershed_group_code, lfid = f.linear_feature_id
     FROM whse_basemapping.fwa_stream_networks_sp f
     WHERE b.blue_line_key = f.blue_line_key
       AND b.downstream_route_measure >= f.downstream_route_measure
       AND b.downstream_route_measure < f.upstream_route_measure", out))
}

# Twelve two-group lines over 3 km whose groups' thresholds differ, shortest
# first: deterministic, and enough to show whether the effect is common.
pick <- span[span$n_groups == 2 & span$differ & span$len > 3000, ]
pick <- pick[order(pick$len, pick$blue_line_key), ][seq_len(min(12, nrow(pick))), ]

lines <- do.call(rbind, lapply(seq_len(nrow(pick)), function(i) {
  g <- strsplit(pick$wsgs[i], ",")[[1]]
  blk <- pick$blue_line_key[i]
  job(blk, g[1], "a")
  job(blk, g[2], "b")
  q <- DBI::dbGetQuery(conn, sprintf("
    WITH a AS (SELECT downstream_route_measure m, gradient_class c
               FROM pg_temp.b294_brk_a WHERE wsg = %1$s),
         b AS (SELECT downstream_route_measure m, gradient_class c
               FROM pg_temp.b294_brk_b WHERE wsg = %1$s)
    SELECT (SELECT count(*) FROM a)::int AS a_own,
           (SELECT count(*) FROM a FULL JOIN b USING (m)
             WHERE a.c IS DISTINCT FROM b.c)::int AS a_rows_wrong_after_b,
           ((SELECT count(*) FROM pg_temp.b294_brk_a WHERE lfid IS NULL) +
            (SELECT count(*) FROM pg_temp.b294_brk_b WHERE lfid IS NULL))::int
             AS unmatched", DBI::dbQuoteString(conn, g[1])))
  data.frame(blue_line_key = blk, wsgs = pick$wsgs[i], len_m = pick$len[i], q)
}))

summary <- data.frame(
  measured_utc = format(Sys.time(), "%Y-%m-%dT%H:%MZ", tz = "UTC"),
  mainstem_lines_spanning_groups = nrow(span),
  of_which_thresholds_differ = sum(span$differ),
  lines_sampled = nrow(lines),
  lines_where_second_job_changes_first_group = sum(lines$a_rows_wrong_after_b > 0),
  first_group_barriers_sampled = sum(lines$a_own),
  first_group_positions_changed = sum(lines$a_rows_wrong_after_b),
  barriers_unmatched = sum(lines$unmatched))

utils::write.csv(lines, file.path(out_dir, "lines.csv"), row.names = FALSE)
utils::write.csv(summary, file.path(out_dir, "summary.csv"), row.names = FALSE)
print(lines)
print(t(summary))
DBI::dbDisconnect(conn)
