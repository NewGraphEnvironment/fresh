# Code-check round 3: branch 318 (HEAD c5f8596, merge-base a00ad5d)

## Checklist read

- code-check-infra.md: read in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms`, with table rows and evidence blocks skipped. None of the ~25 headings under "Rules that stand alone", Security or Spreadsheets/PDFs was read.
- code-check-r.md: read 7 sections in full: "Postgres row order is never fixed unless the query fixes it…", "testthat counts an uncaught error under `error`, not `failed`", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "`deparse(body(f))` excludes formal defaults…", "A `function(...)` mock hides arguments the real callee no longer accepts", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package", "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check`…". I also searched for "A database driver's value is not a base R type", but the search pattern did not match it, so it was not read. The rest were judged from their index lines.
- code-check-spatial.md: read 2 sections in full: "FWA `upstream_route_measure` misses the next segment's start" and "FWA main flow is not edge type 1000 alone". The rest were judged from their index lines.
- code-check-shell.md: index lines only. The diff contains no shell.

## The mechanism behind rounds 1-3

All three earlier findings, and the one below, have the same cause. **The observation the test reads is the same whether the code is right or wrong.** The fixture or the helper folds the defect state and the correct state into one value, and nobody restored the defect to see whether the observation changed:

- Round 1 (gap barriers): the persist fixtures set `linear_feature_id` themselves, so the keying step under test never ran.
- Round 1 (`ID_SEGMENT`): an earlier column check refused the call before it reached the guard, and the refusal looked the same as the guard's.
- Round 2 (`off == 0`): the AOI holds whole blue lines, so "scoped" and "unscoped" write the same rows.
- Round 3 (below): `.ov_direct()` turns a refusal into a length-1 string, and one species × one habitat type turns success into a length-1 SQL vector. So `expect_length(x, 1)` reads the same value for both outcomes.

Where that mechanism can reach, I enumerated every `expect_*` the branch adds or changes:

| file | assertions | targets | can fail? |
|---|---|---|---|
| test-frs_habitat.R | `linear_feature_id` / `watershed_group_code` in cols | enrich not run with `parent = TRUE` | yes. Without the columns, the persist helper stops and the test errors. |
| test-frs_habitat.R | `off == 0` | unscoped insert | no (accepted tradeoff; the comment now says so) |
| test-frs_habitat.R | DELETE count 0, `.frs_persist_barriers(` ×2, `parent = TRUE` ×2, the four greps on the helper body | inline delete re-added, wiring dropped | yes. These are literal counts over the deparsed body, which drops comments. |
| test-frs_habitat_overlay.R | wsg refusal + `"by"` + join text (L271-277) | missing wsg | yes. The join-text match catches a wrongful refusal. |
| test-frs_habitat_overlay.R | source-lacks-wsg message (L285) | inner branch | yes. The outer message does not name `ws.k`. |
| test-frs_habitat_overlay.R | lfid refusal (L294) | missing lfid | yes |
| test-frs_habitat_overlay.R | **`expect_length(ok, 1)` L297, `expect_length(to_only, 1)` L301** | refusal of a correct call | **no (finding)** |
| test-frs_habitat_overlay.R | point join `expect_no_match("^ERROR:")` | guard leaking into the point join | yes |
| test-habitat_partition_293.R | #225 block flipped to refused, counts (L965-971) | classify guard | yes (mutation `g_classify`: 5 failed + 1 error) |
| test-habitat_partition_293.R | classify / near_river / cluster / order_child / bridged overlay refusals (L995-1024) | each guard | yes. Removing each guard on its own turned the file red: g_cluster 1F+1E, g_order 1F+1E, g_overlay 2F, g_near 2F+1E, g_classify 5F+1E. |
| test-habitat_partition_293.R | call-graph walk (premise, near_river reach, unguarded empty, exempt stale) | entry point missing the guard | yes. It is among the failures in each mutation above. |
| test-persist_barriers_294.R | two-group, re-run, moved barrier, unkeyed row, old shape (incl. `"re-run every watershed group"` no-match, which the staged text really contains), rollback, same table | scope, idempotence, guard, transaction | yes, by reasoning from the fixture against the blue-line delete, against an unscoped insert, against deleting by the source's lfids, and against removing the guard, the transaction or the regclass check. Each one changes a row the test reads. |
| test-persist_barriers_294.R | gap test, incl. the default-arm `c(TRUE, FALSE)` | `upstream_route_measure` bound | yes. The default-arm row is also the premise: it shows 148.18 really sits in a gap. |

Code side: the silent drop of an unkeyed barrier is now empty in practice. With the `lead()` bound, BULK has 0 of 104,137 barriers unkeyed, MORR 0 of 68,364 and LFRA 0 of 52,753 (measured 2026-11-22 on the local fwapg, `frs_break_find()` at 7 classes plus `.frs_enrich_breaks(parent = TRUE)`).

## Findings

- **[severity: fragile]** tests/testthat/test-frs_habitat_overlay.R:297 and :301. Two `expect_length(..., 1)` assertions cannot tell a refusal from success. The test's own helper turns any error into one string `"ERROR: …"`, and a successful call with one species and one habitat type captures one UPDATE, so both outcomes have length 1. Proved by mutation in a detached worktree; the overlay test file stayed FAIL 0 / ERROR 0 under each:
  - Dropping `!"linear_feature_id" %in% by` from the guard (R/frs_habitat_overlay.R:246-247) makes it refuse `by = c("id_segment", "watershed_group_code", "linear_feature_id")`. That is the exact remedy its message prescribes, so a caller who follows it loops on the same refusal. `.ov_direct()` returned the "leaves out linear_feature_id" error and L297 passed.
  - Dropping `"linear_feature_id" %in% from_cols &&` makes it refuse the case where only `to` carries the column, the case accepted at the plan gate. The message then wrongly says "both ws.h and ws.k carry". L301 passed.

  Production code is correct today; what is missing is the guard on these two branches. A matching `expect_no_match(ok, "^ERROR:")` / `expect_no_match(to_only, "^ERROR:")`, as the point-join test at L311 already does, can fail against both mutations.
  - **Rule:** code-check.md "A proxy is not the property" (whether an assertion can tell the property from a neighbouring value); code-check.md "Restore the bug and prove the guard fires"

## Considered, not findings

- Direct-mode overlay does not run `.frs_group_required()`. The call-graph test counts `frs_habitat_overlay` as guarded because its bridged branch calls the guard, since `reach()` cannot see branches. In direct mode there is no streams table to check, and a `to` with NULL-group rows comes only from data written before #308. That falls within the owner's #308 scope (bridged only).
- Nothing in the code has changed since round 2 (c5f8596 touched only a test comment), so round 2's link assessment stands.
- The scratch worktree has been removed. Nothing was written outside pg_temp.
