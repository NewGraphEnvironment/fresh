# Findings — Backlog move 1: watershed-group keying fixes (#318)

## Issue context

**If we do it:** barriers and habitat rows stop crossing watershed groups, and rows with no group are either refused or found. **If we never do:** a job keeps deleting other groups' barriers on group-spanning blue lines, and NULL-group rows are written and never read.

This is move 1 of `planning/backlog.md` (#315). Run `/planning-init <this issue>`: its batches are the scope, one phase per batch, one PR.

When the plan finds that a batch, or one of its members, is more than one PR's work, it carries the first piece and files each other piece as its own issue naming move 1, and leaves it out of `planning/backlog.md`: the next `/backlog-sweep` reads an issue the file does not name as unplaced, and folds it into a move other than this one.

## Batch 1: Watershed-group keying fixes

**Why here:** The keying family #282 and #293 hit, a third time: #294 deletes another group's barriers on the 259 blue lines that span groups. One synthetic fixture serves all three.

**Touches:** `R/frs_habitat.R`, `R/frs_break.R`, `R/utils.R`, `R/frs_cluster.R`, `R/frs_near_river.R`, `R/frs_habitat_classify.R`, `R/frs_habitat_overlay.R`, `research/id_segment_identity.md`

**To decide at the gate:**

- #308: option 1, 2 or 3 for rows with a NULL `watershed_group_code`.
- #277: direct mode refuses an `id_segment`-only join, or documents it. Its parts 1-3 shipped in PR #296 and #297.
- #294: the approach is already chosen in the issue (widen the key).

| issue | title |
|---|---|
| #294 | to_barriers delete keys on blue_line_key alone, so a job removes another group's barriers on the 259 lines that span groups |
| #308 | Habitat rows with a NULL watershed_group_code are written but never read |
| #277 | frs_habitat_overlay() direct mode: refuse an id_segment join without watershed_group_code? (the three id_segment-only keys are fixed) |



## Exploration (2026-11-22, plan mode)

- `.frs_break_find_multiclass()` (`R/frs_break.R`) takes `working_blks` from the job extract, then reads every `fwa_stream_networks_sp` segment of those blue lines with no group filter: a job's `grad_tbl` covers whole lines, so the blue-line delete in `frs_habitat()` matches exactly what the insert writes back. #294's defect is last writer wins on classes (thresholds come from each job's species), not loss.
- Both barrier blocks are inline copies (sequential `.run_job` and the mirai worker); `.frs_persist_streams()` (`R/utils.R`) is the shape to copy: `.frs_persist_columns()`, `.frs_null_key_guard()`, one transaction, explicit columns.
- `.frs_group_required()` early-returns without `linear_feature_id`; `test-habitat_partition_293.R` pins the #225 NULL-group case as replaced-not-refused.
- `frs_habitat_overlay()` direct mode joins on the caller's `by`; the mocked test at line 236 uses `by = "id_segment"`.

## #294 measured: the whole-line read and last writer wins (2026-11-22)

`data-raw/barrier_span_294.R`, the Docker fwapg from `docker/`, logs in `data-raw/logs/barrier_span_294/`.

- 157 mainstem blue lines (`blue_line_key = watershed_key`, which the default `blk_filter` samples) span more than one watershed group. The issue's 259 counts every blue line, mainstem or not.
- 108 of the 157 join groups whose species give different gradient thresholds.
- On CHWK/HARR line 356308001, the HARR job wrote the same 18 barriers, all in CHWK, as the CHWK job did: the whole line is read, so the old blue-line delete covered exactly what the insert wrote back. Nothing was lost.
- 12 sampled two-group lines (over 3 km, thresholds differ, shortest first): on 5 of them, the second group's job leaves the first group's barriers different from what that group's own job found. Altogether 41 of 126 first-group positions are missing, extra, or at a different class. On GUIC/LNIC alone it is 26 of 73.
- 0 barriers fell outside every segment under `.frs_enrich_breaks()`'s `[downstream, upstream)` rule, so keying on the parent segment drops nothing on this sample.

So #294's defect is last writer wins on classes, not deletion. The fix scopes delete and insert to the job's own segments.

## Plan review (2026-11-22)

`review-plan.md` has every finding with its verdict. Not measured, kept as a documented edge: the barrier finder rounds a vertex measure to 0.01 m, which can key a barrier sitting right on a group boundary to the neighbouring group's segment. That barrier is then written by the neighbour's job, at the neighbour's classes. The 12-line sample counted barriers with no segment (0), not barriers moved across a boundary.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `frs_db_conn()` refused by the default database | `Sys.setenv()` to the Docker fwapg from `docker/` before `load_all()`, as CLAUDE.md describes |
