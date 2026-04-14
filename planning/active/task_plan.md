# Task Plan: Issue #147 — SK outlet ordering fix + refactor

## Phase 1: Fix lake outlet ordering + partition
- [x] Fix `ORDER BY` in `lake_outlets` CTE: add `wscode_ltree, localcode_ltree` before `downstream_route_measure`
- [x] Add `waterbody_key` to `lake_outlets` SELECT list so it's available downstream
- [x] Fix `PARTITION BY` in `downstream` CTE: change `lo.blue_line_key` to `lo.waterbody_key`
- [x] Fix all downstream CTEs: rename `lake_blk` to `lake_wbk`, partition/join on `waterbody_key`
- [x] Commit + code-check

## Phase 2: Extract reusable trace + rename to mechanism
- [x] Extract `.frs_trace_downstream()` — generic downstream trace with distance cap + gradient stop
- [x] Rename `.frs_connected_spawning()` to `.frs_connected_waterbody()` — mechanism not use-case
- [x] Parameterize `waterbody_poly` — dispatch from `waterbody_type` in rules (L, W)
- [x] Caller detects waterbody type generically, not hardcoded to lakes
- [x] Commit + code-check
