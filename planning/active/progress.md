# Progress — Custom-AOI persist deletes other watershed groups' rows from to_streams (#282)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user, as a **park**: the baseline
  only, no phase runs.
- Gate decisions taken (both recorded in `task_plan.md`): delete on
  `(id_segment, watershed_group_code)` as the issue proposes; `to_barriers`'
  blue_line_key delete filed as a separate issue rather than fixed here.
- Measured against the live DB during exploration: 0 null
  `watershed_group_code` in `fwa_stream_networks_sp` (column is `NOT NULL`), and
  **259 blue lines span more than one watershed group** — the fact behind the
  `to_barriers` sibling defect. Queries are in `findings.md`.
- Found that the shipped `frs_habitat()` example (`man/frs_habitat.Rd:211-217`)
  passes a custom AOI with `to_streams = "fresh.streams"`, which answers the
  issue's open question about whether any documented workflow reaches the bug.
- Created branch `282-custom-aoi-persist-deletes-other-watersh` off origin/main
  at `a49b45b`.
- Plan review (synchronous, before the baseline commit) found the issue's stated
  mechanism to be wrong: `id_segment` does **not** restart per job —
  `.frs_add_id_segment()` sets it to `linear_feature_id`. Confirmed in code, and
  the wrong mechanism is also in shipped `NEWS.md` 0.46.0.
- Measured the other half myself, which the review could not reach: `fresh.streams`
  holds 3.8M rows whose `id_segment` runs 1..n **per group**, 0 rows equal to
  `linear_feature_id`, 113,305 ids shared across groups, 0 duplicate
  `(id_segment, watershed_group_code)` pairs. So the issue's premise is right
  about the persisted table and wrong about the code, and the two sides measured
  different table generations. **The delete-key decision is re-opened**, as a
  Phase 0 task with both measurements in hand — not flipped on a review finding.
- Review also found, and I confirmed, that `frs_habitat_classify()` (`:170-172`,
  `:249-255`) and `frs_near_river()` (`:155-158`) delete **whole groups** from
  their shared targets in custom-AOI mode — larger than #282. Two entries in
  `findings.md`'s scoped-site audit were misclassified and are corrected; the
  defect is filed as its own issue in Phase 0.
- Phases restructured: new Phase 0 (settle the mechanism, re-decide the key, file
  the sibling), Phase 1 assertions rewritten to assert the collision is live
  before asserting survival, Phase 2 splits the helper so one proof runs on CI
  (there is no Postgres service in `.github/workflows/`), Phase 3's enumeration
  moved from parsing `R/` — which cannot fire, since tests run from
  `tests/testthat` — to `deparse(body())` with a positive control.
- Scaffolded PWF baseline from issue #282 with the reviewed phases
  (`review-plan.md` carries every finding with my verdict on it).
- Next: parked 2026-10-28; resume with the command below. **Start at Phase 0, not
  Phase 1** — the key decision is open and needs the owner.

## Session 2026-11-01 (compact capture, no phase work)

- Landed the mechanism correction on `main` (`4d65b96`), not on this branch: the
  wrong claim in `CLAUDE.md` is what produced the first draft of this plan, so
  leaving it behind a parked PR would let the next session repeat the error. Added
  `research/id_segment_identity.md` with both artifacts and their queries, and its
  row in `research/README.md`.
- Filed the three siblings this branch's review turned up, so none of them lives
  only in a parked branch:
  - **#293** — `frs_habitat_classify()` / `frs_near_river()` delete whole
    watershed groups in custom-AOI mode. Bigger than #282, and the inverse
    mechanism: the predicate names the group correctly, the group *set* is too
    wide. Read before Phase 1.
  - **#294** — `to_barriers` deletes by `blue_line_key` alone; 259 lines span
    groups; needs `watershed_group_code` carried through `frs_break_find()`'s
    multiclass projection.
  - **#295** — `NEWS.md` 0.46.0 and #231's body still state the wrong mechanism;
    asks how a released changelog entry should be corrected.
- `origin/main` moved from `a49b45b` to v0.50.1 while parked, so the resume
  command's `git merge origin/main` is doing real work, not a formality.
- Nothing in Phase 0–4 was executed. The branch still holds only the baseline.

### Resume

```bash
cd /Users/airvine/Projects/repo/fresh && git fetch -q origin && git checkout 282-custom-aoi-persist-deletes-other-watersh && git pull --ff-only && git merge origin/main
```

The park approval covered the baseline only. The run-to-PR mandate starts when
the resume instruction is given.

## Session 2026-11-01 (resume — run-to-PR mandate)

- Merged `origin/main` (v0.51.0) into the branch, clean. #277 parts 1 and 2 had
  landed while parked, so `frs_order_child()` and `frs_habitat_overlay()` already
  match `watershed_group_code`; the two `to_streams` delete sites are untouched at
  `R/frs_habitat.R:515` and `:675`.
- **Phase 0 measured** (`findings.md` A–F, commit `7f87793`). The re-opened key
  decision is settled empirically against the pair key: on a table built by
  current code the residual collisions are **same-group** — 81 of a job's 275
  derived ids name a real FWA segment and all 81 are in the job's own group, 0
  other-group. Found a third key the plan had not considered, the parent segment
  (`linear_feature_id`), which is the only candidate correct against both table
  generations and the only one that clears stale broken rows. Float equality in
  the predicate is safe and measured. The key does **not** decide #293, contrary
  to the resume premise — its targets carry no `linear_feature_id`.
- **Phase 1 reproduced the loss end to end.** New integration test in
  `tests/testthat/test-frs_habitat.R`, key-agnostic by construction (the decoy
  carries a distinct `linear_feature_id`). Run against the unfixed code: one
  failure, at the decoy-survives assertion, with the live-collision check passing
  first. The pure-string builder test moves to Phase 2, which is where the builder
  is written.
- **Blocked at Phase 2** on the owner's key choice, which is the one decision the
  resume instruction reserved. Options and numbers put back in the same session.
- **Owner's decisions, 2026-11-01:** delete key = **parent segment**
  (`linear_feature_id`); the #293 fallout to be **recorded in #293's body**.
- **Phase 2 landed** (`4dd375c`): `.frs_persist_streams()` replaces both copies
  of the persist block, with `.frs_persist_delete_sql()` split out as a pure
  string builder so the one proof that runs on CI needs no database. Nine
  CI-runnable cases, the widened `.frs_persist_columns()` return pinned in the
  existing #114 test, and an enumeration over `deparse(body(frs_habitat))` with
  positive controls.
- **Phase 3-4 partial** (`41fcd41`): two DB tests for the added-key NULL guard
  (hot and cold path — it had none, so a sweep would have called it uncaught),
  the mutation site list, `data-raw/audit_persist_282.R`, and the `to_streams`
  roxygen.
- **Self-review found a defect in my own Phase 2 code** (`f1f649b`):
  `.frs_persist_streams()` recomputed the delete key the builder also decided —
  "one fact derived twice". `.frs_persist_delete_key()` is now the single
  decision site; the agreement is pinned as a property over every column set
  that reaches a key, rather than by reading two paths and finding them
  consistent. The enumeration test's positive controls caught the restructure,
  which is what they are for.
- **First mutation sweep stopped and discarded**, deliberately: it was running
  against the pre-restructure code, and an interrupted sweep writes no table, so
  it is read as not run. Re-run once on the final shape with 10 sites, including
  one for the regression `f1f649b` removes.
- Three wordings sharpened after re-reading them: "nothing in the pipeline clips
  geometry" was loose, because `frs_break_apply()` does cut geometry. The
  accurate claim, in NEWS, the roxygen and `findings.md`, is that an AOI never
  *truncates* a segment at its boundary; breaking subdivides inside the run.
- Checked rather than assumed, before standing behind the repair claim: WSG mode
  passes a strict `watershed_group_code = '<code>'` row filter
  (`R/frs_habitat.R:438`, `:607`), not `.frs_resolve_aoi()`'s loose bbox arm, so
  a group job's working table holds exactly that group and the group overwrite is
  a clean replace.
- **Mutation sweep clean, 10 of 10 sites caught, 0 skipped** (`findings.md`,
  "Mutation sweep"). Run against the final shape. The defect site reddens four
  tests; the "one fact derived twice" site reddens two, so the property test
  that pins the chooser and the guard together is load-bearing.
- **mirai path run, not reasoned about:** `workers = 2L` against the installed
  branch reproduces all six #282 assertions. No test in the suite exercises
  `workers`, and a `load_all()` run could not have, since the daemon resolves
  internals in the installed namespace.
- **259 spanning blue lines re-derived** 2026-11-01, unchanged — the only
  measured figure in the NEWS entry carried over from the parked session.
- **Round 1 of `/code-check branch` found two real bugs in this branch's own
  code**, both reproduced before fixing (`findings.md`, "Round 1"):
  the added-key NULL guard was a **one-shot proxy** — the ALTER has already run
  when it raises, so the re-run its own error invites passes silently and the
  stale NULL-key row survives for ever; and `wsg` **and** `aoi` together is a
  subset job that was overwriting the whole watershed group, which also made
  the NEWS repair instruction actively harmful. Fixed at the decision sites:
  the guard asks the target for NULL-key rows on every call, and
  `.frs_partition_wsg()` decides whether a job owns the group outright.
- Also from round 1: the partition overwrite is now **one statement** (a
  data-modifying CTE), closing the DELETE/INSERT window
  `code-check-infra.md` names; `withr::defer()` in the audit script; and the
  `IS NOT DISTINCT FROM` claim in three planning files reconciled with the `=`
  that shipped.
- **Round 2 found a defect inside round 1's fix**, which keeps the review loop
  open past three rounds: the data-modifying CTE put the delete and the insert
  under one command id, so the insert's uniqueness check still saw the rows the
  delete was removing. `fresh.streams` has `streams_pkey` UNIQUE on
  `(id_segment, watershed_group_code)`, so the **second run of any ground**
  aborted — on the whole-group key too, which is the documented repair.
  Reproduced both ways. Replaced with one transaction around two statements,
  which is what `code-check-infra.md` prescribed; the fixtures now carry a
  unique index as the real targets do, and restoring the CTE reddens them.
- Round 2 also: `.frs_same_relation()`'s roxygen claimed exactness it cannot
  have for an unqualified name, so the exact `regclass` test now runs in
  `.frs_persist_streams()`; and the audit script's `n_missing` was a difference
  of two differently-filtered counts, now a `NOT EXISTS` set difference.
  Re-derived: 98 groups, 3 short, 34 segments — unchanged.
- **Round 3 named the mechanism and enumerated against it.** The mechanism: a
  property of the *code* standing in for a property of the *database* — every
  finding in rounds 1-3 is an instance, and each proxy was decidable from the
  source alone, which is why each survived into a live run. Enumeration: 15
  guards (1 with no test that could fail), 8 fixtures (constraint-free), 14
  prose claims (4 unsupported).
- Round 3's bug: `data-raw/audit_persist_282.R` took its reference set from
  `.frs_stream_guards()` and attributed those guards to `frs_extract()`, **which
  applies none** — so on a table built by current code the audit would have
  called a real loss of placeholder segments clean (BULK: 2,426 of 32,472 FWA
  segments fail the guards). It now reports both reference sets; on
  `fresh.streams` the pair shows 151,038 "missing" against all FWA and 34
  against the guarded set, which is the filter the legacy pass applied, and all
  34 are still `edge_type` 6010.
- Round 3 also: the `regclass` guard round 2 added had no test and no sweep row
  (now both); `tryCatch(dbBegin)` read every failure as nesting (now only the
  nesting message, both branches tested); the NULL-key guard's whole-target
  scope documented with its staged-migration escape; the `wsg` column check
  made two-sided; three prose claims corrected, including a loose "every
  sibling schema" replaced by 296 relations / 0 without a unique index.
