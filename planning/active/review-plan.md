# Plan review for #318 (Plan agent, 2026-11-22, background beside Phase 1)

Run while Phase 1 landed; findings cite HEAD at the time. Each verdict below was probed before acting.

| # | Category | Finding | Verdict |
|---|---|---|---|
| 1 | Q1 | #294 premise correct: `working_blks` from the extract, `vertex_grades` reads every segment of those lines, classes from the job's species | Confirmed (matches `data-raw/barrier_span_294.R`) |
| 2 | Q2 | Working streams table carries `linear_feature_id` on every segment, split children included; exists at step 5b | Confirmed by reading `frs_break_apply`, cleanup order |
| 3 | Q2 | Rounding (`ROUND(drm, 2)`) can key a barrier just past a group boundary to the neighbour's segment; measurement counted NULLs only | Accepted as a documented edge, not measured (see findings) |
| 4 | Gap | `.frs_null_key_guard()` advises the staged per-group backfill, which loops for barriers (every run keys on `linear_feature_id`) | Confirmed; fixed with `staged = FALSE`, test asserts the wording |
| 5 | Gap | Phase 2 also breaks `test-habitat_partition_293.R:584-590` (the drop-`linear_feature_id` no-error block); the message must keep "no watershed_group_code" | Folded into Phase 2 |
| 6 | Gap | `test-frs_cluster.R` mocked tests (62/104/146) would hit an unstubbed `DBI::dbGetQuery` through the guard | Folded into Phase 2 |
| 7 | Ordering | Guard after each function's own column checks (order_child, overlay bridge), so friendly "must carry" errors stay | Folded into Phase 2 |
| 8 | Gap | `frs_habitat_predicates()` emits the group-equating near_river EXISTS and takes no table: structural test must exempt it; the connectivity internals are reached after classify in `frs_habitat()` | Folded into Phase 2 |
| 9 | Assumption | Old NULL-group habitat rows stay stranded; tell users to rebuild | Folded into Phase 2 message and NEWS |
| 10 | Gap | Guard uses `count(*)`; use `EXISTS` | Folded into Phase 2 |
| 11 | Gap | Phase 2 tests should cover `frs_order_child` and bridged overlay too | Folded |
| 12 | Blocker-risk | #277 `linear_feature_id` clause must apply only when `id_segment` is in `by`, or the default point join is refused | Confirmed; folded into Phase 3 rule |
| 13 | Assumption | "Same rule as `.frs_key_match()`" is wrong; state the rule; from lacking the group needs its own message; compare `tolower(by)`; use existing `to_cols`/`from_cols` | Folded into Phase 3 |
| 14 | Acceptance | Overlay test at line 236 needs no change (TBL_DEFAULT has neither column) | Accepted; kept as the id_segment-only control |
| 15 | Gap | NEWS and roxygen must say barriers on the rest of a line are no longer persisted by this job | Fixed in `@param to_barriers`; NEWS in Phase 4 |
| 16 | Assumption | No file in link references `to_barriers`; the owed issue may be unnecessary | Owed item reworded: confirm a consumer first |
| 17 | Acceptance | Mutation check must target the helper (delete predicate; INSERT without `WHERE owned`) | Both run: 9 failures each |
| 18 | Acceptance | Existing integration test is the end-to-end cover; plan should name it | Named; extended with the scope check |
| 19 | Scope | Parallel first-run catalog race on `CREATE TABLE IF NOT EXISTS`, same as `to_streams` | Pre-existing, out of scope |
