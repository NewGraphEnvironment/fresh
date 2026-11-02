#!/usr/bin/env Rscript
# Audit the exposure fresh#293 describes: a custom-AOI job deletes whole
# watershed groups from a SHARED habitat or near_river table and reinserts only
# the AOI's own rows, so the groups the AOI touches lose every row outside it.
#
#   Rscript data-raw/audit_habitat_293.R [out_dir]
#
# Defaults the directory to data-raw/logs/habitat_293/, writing tables.csv,
# summary.csv and ratio.csv into it. **Only summary.csv and ratio.csv are
# committed.** tables.csv names every schema on the instance it ran against,
# and this is a public repository; the summary carries every number the
# findings cite, and this script re-derives the detail on demand.
#
# Two questions, because only the first can show damage and only the second
# bounds how large it would be.
#
#   tables.csv — every habitat-shaped and near_river-shaped table on
#     the instance, with its row / group / species counts, whether it carries
#     `linear_feature_id`, and how many of its rows hold NULL for it. A
#     SINGLE-group table cannot have suffered the loss: the whole-group delete
#     and the job's reinsert cover the same ground. A MULTI-group table is the
#     one to read, and `seg_ratio` is the signature — per group, the distinct
#     `id_segment` count against the Freshwater Atlas segment count for that
#     group. A group sitting far below its siblings has rows no run put back.
#     `n_null_lfid` is the backfill cost of #293's migration for that table:
#     every such row is one no partition delete can ever address.
#     `seg_ratio` is a signature for a HABITAT table only. On a near_river
#     table a low ratio is the expected shape — only segments that found a
#     river within the pair's distance get a row at all — so it says nothing
#     there about damage.
#
#   summary.csv — tables.csv aggregated by shape, with no schema names: how
#     many tables, how many shared across groups, how many carry the column,
#     and the rows the migration would have to backfill. This is the committed
#     evidence for the counts the findings quote.
#
#   ratio.csv — the ratio the issue left unmeasured, from the FWA
#     alone and so independent of any habitat table: for the documented
#     custom-AOI example (`man/frs_habitat.Rd`, wscode_ltree <@
#     '100.190442.999098'), the segments INSIDE the AOI against the segments of
#     every watershed group the AOI touches. Rows deleted and not replaced are
#     the difference; the ratio is how many rows one such job would lose per
#     row it writes.
#
# Read `seg_ratio` with research/id_segment_identity.md in hand. A group below
# its siblings is evidence of a loss, not proof of this one: an interrupted run
# or a group never completed looks the same. What distinguishes #293 is a table
# that is shared across groups at all, which is why the table list reports the
# group count for every candidate rather than only the suspicious ones.

suppressMessages(pkgload::load_all(quiet = TRUE))

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[[1]] else "data-raw/logs/habitat_293"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

conn <- frs_db_conn()
# on.exit() at a script's top level registers on the global environment and
# never fires (code-check-r.md).
withr::defer(DBI::dbDisconnect(conn), envir = globalenv())
# CLAUDE.md: both timeouts on any long DB op.
invisible(DBI::dbExecute(conn, "SET statement_timeout = 900000"))
invisible(DBI::dbExecute(conn, "SET lock_timeout = 60000"))

# -- Candidate tables, by the columns that identify each shape ---------------
# Shape, not name: link writes <schema>.streams_habitat and fresh's examples
# write fresh.streams_habitat, and either may be called something else. Only
# ordinary tables ('r', 'p'): a view over one is not a write target.
cand <- DBI::dbGetQuery(conn, "
  WITH cols AS (
    SELECT n.nspname AS sch, c.relname AS tbl, a.attname AS col
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid
    WHERE c.relkind IN ('r', 'p')
      AND a.attnum > 0 AND NOT a.attisdropped
      AND n.nspname NOT LIKE 'pg_%' AND n.nspname <> 'information_schema'
  )
  SELECT sch, tbl,
    bool_or(col = 'linear_feature_id') AS has_lfid,
    CASE
      WHEN bool_and(col <> 'species_code') THEN 'near_river'
      ELSE 'habitat'
    END AS shape
  FROM cols
  GROUP BY sch, tbl
  HAVING bool_or(col = 'id_segment')
     AND bool_or(col = 'watershed_group_code')
     AND (
       (bool_or(col = 'species_code') AND bool_or(col = 'accessible')
          AND bool_or(col = 'spawning') AND bool_or(col = 'rearing'))
       OR
       (bool_or(col = 'measure') AND bool_or(col = 'threshold')
          AND bool_or(col = 'distance_max') AND bool_or(col = 'dist_m'))
     )
  ORDER BY sch, tbl")

cat("Candidate tables: ", nrow(cand), " (",
    sum(cand$shape == "habitat"), " habitat, ",
    sum(cand$shape == "near_river"), " near_river)\n", sep = "")

# FWA segments per watershed group, the denominator for seg_ratio. Taken once:
# it is a province-wide aggregate and the reason this script sets a timeout.
fwa <- DBI::dbGetQuery(conn, "
  SELECT watershed_group_code AS wsg, count(*)::bigint AS n_fwa
  FROM whse_basemapping.fwa_stream_networks_sp
  GROUP BY 1")

# -- Per-table counts --------------------------------------------------------
rows <- vector("list", nrow(cand))
for (i in seq_len(nrow(cand))) {
  t <- paste0(cand$sch[i], ".", cand$tbl[i])
  # DBI::dbQuoteIdentifier() on each part: a schema or table name may hold
  # anything, and .frs_validate_identifier() would reject names this
  # enumeration legitimately found.
  q <- paste0(
    DBI::dbQuoteIdentifier(conn, cand$sch[i]), ".",
    DBI::dbQuoteIdentifier(conn, cand$tbl[i]))
  agg <- tryCatch(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::bigint AS n_rows,
            count(DISTINCT watershed_group_code)::int AS n_groups,
            %s AS n_species,
            %s AS n_null_lfid
     FROM %s",
    if (cand$shape[i] == "habitat") {
      "count(DISTINCT species_code)::int"
    } else {
      "NULL::int"
    },
    if (cand$has_lfid[i]) {
      "count(*) FILTER (WHERE linear_feature_id IS NULL)::bigint"
    } else {
      "count(*)::bigint"  # no column at all: every row needs the backfill
    },
    q)), error = function(e) {
      cat("  SKIP ", t, ": ", conditionMessage(e), "\n", sep = "")
      NULL
    })
  if (is.null(agg)) next

  # seg_ratio, only where it can mean something: one group cannot sit below
  # its siblings. Reported as the worst group's ratio and the best group's, so
  # a spread names the suspicious table without a row per group.
  seg <- if (agg$n_groups > 1) {
    per <- tryCatch(DBI::dbGetQuery(conn, sprintf(
      "SELECT watershed_group_code AS wsg,
              count(DISTINCT id_segment)::bigint AS n_seg
       FROM %s GROUP BY 1", q)), error = function(e) NULL)
    if (is.null(per)) {
      c(NA_real_, NA_real_)
    } else {
      m <- merge(per, fwa, by = "wsg")
      r <- if (nrow(m) == 0) NA_real_ else m$n_seg / m$n_fwa
      c(min(r), max(r))
    }
  } else {
    c(NA_real_, NA_real_)
  }

  rows[[i]] <- data.frame(
    table = t, shape = cand$shape[i], has_lfid = cand$has_lfid[i],
    n_rows = agg$n_rows, n_groups = agg$n_groups, n_species = agg$n_species,
    n_null_lfid = agg$n_null_lfid,
    seg_ratio_min = seg[[1]], seg_ratio_max = seg[[2]],
    stringsAsFactors = FALSE)
}
tables <- do.call(rbind, rows)

out_tables <- file.path(out_dir, "tables.csv")
utils::write.csv(tables, out_tables, row.names = FALSE)
cat("\nWrote ", out_tables, " (not committed: it names every schema)\n",
    sep = "")

# The committed aggregate. One row per shape, no schema names.
summary_rows <- lapply(split(tables, tables$shape), function(d) {
  sh <- d[d$n_groups > 1, , drop = FALSE]
  data.frame(
    shape = d$shape[[1]],
    n_tables = nrow(d),
    n_multi_group = nrow(sh),
    n_with_lfid = sum(d$has_lfid),
    groups_max = max(d$n_groups),
    n_rows = sum(d$n_rows),
    n_null_lfid = sum(d$n_null_lfid),
    seg_ratio_min = if (nrow(sh) == 0) NA_real_ else
      suppressWarnings(min(sh$seg_ratio_min, na.rm = TRUE)),
    stringsAsFactors = FALSE)
})
summ <- do.call(rbind, summary_rows)
out_summary <- file.path(out_dir, "summary.csv")
utils::write.csv(summ, out_summary, row.names = FALSE)
cat("Wrote ", out_summary, "\n", sep = "")
print(summ)

cat("\nShared (multi-group) tables, the only ones exposed: ",
    sum(tables$n_groups > 1), " of ", nrow(tables), "\n", sep = "")

# -- The ratio the issue left unmeasured -------------------------------------
# From the FWA alone: segments inside the documented AOI, against every
# segment of every group the AOI touches. The AOI predicate is the one in
# man/frs_habitat.Rd, so the number is about the shipped example.
aoi <- "wscode_ltree <@ '100.190442.999098'::ltree"
ratio <- DBI::dbGetQuery(conn, sprintf("
  WITH inside AS (
    SELECT linear_feature_id, watershed_group_code
    FROM whse_basemapping.fwa_stream_networks_sp WHERE %s
  ),
  groups AS (SELECT DISTINCT watershed_group_code FROM inside)
  SELECT (SELECT count(*)::bigint FROM inside) AS n_inside,
         (SELECT count(*)::bigint FROM whse_basemapping.fwa_stream_networks_sp n
            JOIN groups g USING (watershed_group_code)) AS n_groups_total,
         (SELECT count(*)::int FROM groups) AS n_groups,
         (SELECT string_agg(watershed_group_code, ' ' ORDER BY
            watershed_group_code) FROM groups) AS groups", aoi))
ratio$n_lost <- ratio$n_groups_total - ratio$n_inside
ratio$lost_per_written <- ratio$n_lost / ratio$n_inside
ratio$aoi <- aoi

out_ratio <- file.path(out_dir, "ratio.csv")
utils::write.csv(ratio, out_ratio, row.names = FALSE)
cat("\nWrote ", out_ratio, "\n", sep = "")
print(ratio)
cat("\nOne custom-AOI job over the documented AOI would delete ",
    format(ratio$n_lost, big.mark = ","),
    " rows it does not put back, per species, for ",
    format(ratio$n_inside, big.mark = ","), " it writes (",
    round(ratio$lost_per_written, 1), " lost per row written).\n", sep = "")
