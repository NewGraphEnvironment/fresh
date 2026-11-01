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
