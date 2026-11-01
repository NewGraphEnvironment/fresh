# Code-check review, round 2 (#281, branch 281-frs-network-features-an-existence-mode-t)

## Checklist read

- `code-check-infra.md`: in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, with the `|` table rows skipped. No "Rules that stand alone" or Security heading names anything this diff uses.
- `code-check-r.md`: 9 sections read. They are: Postgres row order; `sprintf("%g")` in SQL; a `data-raw/` script must load the source tree; Rscript reads a script as it runs; `tryCatch()` nests its handlers; a database driver's value is not a base R type (integer64 from `::bigint`, relevant to `n_pairs`); `paste()` with a zero-length argument; `data.frame()` recycling against zero length; `ifelse()` with an all-NA test. The rest were not read. Round 1 covered the testthat, mock and `R CMD check` sections, and this fix does not touch tests.
- `code-check-spatial.md`: none re-read. The diff does no spatial work beyond `frs_db_query()` = `sf::st_read()`, and round 1 read the three relevant sections.
- `code-check-shell.md`: none read. The fix has no shell code.

## What I checked

- **The `ids_arrays` digest builds the arrays.** I ran a plan-only `EXPLAIN (VERBOSE)`, with no ANALYZE, on SALR, unscoped, which needs no temp table.
  - The `ids` digest's subquery outputs `a.id_segment, NULL::text[]`.
  - With `sum(cardinality(feature_ids))` it outputs `a.id_segment, array_agg(b.id_barrier) FILTER (...)`, and the top node computes `sum(cardinality(array_agg ...))`.
  - I found no other pruning: the ORDER BY keys and GROUP BY carry sortgroupref, so the sort runs in both digests. The `exists` digest reads its only column.
  - `n_pairs` counts non-NULL ids only. In SETN CH it equals the plan's join rows (4,829,028), and in CHWK CH the `distinct_sql` plan's (161,974). So "pairs" is accurate for these views.
- **The walks.tsv migration.** The first 161 lines, cut to 10 fields, are byte-identical to 757bca1's file. All 160 old rows carry `n_pairs = NA`, and all 208 rows have 11 fields.
- **Every figure, recomputed from walks.tsv and plans/*.json.** I split batches by `measured_utc`: 1 = 00:35:15-00:45:49, 2 = 00:52:33-01:11:29, 3 = 01:16:22-01:26:25, 4 = 01:49:47-01:57:38. Each walk has exactly two runs of each form within a batch.
  - All 12 rows of the README table reproduce: pairs, SQL means from batch 4, fn means from batch 2, and both ratio columns.
  - SQL saving is at most 15.0% (SETN CH). The end-to-end saving is at most 19.6% (SETN BT, 21.31 to 17.13 s).
  - `exists_sql` against `distinct_sql` in batch 1 runs 1.09 (SALR BT) to 14.67 (LFRA BT), which matches "1.1× to 15×".
  - CHWK CH timed: 6.10 s and 2.63 s. Plans: 11.42 s semi-join, 74.8 M rows removed, 14,347 segments, about 5,216 materialized rows per loop; the join returns 161,974 rows in 2.83 s from 8,585 admitted features, then a hash aggregate to 11,301.
  - SETN CH plan: join 37.88 s of 45.27 s; external-merge sort of 538,912 kB, which is 526.3 MiB.
  - The two `others_active = 1` rows match, as do the timeouts at 01:21 and 01:26, a single digest per walk across every form and batch, and NEWS's 1.00×-1.24× and 41 s against 50 s.
- **The script's form combinations.**
  - `ids_arrays` is accepted as the first form, and counts as an ids form for censoring.
  - `n_pairs` reaches `emit()` as NA from `timed_fn`, from the timeout path and from the skip row.
  - In EXPLAIN mode `walk_sql()` sends the bare walk, so an `ids` or `ids_arrays` plan builds the arrays.
  - `NF281_ALLOW_OTHERS` bypasses only the start refusal, and `others_active` is still recorded.
  - integer64 `n_pairs` goes through `is.na()` and `as.character()` with RPostgres's bit64 loaded, and the values in the log are correct.
- **The mocked suite:** `devtools::test(filter = "frs_network_features$")` gave FAIL 0, ERROR 0, PASS 140. The only database access was the plan-only EXPLAIN above.

## Findings

- **[prose, minor]** `research/fwa_downstream_walk.md:118`: "the exists mode is 1.00× to 1.24× faster end to end, rising with the number of segments reached." Per walk, the ratio does not rise with segments reached. Within each group, BT has the fewest segments but a higher ratio than ST: CHWK BT 10,092 segments at 1.100× against ST 10,818 at 1.084×; LFRA BT 42,292 at 1.190× against ST 44,538 at 1.184×; SETN BT 163,588 at 1.244× against ST 174,987 at 1.217×. The largest ratio, 1.24×, is SETN BT, the smallest SETN walk. Two readings do hold: the rise across groups (SALR, then CHWK, LFRA, SETN), and the absolute saving in seconds, which is monotone in segments over all 12 walks (0.00 up to 9.57 s). NEWS line 8's "The saving grows with the number of segments reached" is true read as seconds. Suggested wording: "rising from group to group with the segments reached".

- **[prose, minor, working notes]** `planning/active/findings.md:56-58` still carry the superseded figures that the round-1 disposition (lines 63-67) and the log correct:
  - "1.1x (SALR) to 13x (LFRA BT) slower than the array walk", where the corrected figure is 15× against the join;
  - "SQL alone: up to 1.17x", where it is 1.18× in batch 4;
  - "Sort spill in SETN not checked … the EXPLAIN was not run", where batch 4's EXPLAIN checked it.

  These bullets become the archive's evidence record, so they read as current findings unless they are marked superseded or edited.

No bugs found. The round-1 fix holds: the arrays are now built in the SQL-level timings, and every figure in the README, NEWS and research reproduces from the batch it names.
