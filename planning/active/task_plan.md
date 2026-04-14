# Task Plan: Issue #147 — SK outlet ordering fix

## Phase 1: Fix lake outlet ordering + partition
- [x] Fix `ORDER BY` in `lake_outlets` CTE: add `wscode_ltree, localcode_ltree` before `downstream_route_measure`
- [x] Add `waterbody_key` to `lake_outlets` SELECT list so it's available downstream
- [x] Fix `PARTITION BY` in `downstream` CTE: change `lo.blue_line_key` to `lo.waterbody_key`
- [x] Fix all downstream CTEs: rename `lake_blk` to `lake_wbk`, partition/join on `waterbody_key`
- [x] Commit + code-check
