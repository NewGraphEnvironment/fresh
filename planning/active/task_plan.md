# Task Plan: Issue #147 — SK outlet ordering fix

## Phase 1: Fix lake outlet ordering + partition
- [ ] Fix `ORDER BY` in `lake_outlets` CTE (line 1385): add `wscode_ltree, localcode_ltree` before `downstream_route_measure`
- [ ] Add `waterbody_key` to `lake_outlets` SELECT list so it's available downstream
- [ ] Fix `PARTITION BY` in `downstream` CTE (line 1392): change `lo.blue_line_key` to `lo.waterbody_key`
- [ ] Fix `downstream_capped` PARTITION BY (line 1401-1403) to also use `waterbody_key` instead of `lake_blk`
- [ ] Commit + code-check
