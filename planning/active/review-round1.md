# Code-check review, round 1 (#272, branch diff c408b468...HEAD)

## Checklist read

- `code-check-infra.md` (38 KB): in full. Applicable: "Function-as-join-predicate", "View vs. real table changes the planner's join direction", "Set statement_timeout + lock_timeout", "Benchmark Postgres with a SELECT on an idle server, settings interleaved".
- `code-check.md` (331 KB): the prose of all 14 H3s under `## Mechanisms`, table rows skipped. None of the 23 H3s under "Rules that stand alone", Security or Spreadsheets/PDFs read (none names a tool or shape this diff uses).
- `code-check-r.md` (178 KB): 14 of 111 headings read in full: Postgres row order; `::text` spelling; driver values (`pq__text`, integer64); `expect_false(identical())`; `function(...)` mocks; `pkg::` in tests; tests under R CMD check; data-raw loads the source tree; `system2(stdout = TRUE)`; `tryCatch()` nesting; `information_schema` lookups; tests that silently do not run; `skip_if_not()` scope; testthat error vs failed. 97 not read.
- `code-check-spatial.md` (156 KB): 1 of 93 headings read ("A GDAL failure partway through `sf::st_read()`", not applicable: `frs_db_query()` goes through sf's DBI method, and the call is unchanged). 92 not read; the FWA headings in the index (route measures, main-flow edge types, main-stem ends, GNIS names) concern nothing this diff does.
- `code-check-shell.md` (125 KB): 0 of 67 read. The diff has no shell code; the one subprocess (`system2("git", "show")` in data-raw) is covered by the R heading above.

## What was checked, with probes

- **Prefilter is a superset of `fwa_downstream()`'s reach.** Read both bodies from the local fwapg (`pg_proc`). Both branches (`include_equivalents` TRUE/FALSE) are criterion 1 (`blue_line_key_a = blue_line_key_b AND ...`) OR criterion 2 (`wscode_ltree_a <@ wscode_ltree_b AND ...`). `subpath(ws_a, 0, k)` for k in 1..nlevel is exactly the ancestor-or-equal set, so the two arms admit everything either criterion can return. The `tolerance` only narrows criterion 1. Holds.
- **"No FWA blue line carries two wscodes"**: 0 rows (`GROUP BY blue_line_key HAVING count(DISTINCT wscode_ltree) > 1`), and 0 NULL wscodes in `fwa_stream_networks_sp`. Holds.
- **Mutation proof of the local live test** (copies under the scratchpad, `pkgload::load_all(copy)`, `NOT_CRAN=true testthat::test_file`, `failed` and `error` both read; a deparse of `.frs_walk_prefilter` was printed to show each patch took):
  - control: 19 expectations, 0 failed, 0 error
  - ancestor arm reduced to equality (`SELECT DISTINCT s.ws`): 2 failed
  - blue-line arm deleted: 6 failed
  Both arms are seen by the test.
- Mock unit tests (`test-frs_network_features.R`) on the control copy: 30 blocks, 0 failed, 0 error, 0 skipped.
- **Plan on a dense feature table**: `EXPLAIN` of the prefilter against all of `fwa_stream_networks_sp` with an LSKE temp table uses a BitmapOr of the GiST `wscode` index and the btree `blue_line_key` index. No seq scan.
- **walks.tsv against NEWS / README / research**: recomputed means per group, view and form. All table values, the "0.34 to 8.4 s", "0.07 to 0.7 s", "0.85-4.5 to 0.17-1.7 s", the "> N×" ratios and "7.9× (LSKE) to 33× (CHWK)" match. `d_set` takes exactly one value per (group, view) across every form that ran (12 of 12). Every CH and BT rep-1 `old` row is a timeout.
- link's callers (`lnk_pipeline_access()`, `lnk_access()`) pass `aoi` with downstream and already build an indexed table. The scoped path copies it again, which is redundant but correct. link's tests mock `frs_network_features()` whole (`.package = "fresh"`), so the new `.frs_db_execute` calls cannot reach them.
- The DROP is registered before the CREATE, a failed DDL is rethrown with its class and `$parent`, the ORDER BY tie key is `b.<feature_id_col>`, `unique()` keeps a key column that doubles as the id from being projected twice, and an empty AOI gives `= ANY('{}')`, so no rows, as before. No defect found.

## Findings

- **[fragile, low] tests/testthat/test-frs_network_features-local.R:9-13 (and research/fwa_downstream_walk.md, "Prefiltering the feature side")**: the comment says "Its streams reach the Fraser (wscode `100`)". SKGT's streams are `970.*` (6,914 segments, the Skagit). One SKGT segment carries a Fraser code: `linear_feature_id` 868144510, edge type 1450, 30 m, wscode `100.111269`. Every candidate the ancestor arm admits beyond SKGT's own codes sits on `100.*` (6,980 network segments, 0 on any other top-level code). So the test's ancestor-arm coverage (its `expect_gt(ancestor n, 0)`, and the 2-failure mutation above) rests on that one 30 m segment. The direction is safe: if a future FWA load recodes it, the premise assertion goes red rather than passing vacuously. But the comment misdescribes why SKGT works, and whoever picks a replacement group will be misled. Suggest saying it plainly ("one 30 m SKGT segment, 868144510, is coded on a Fraser tributary, 100.111269; only it reaches codes outside SKGT's own") and recording the count beside the 22-of-40,495 figure.
- **[fragile, low] data-raw/network_features_prefilter.R:197-199, data-raw/logs/network_features_272/walks.tsv**: the skipped second `old` run is emitted with `timed_out = TRUE`. The TSV therefore records 16 timeouts for CH and BT (2 per walk), of which only 8 ran (rep 1). The README says the skip shows in `d_set` ("skipped: …"), but anyone counting the `timed_out` column, the obvious reading, double-counts censored runs. Emit `timed_out = NA` (or FALSE) for the skipped row, and fix the 8 committed rows to match. The log is evidence, so the fix belongs in the data as well as the script.

Not defects (noted, no change asked):
- The README and research say the temp table costs "0.07-0.14 s for 7-14 k segments". The measured maximum is 0.146 s (CHWK CH), which rounds to 0.15.
- The test comment ("changed no answer pair in VICT, LKEL or UPET") and the research doc ("0 in CHWK, SAHD and UPET … 1.00 M of 1.05 M in UTRE") cite different group lists for the arm-ablation result, and neither names the probe that produced it. The research header points to the archive's probes, so this is traceable once archived.

Verdict: no bug or security issue in the shipped code. Two low-severity accuracy issues in the test premise comment and the committed evidence log.
