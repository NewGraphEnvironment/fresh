# Task Plan — fresh#191: lake_adjacent knob on .frs_connected_waterbody

## Phase 1: Setup
- [x] File fresh#191 with diagnosis + proposed fix
- [x] Branch `191-lake-adjacent-knob` from main
- [ ] PWF baseline (task_plan, findings, progress)

## Phase 2: Code change — fresh-side
- [ ] Add `lake_adjacent` parameter (default TRUE) to `.frs_connected_waterbody`
- [ ] Branch Phase 2 SQL: when FALSE, skip `clustered`/`cluster_geoms`/`valid_clusters` CTEs and insert `SELECT id_segment FROM spawn_upstream` directly into the qualifying-segments temp table
- [ ] Update `frs_habitat_classify` call site (`R/frs_habitat.R:1217`) to read `sc[["lake_adjacent"]] %||% TRUE` and pass through
- [ ] Update `.frs_load_rules` `spawn_connected` validator (`R/frs_params.R`) to accept `lake_adjacent` as a valid key
- [ ] `devtools::document()` clean

## Phase 3: Tests (robust — prove both branches)
- [ ] `tests/testthat/test-frs_habitat.R`: `.frs_connected_waterbody` with `lake_adjacent = TRUE` (default) — assert `ST_ClusterDBSCAN`, `cluster_geoms`, `valid_clusters`, `ST_DWithin` all appear in captured SQL
- [ ] Same file: `.frs_connected_waterbody` with `lake_adjacent = FALSE` — assert NONE of those CTE markers appear; assert `INSERT INTO ... SELECT id_segment FROM spawn_upstream` does appear (per-statement match)
- [ ] `tests/testthat/test-frs_params.R`: `.frs_load_rules` accepts `spawn_connected.lake_adjacent: yes/no`
- [ ] Same file: `.frs_load_rules` errors on misspelled key — confirms validator wired up
- [ ] `devtools::test()` clean (excluding known pre-existing failures)

## Phase 4: Code-check
- [ ] `/code-check` on staged diff — fix any real findings, re-stage

## Phase 5: Release
- [ ] DESCRIPTION: 0.25.0 → 0.26.0
- [ ] NEWS.md: 0.26.0 entry
- [ ] Commit "Release v0.26.0"
- [ ] Tag v0.26.0, push

## Phase 6: Ship
- [ ] PR with `Fixes #191` and `Relates to NewGraphEnvironment/sred-2025-2026#18`
- [ ] PR cross-references link#87
- [ ] Archive PWF after merge
