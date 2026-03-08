# fresh — Function Build Plan

## Goal
Build working fresh package with db helpers and fetch functions (#1), with tests.
All functions prefixed `frs_`, named noun-first.

## Phases

### Phase 1: DB Helpers
- [x] `frs_db_conn()` — connect to fwapg/bcfishpass PostgreSQL (env var defaults)
- [x] `frs_db_query()` — connect + query + disconnect, return sf
- [x] Tests for both (3/3 pass)

### Phase 2: Fetch Functions (Issue #1)
- [x] `frs_stream_fetch()` — fetch FWA stream segments by watershed group / bbox / blk
- [x] `frs_lake_fetch()` — fetch FWA lakes, network-aware filtering
- [x] `frs_wetland_fetch()` — fetch FWA wetlands, network-aware filtering
- [x] Tests for all three (9 tests, 18 expectations, all pass)

### Phase 3: Index Functions (Issue #2)
- [x] `frs_point_snap()` — snap xy to nearest stream (wraps fwa_indexpoint)
- [x] `frs_point_locate()` — get point geometry at network position (wraps fwa_locatealong)
- [x] Tests for both (26 total pass)

### Phase 4: Traverse Functions (Issue #3)
- [x] `frs_network_upstream()` — stream segments upstream (fwa_upstream ltree)
- [x] `frs_network_downstream()` — stream segments downstream (fwa_downstream ltree)
- [x] Tests for both (32 total pass)

### Phase 5: Prune Functions (Issue #4)
- [x] `frs_network_prune()` — filtered upstream (order, gradient, wsg)
- [x] `frs_order_filter()` — Strahler order threshold on sf result
- [x] Tests for both (37 total pass)

### Phase 6: Fish Functions (Issue #5)
- [x] `frs_fish_obs()` — query bcfishobs observations by species/wsg/blk
- [x] `frs_fish_habitat()` — query bcfishpass streams_vw habitat model
- [x] Tests for both (47 total pass)

### Phase 7: Package Polish
- [x] `devtools::document()` — NAMESPACE and man pages generated
- [x] `devtools::check()` — 0 errors, 0 warnings, 0 notes (after .Rbuildignore)
- [x] NEWS.md — v0.1.0
- [ ] PR to main with SRED reference

## Decisions
- Use same env vars as fpr (`PG_*_SHARE`) for zero-config compatibility
- `ngr_dbqs_ltree()` useful for traverse — copy as internal helper to avoid ngr dependency
- One function per R file, one test file per function
- Planning files committed to repo in `planning/`

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| permission denied for postgisftw.fwa_indexpoint | 1 | Use whse_basemapping.fwa_indexpoint with ST_Transform instead |
