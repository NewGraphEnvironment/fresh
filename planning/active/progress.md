# Progress — Custom-AOI jobs delete whole watershed groups from the shared habitat and near_river tables (#293)

## Session 2026-11-02

- Plan-mode exploration: read `frs_habitat_classify()`, `frs_near_river()`,
  `frs_habitat()`'s persist path, #282's helpers in `R/utils.R`,
  `research/id_segment_identity.md`, link's `lnk_pipeline_classify()` and
  `lnk_persist_init()` (the downstream consumer), and the #282 archive README.
- Phase 0 part one landed in `findings.md`: the `bcfishpass` instance holds four
  fresh-written habitat tables, all single-group, none carrying
  `linear_feature_id`, and no `near_river` table — so no loss there.
- Gate decisions taken (owner): key option (a) `linear_feature_id`; migration by
  hard error + staged backfill; species-scope the custom-AOI delete, with the
  whole-group delete left unscoped by species so the backfill stays completable.
- Plan review (Plan agent, synchronous) reshaped the plan: an lfid-keyed delete
  removes the property that makes `(id_segment, watershed_group_code)` a sound
  **read** key on these shared tables, so the 13 habitat-to-streams join sites and
  the `near_river` predicate must gain the same key. Its citations were verified
  against the tree before the plan was written. Review findings are in
  `review-plan.md`.
- Created branch `293-custom-aoi-jobs-delete-whole-watershed-g` off origin/main at
  `832f0cc`.
- Scaffolded the PWF baseline with the approved phases.
- Next: Phase 0 against `frs_db_conn()`'s instance, then Phase 1 failing tests.
- Phase 0 complete. 199 habitat tables on the shared instance, every one
  single-group, so no habitat table has suffered the loss; 21 of 98 near_river
  tables are shared across 2-125 groups and are the realised exposure. The
  issue's magnitude claim is wrong: measured 0.38 rows lost per row written on
  the documented AOI, not a multiple. Issue body corrected.
  Commits: see `data-raw/audit_habitat_293.R`.
- Phases 1-4 landed in one commit: failing tests first, then the schema and
  key helpers, the delete scope and its transaction, and the read side.
  `tests/testthat/test-habitat_partition_293.R` 9 tests / 37 assertions, all
  passing. Next: the full suite, for what the narrowed key broke.
