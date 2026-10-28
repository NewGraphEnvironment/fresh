# Code-check review, round 2 (#272, branch diff c408b468...HEAD at 18d36bc)

## Checklist read

- `code-check-infra.md` (38 KB): in full. Applicable: "Function-as-join-predicate", "View vs. real table changes the planner's join direction", "Set `statement_timeout` + `lock_timeout`", "Benchmark Postgres with a SELECT on an idle server", "`pkill` does NOT cancel its Postgres query".
- `code-check.md` (331 KB): the prose of all 14 H3s under `## Mechanisms` (table rows and evidence blocks skipped). None of the H3s under "Rules that stand alone", Security or Spreadsheets/PDFs read; none names a tool or shape this diff uses.
- `code-check-r.md` (178 KB): 13 headings read in full: Postgres row order; `::text` spelling; driver values (`pq__text`); `information_schema` lookups; `function(...)` mocks; `data-raw/` loads the source tree; `system2(stdout = TRUE)`; `on.exit()` at top level; `tryCatch()` nesting; tests under `R CMD check`; `pkg::` in tests; `sprintf("%g")` into SQL; `tempfile()` in the session tempdir. About 98 not read.
- `code-check-spatial.md` (156 KB): 0 headings read. The FWA headings in the index (route measures, main-flow edge types, main-stem ends, GNIS names) concern nothing this diff does, and it has no sf/terra/GDAL code beyond the unchanged `frs_db_query()`.
- `code-check-shell.md` (125 KB): 0 of 67 read. No shell code in the diff. (I did hit the "verification command can be shadowed" trap myself: `diff` here is a shell function wrapping `git diff --no-index --color-words`, which reported 0 changed lines between two different files. Re-run with `/usr/bin/diff`; the results below use that.)

## Round 1's fixes, checked

- **(b) `timed_out` on skipped runs: correct and complete.**
  - Script (`data-raw/network_features_prefilter.R:199`) now emits `timed_out = NA`; `emit()` writes `NA` for a length-1 NA. Header comment (lines 20-23) matches.
  - Every reader of `timed_out` was grepped (`git grep timed_out`, all tracked files). The only code reader is `if (r$timed_out) old_censored <- TRUE` (line 206). `r` there always comes from `timed_digest()`, which returns only TRUE or FALSE, so the NA never reaches an `if`. Nothing else reads the column.
  - TSV: `/usr/bin/diff` of 0e3e967's `walks.tsv` against HEAD's shows 16 lines (8 rows changed). Applying `$9 = "NA"` mechanically to every row whose `d_set` matches `skipped` in the 0e3e967 copy gives HEAD's file byte for byte (`cmp`: identical). So the hand edit touched exactly those 8 cells. All 57 lines have 13 fields, and the file ends in a newline.
  - Counts now: `old` rep 1 has 8 TRUE (every CH and BT walk) and 4 FALSE (anthropogenic); `old` rep 4 has 8 NA (all `skipped: …`) and 4 FALSE. That matches the README's "the 8 `TRUE` rows are the 8 runs that timed out".
  - Cosmetic only: the console line at `:187` still prints `timeout` for a skipped row, because `seconds` is NA. It is not in the log.
- **(a) SKGT comment: correct.** Probed `fwa_stream_networks_sp` for SKGT: 6,914 segments are on `970.*`, 20 on `999.*` placeholders (edge 1400), and 1 on `100.*`, which is `linear_feature_id` 868144510 (edge 1450, 30.4 m, wscode `100.111269`). Comment, findings and round 1's description agree. In the plain-join answer with the test's fixture, all 22 ancestor-only pairs come from that one segment (both `include_equivalents` values). Test line 106 ("features on the Fraser below SKGT") is consistent with that.
- **(c) DDL range 0.07-0.15 s: correct.** It appears in the log README, research and findings; no `0.07-0.14` / `0.07 to 0.14` remains in any tracked `.md`, `.R` or `.Rd` outside `planning/archive/` and round 1's own review file. NEWS's "0.07 to 0.7 s" covers all four groups and is consistent.

## Other checks

- `fwa_downstream()` bodies re-read from the local fwapg (`pg_get_functiondef`). The 10-argument form the walk calls delegates to the 11-argument one. Every branch is criterion 1 (`blue_line_key_a = blue_line_key_b AND …`) or criterion 2 (`wscode_a <@ wscode_b AND …`). So `subpath(ws, 0, k)` for k in 1..nlevel, plus the blue-line arm, admits a superset of every answer.
- `man/frs_network_features.Rd` matches roxygen: `devtools::document()` in a `git archive HEAD` copy, then `/usr/bin/diff -r man`, shows no difference.
- `devtools::test(filter = "network_features")` in that copy (21:15:36-21:15:54 UTC): unit 96 / local 19 / live 15 expectations, with 0 failed, 0 error and 0 skipped in each.
- NEWS / log README / research figures were spot-recomputed from `walks.tsv`. New CH/BT range 0.34-8.35 s. `old_scoped`/new ratios: CHWK BT 33.3×, LSKE 7.9×. `d_order` differs only on SALR CH, CHWK CH and CHWK BT. They match.
- `DESCRIPTION` is still 0.44.0 under a `# fresh 0.45.0` NEWS heading. That is expected: the bump is `/gh-pr-merge`'s.

## Findings

- **[fragile, low] tests/testthat/test-frs_network_features-local.R:13-15**: the comment says the ancestor arm alone admits "22 of 40,495 pairs with the fixture below". But the fixture below (every 25th segment plus the NULL-coded SKGT copies) gives SKGT **50,417** answer pairs with `include_equivalents = FALSE` (9,922 of them NULL-coded copies) and **51,698** with TRUE. 40,495 is the count of the every-25th-segment part alone at FALSE, which is the population `research/fwa_downstream_walk.md:43-44` and findings correctly describe ("every 25th FWA segment as features"). The text dates from 94a146c and survived round 1's rewrite of the lines around it. Fix: "22 of 40,495 pairs from the every-25th-segment part" (or "22 of 50,417 / 51,698 with the whole fixture").
  Measured 2026-10-28 21:14 UTC with the test's own fixture SQL and plain join on the local fwapg.

Not defects (noted, no change asked):

- **The roxygen's "the answer is the same as the unprefiltered join's" holds for every code but the empty ltree.** `fwa_downstream(1, 100, '100.1', '100.1', 2, 50, '', '', false, 1)` is **true**: `''` is an ancestor of everything, and `wscode_b = localcode_b AND wscode_a != wscode_b` holds. But `generate_series(1, nlevel(...))` starts at k = 1, so the prefilter never admits a `''`-coded feature off the AOI's blue lines. FWA has 0 such rows. Only a feature table that stores missing codes as `''` instead of NULL would see a difference. There, the old walk returned such a feature as downstream of every segment, which is itself meaningless. Mentioned so the guarantee's boundary is known, not as a requested change.

Verdict: no bug or security issue. Round 1's three fixes are correct and complete: no other reader of `timed_out`, the hand edit equals the script's rule, and no stale Fraser or 0.14 claim remains. One low-severity wrong denominator in a test comment.
