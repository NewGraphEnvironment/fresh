# Task: Backlog move 1: watershed-group keying fixes (#318)

**If we do it:** barriers and habitat rows stop crossing watershed groups, and rows with no group are either refused or found. **If we never do:** a job keeps deleting other groups' barriers on group-spanning blue lines, and NULL-group rows are written and never read.

## Context from exploration
Move 1 of `planning/backlog.md` (#315): one PR, one phase per member of its single batch: #294, #308, #277. All three are the keying family #282 and #293 already hit: rows crossing watershed groups, or rows with no group written and then never read.

Exploration corrected #294's premise. `frs_break_find()`'s multiclass arm (`R/frs_break.R`, `.frs_break_find_multiclass`) takes the blue lines from the job's extract, then reads **every** FWA segment of those lines (`whse_basemapping.fwa_stream_networks_sp`, no group filter). So a job's `grad_tbl` holds barriers along the whole line, in the neighbouring group too, and the blue-line delete matches exactly what the insert writes back. Nothing is lost. The defect is **last writer wins**: each job builds its gradient classes from its own species' thresholds (`all_thresholds`), so the second group's run overwrites the first group's barriers with the wrong classes. A wider key alone would not help. The job has to delete and insert only the barriers on its own segments.

## Decided at the gate (owner, 2026-11-22)

- **#294 key:** carry `linear_feature_id` and `watershed_group_code` (from the segment each barrier falls on) on persisted barriers. Delete and insert only barriers on the job's own segments, by `linear_feature_id`: the rule #293 chose for `to_streams`, and it covers custom AOIs.
- **#294 old tables:** a `to_barriers` written before this change gains the columns with NULL in its old rows. The run refuses through the existing `.frs_null_key_guard()`, before any delete, and says to drop the table and re-run.
- **#308:** option 1. Refuse any NULL `watershed_group_code`, not only on parent-segment networks.
- **#277:** refuse. Direct mode refuses an `id_segment` join that leaves out a key column the tables carry.

## Phase 1: #294, persist barriers on the job's own ground

- [x] Measure the corrected premise, read-only, on the local fwapg: pick a mainstem blue line (`blue_line_key = watershed_key`) that spans two groups, run the multiclass `frs_break_find()` from one group's extract, and count its barriers in the other group. Check the two groups' species give different thresholds (`frs_wsg_species()`). Count barriers that `.frs_enrich_breaks()`'s `>= drm AND < urm` match leaves without a segment on one group. Write it up in `findings.md`.
- [x] Edit #294's body: the corrected mechanism, the decided fix, and a link to the findings.
- [x] Tests first, on `pg_temp` (`helper-synthetic.R` style, `frs_test_tbl()` for any `working.` name). Cover a new `.frs_persist_barriers(conn, to, from, streams)`:
  - two jobs on two groups sharing a blue line: after the second job, the first job's barriers on its own segments are still there with their own classes;
  - a re-run replaces its rows instead of duplicating them;
  - a barrier with no parent segment (NULL `linear_feature_id`) is not inserted;
  - an old-shape target (no key columns, with rows) is refused before anything is deleted;
  - delete and insert run in one transaction.
- [x] `.frs_enrich_breaks()` (`R/frs_habitat.R`) gains a `parent = FALSE` argument. With `TRUE` it also sets `linear_feature_id` and `watershed_group_code` in the same join. `frs_habitat_access()` keeps calling it without that argument, so its output does not change.
- [x] Add `.frs_persist_barriers()` to `R/utils.R`, built the way `.frs_persist_streams()` is: `CREATE TABLE IF NOT EXISTS`, then `.frs_persist_columns()`, then `.frs_null_key_guard(key = "linear_feature_id")`, then delete and insert in one transaction with an explicit column list. Delete `WHERE linear_feature_id IN (SELECT linear_feature_id FROM <streams>)`. Insert only the `from` rows whose `linear_feature_id` is in `<streams>`. Refuse a target that is the same relation as the source.
- [x] Replace both inline barrier blocks in `frs_habitat()`, the sequential `.run_job` and the mirai worker, with `.frs_enrich_breaks(parent = TRUE)` plus `.frs_persist_barriers(..., streams = streams_tbl)`.
- [x] Update the structural test in `test-frs_habitat.R` (around line 765): the body has no `DELETE FROM` left and calls `.frs_persist_barriers(` twice. Add positive controls on the helper's body.
- [x] Update roxygen `@param to_barriers` (new columns, what scope each job writes) and `devtools::document()`.
- [x] Restore the old scope in a throwaway worktree and confirm the tests go red: (a) delete by `blue_line_key IN (SELECT blue_line_key FROM from)`, (b) INSERT without `WHERE owned`. 9 failures each.
- [x] (review) `.frs_null_key_guard(staged = FALSE)` for barriers: the staged per-group backfill would loop on the same refusal.
- [x] (review) `@param to_barriers` says the rest of a line is no longer written by this job, and lists `source`. The existing integration test (`test-frs_habitat.R`, to_barriers) checks every row lies on the job's segments.

## Phase 2: #308, refuse a NULL watershed group

- [x] Tests first: a network with a NULL-group row and no `linear_feature_id` is refused by `frs_habitat_classify()`, `frs_near_river()`, `frs_cluster()`, `frs_order_child()` and bridged `frs_habitat_overlay()`. Flip the #225 block in `test-habitat_partition_293.R` (around line 305) and the drop-`linear_feature_id` no-error block (around line 584) to "refused". Keep the phrase "no watershed_group_code" in the message. Mock `.frs_group_required` in the `test-frs_cluster.R` mocked tests (review 5, 6, 11).
- [x] `.frs_group_required()` (`R/utils.R`) drops its `lfid` early return and refuses any NULL group, tested with `EXISTS` rather than `count(*)`. The message tells a network with no groups to set a constant one, and says habitat rows already written with no group must be rebuilt (review 9, 10). Keep `lfid` only for the wording, or drop the argument and update the two callers (`frs_habitat_classify.R`, `frs_near_river.R`).
- [x] Call it from `frs_cluster()` on `table`, before the species lookup; from `frs_order_child()` and bridged `frs_habitat_overlay()` after their own column checks (review 7).
- [x] Find every exported entry point that reaches `.frs_key_match()`, and so equates the group: `frs_cluster`, `frs_order_child`, `frs_habitat_overlay` bridged, and the connectivity passes (reached through classify). Each one either calls the guard or is reached only through one that does. Add a structural test in `test-habitat_partition_293.R` that fails if an entry point is missing it, with named exemptions: `frs_habitat_predicates()` (takes no table) and the connectivity internals (reached in `frs_habitat()` after classify) (review 8). Run it after Phase 3 too.
- [x] Rewrite the roxygen of `.frs_group_required()` (it still says the no-`lfid` case is #308's open question), and correct any exported docs that say a NULL group is tolerated.

## Phase 3: #277, refuse an id_segment-only direct join

- [x] Tests first (mocked, `test-frs_habitat_overlay.R`). The rule, applied only when `id_segment` is in `by` (compared lower-case): `watershed_group_code` must be in `by` when `to` carries it, and `linear_feature_id` must be in `by` when both `to` and `from` carry it. A `from` without the group gets a message naming the source. The default point join and the existing line-236 test (TBL_DEFAULT has neither column) stay valid (review 12-14).
- [x] Add the refusal in `frs_habitat_overlay()` direct mode, after the `from` column check, from the `to_cols`/`from_cols` it already holds (so the mocked tests reach it).
- [x] Roxygen for `by` and the direct-mode section. `devtools::document()`.

## Phase 4: Docs and release

- [x] `research/id_segment_identity.md`: a section on persisted barriers (the whole-line read, last writer wins, the parent-segment key) and on the NULL-group refusal. Update the **Verified** line.
- [x] `CLAUDE.md` naming conventions: `to_barriers` is keyed by `linear_feature_id`, like `to_streams`.
- [ ] Commits close #294, #308 and #277 with `Fixes #N`. Reconcile #318 and the member issue bodies with what shipped.
- [ ] As the last commit: a NEWS entry (behaviour changes: barriers gain 2 columns, old barrier tables are refused, NULL groups are refused, id_segment-only direct overlays are refused) and a minor version bump from 0.55.1.

## Owed at the end (reported, done after merge)

- [x] Check whether anything in link reads a `frs_habitat(to_barriers =)` table (the review's grep found none). Only if a consumer exists, file a heads-up issue in link: two new columns, and an old table must be rebuilt. Checked 2026-11-22: GitHub code search and `git grep` of link's `origin/main` find no `to_barriers`, so no issue is needed.

## link compatibility (owner, 2026-11-22)

- [x] Nothing on this branch may change link's outputs or stop a link run: call-graph diff, guard reachability, and link's suite against fresh main vs branch, identical (findings.md)

## Validation

- [x] Tests pass (whole suite on the `docker/` fwapg, 2026-11-22: 0 failed, 0 errors, 2756 passed, 7 skipped, all for reasons outside this work: no bcfishpass schema, no fwapg trial)
- [x] `/code-check` clean (once over the branch with `/code-check branch`): 3 rounds, ended on an enumeration of every new or changed assertion (`review-verdict.md`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

**How each change is proved:**
- `Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5` against the local Docker fwapg, the whole suite, committed before the run.
- Each new guard is shown to fire: restore the old code in a `git worktree` and watch its test go red.
- `test-test_table_names.R` stays green (no fixed `working.` names).
- `lintr::lint_package()` compared per file and line against an `origin/main` worktree. `devtools::document()` is clean. `pkgdown::check_pkgdown()` is clean (no new exports expected).
- The Phase 1 measurement is recorded with its query and date in `findings.md` and the archive README.
