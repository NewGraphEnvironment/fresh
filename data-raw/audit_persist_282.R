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
# group, under frs_extract()'s own guards, whose linear_feature_id is absent
# from the table. A group showing a shortfall has rows that no run put back;
# re-running that group in WSG mode is the repair, because the whole-group
# delete is self-healing.
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
# n_missing is a set difference, not a difference of two counts. The table can
# hold a linear_feature_id outside the guarded FWA set -- a placeholder or
# unmapped segment written by some other pass -- and under subtraction each one
# cancels a segment that really is absent, so the column that decides whether
# production data is damaged could read 0 with rows missing. Driving from
# `groups` rather than from `fwa` also keeps a group that is in the table but
# has no guarded FWA rows, which a LEFT JOIN the other way round dropped.
res <- DBI::dbGetQuery(conn, sprintf(
  "WITH groups AS (
     SELECT DISTINCT watershed_group_code AS wsg FROM %1$s
   ),
   fwa AS (
     SELECT s.watershed_group_code AS wsg,
            count(DISTINCT s.linear_feature_id) AS n_fwa
     FROM whse_basemapping.fwa_stream_networks_sp s
     WHERE %2$s
       AND s.watershed_group_code IN (SELECT wsg FROM groups)
     GROUP BY 1
   ),
   present AS (
     SELECT watershed_group_code AS wsg,
            count(DISTINCT linear_feature_id) AS n_present
     FROM %1$s GROUP BY 1
   ),
   missing AS (
     SELECT s.watershed_group_code AS wsg,
            count(DISTINCT s.linear_feature_id) AS n_missing
     FROM whse_basemapping.fwa_stream_networks_sp s
     WHERE %2$s
       AND s.watershed_group_code IN (SELECT wsg FROM groups)
       AND NOT EXISTS (
         SELECT 1 FROM %1$s t
          WHERE t.linear_feature_id = s.linear_feature_id
            AND t.watershed_group_code = s.watershed_group_code)
     GROUP BY 1
   )
   SELECT g.wsg AS watershed_group_code,
          coalesce(f.n_fwa, 0)::bigint AS n_fwa_segments,
          coalesce(p.n_present, 0)::bigint AS n_in_table,
          coalesce(m.n_missing, 0)::bigint AS n_missing
   FROM groups g
   LEFT JOIN fwa f USING (wsg)
   LEFT JOIN present p USING (wsg)
   LEFT JOIN missing m USING (wsg)
   ORDER BY 4 DESC, 1", tbl, guards))

res$n_fwa_segments <- as.numeric(res$n_fwa_segments)
res$n_in_table <- as.numeric(res$n_in_table)
res$n_missing <- as.numeric(res$n_missing)

cat("Audited:", tbl, "at", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Groups in table:", nrow(res), "\n")
cat("Groups with a shortfall:", sum(res$n_missing > 0), "\n")
cat("Segments missing in total:", sum(pmax(res$n_missing, 0)), "\n\n")
print(utils::head(res[res$n_missing > 0, , drop = FALSE], 20))

utils::write.csv(res, out, row.names = FALSE, na = "")
cat("\nWrote", out, "\n")
