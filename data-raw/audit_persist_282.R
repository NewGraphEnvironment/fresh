#!/usr/bin/env Rscript
# Audit a persisted to_streams for segments missing relative to the Freshwater
# Atlas — the damage shape fresh#282 describes, where a custom-AOI job deleted
# rows another group's run had written and inserted only its own.
#
#   Rscript data-raw/audit_persist_282.R [table] [results.csv]
#
# Defaults to fresh.streams and data-raw/audit_persist_282_results.csv.
#
# Per watershed group present in the table, counts the FWA segments for that
# group whose linear_feature_id is absent from the table. A group showing a
# shortfall has rows that no run put back; re-running that group in WSG mode
# with no AOI is the repair, because the whole-group delete is self-healing.
#
# Two reference sets, because which one is right depends on who wrote the
# table, and reporting one would decide that for the reader:
#
#   n_missing_all      — against every FWA segment in the group. This is what
#                        CURRENT code writes: frs_habitat() extracts through
#                        frs_extract(), which applies no guards at all (only
#                        the AOI predicate and any `where`), so a run writes
#                        placeholder and unmapped segments too.
#   n_missing_guarded  — against the segments passing .frs_stream_guards()
#                        (placeholder 999 wscode, NULL localcode). This is
#                        what the LEGACY fresh.streams holds: measured, 0 of
#                        its rows fail those guards, so it was written by a
#                        pass that filtered.
#
# Read the pair, not either alone. A shortfall in n_missing_all that vanishes
# in n_missing_guarded is a filter, not a loss. An earlier version of this
# script reported only the guarded set and attributed the guards to
# frs_extract(), which applies none — so on a table built by current code it
# would have called a real loss of placeholder segments clean.
#
# Read the result with fresh#282's Phase 0 measurement in hand: a job built by
# current code numbers its base segments with linear_feature_id, while the
# table as it stands is numbered 1..n per group, so the two id spaces do not
# overlap and the broken delete removes nothing there. A shortfall on such a
# table is therefore evidence of something else — an interrupted run, a group
# never completed — not of #282. On a table built by current code it is #282.

suppressMessages(pkgload::load_all(quiet = TRUE))

args <- commandArgs(trailingOnly = TRUE)
tbl <- if (length(args) >= 1) args[[1]] else "fresh.streams"
out <- if (length(args) >= 2) args[[2]] else
  "data-raw/audit_persist_282_results.csv"

conn <- frs_db_conn()
# on.exit() at a script's top level registers on the global environment and
# never fires (code-check-r.md), and the column check below can stop() with
# the connection open.
withr::defer(DBI::dbDisconnect(conn), envir = globalenv())
# CLAUDE.md: both timeouts on any long DB op.
DBI::dbExecute(conn, "SET statement_timeout = 900000")
DBI::dbExecute(conn, "SET lock_timeout = 60000")

cols <- DBI::dbGetQuery(conn, sprintf(
  "SELECT a.attname AS col FROM pg_attribute a
    WHERE a.attrelid = %s::regclass AND a.attnum > 0 AND NOT a.attisdropped",
  .frs_quote_string(tbl)))$col
for (needed in c("linear_feature_id", "watershed_group_code")) {
  if (!needed %in% cols) {
    stop(sprintf("%s has no %s column, so it cannot be audited this way.",
                 tbl, needed), call. = FALSE)
  }
}

guards <- paste(.frs_stream_guards("s"), collapse = " AND ")
# Every n_missing is a set difference, not a difference of two counts: the
# table can hold a linear_feature_id outside whichever reference set is in
# question, and under subtraction each one cancels a segment that really is
# absent, so the column that decides whether production data is damaged could
# read 0 with rows missing. Driving from `groups` rather than from `fwa` also
# keeps a group that is in the table but has no FWA rows under the reference
# set, which a LEFT JOIN the other way round dropped. A NULL watershed group in
# the table cannot be joined on at all, so it is counted separately and
# reported rather than printed as a row of zeros.
res <- DBI::dbGetQuery(conn, sprintf(
  "WITH groups AS (
     SELECT DISTINCT watershed_group_code AS wsg FROM %1$s
      WHERE watershed_group_code IS NOT NULL
   ),
   fwa AS (
     SELECT s.watershed_group_code AS wsg,
            count(DISTINCT s.linear_feature_id) AS n_all,
            count(DISTINCT s.linear_feature_id)
              FILTER (WHERE %2$s) AS n_guarded
     FROM whse_basemapping.fwa_stream_networks_sp s
     WHERE s.watershed_group_code IN (SELECT wsg FROM groups)
     GROUP BY 1
   ),
   present AS (
     SELECT watershed_group_code AS wsg,
            count(DISTINCT linear_feature_id) AS n_present
     FROM %1$s WHERE watershed_group_code IS NOT NULL GROUP BY 1
   ),
   missing AS (
     SELECT s.watershed_group_code AS wsg,
            count(DISTINCT s.linear_feature_id) AS n_missing_all,
            count(DISTINCT s.linear_feature_id)
              FILTER (WHERE %2$s) AS n_missing_guarded
     FROM whse_basemapping.fwa_stream_networks_sp s
     WHERE s.watershed_group_code IN (SELECT wsg FROM groups)
       AND NOT EXISTS (
         SELECT 1 FROM %1$s t
          WHERE t.linear_feature_id = s.linear_feature_id
            AND t.watershed_group_code = s.watershed_group_code)
     GROUP BY 1
   )
   SELECT g.wsg AS watershed_group_code,
          coalesce(f.n_all, 0)::bigint AS n_fwa_all,
          coalesce(f.n_guarded, 0)::bigint AS n_fwa_guarded,
          coalesce(p.n_present, 0)::bigint AS n_in_table,
          coalesce(m.n_missing_all, 0)::bigint AS n_missing_all,
          coalesce(m.n_missing_guarded, 0)::bigint AS n_missing_guarded
   FROM groups g
   LEFT JOIN fwa f USING (wsg)
   LEFT JOIN present p USING (wsg)
   LEFT JOIN missing m USING (wsg)
   ORDER BY 5 DESC, 1", tbl, guards))

for (col in c("n_fwa_all", "n_fwa_guarded", "n_in_table",
              "n_missing_all", "n_missing_guarded")) {
  res[[col]] <- as.numeric(res[[col]])
}

# A NULL watershed group cannot be joined to FWA at all, so it is reported
# rather than shown as a row of zeros.
n_null_wsg <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS n FROM %s WHERE watershed_group_code IS NULL",
  tbl))$n

cat("Audited:", tbl, "at", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Groups in table:", nrow(res), "\n")
cat("Rows with a NULL watershed group (not auditable):", n_null_wsg, "\n")
cat("Against every FWA segment  — groups short:",
    sum(res$n_missing_all > 0), " segments:", sum(res$n_missing_all), "\n")
cat("Against guarded segments   — groups short:",
    sum(res$n_missing_guarded > 0), " segments:",
    sum(res$n_missing_guarded), "\n\n")
print(utils::head(
  res[res$n_missing_all > 0, , drop = FALSE], 20))

utils::write.csv(res, out, row.names = FALSE, na = "")
cat("\nWrote", out, "\n")
