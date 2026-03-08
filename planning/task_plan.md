# fresh — Function Build Plan

## Goal
Build working fresh package with db helpers and fetch functions (#1), with tests.
All functions prefixed `frs_`, named noun-first.

## Phases

### Phase 1: DB Helpers
- [ ] `frs_db_conn()` — connect to fwapg/bcfishpass PostgreSQL (env var defaults)
- [ ] `frs_db_query()` — connect + query + disconnect, return sf
- [ ] Tests for both

### Phase 2: Fetch Functions (Issue #1)
- [ ] `frs_stream_fetch()` — fetch FWA stream segments by watershed group / bbox / blk
- [ ] `frs_lake_fetch()` — fetch FWA lakes, network-aware filtering
- [ ] `frs_wetland_fetch()` — fetch FWA wetlands, network-aware filtering
- [ ] Tests for all three

### Phase 3: Index Functions (Issue #2)
- [ ] `frs_point_snap()` — snap xy to nearest stream segment
- [ ] `frs_point_measure()` — get blue_line_key + downstream_route_measure
- [ ] Tests for both

### Phase 4: Traverse Functions (Issue #3)
- [ ] `frs_network_upstream()` — stream segments upstream of a point
- [ ] `frs_network_downstream()` — stream segments downstream of a point
- [ ] Tests for both

### Phase 5: Prune Functions (Issue #4)
- [ ] `frs_network_prune()` — filter by order, gradient, access
- [ ] `frs_order_filter()` — Strahler order threshold
- [ ] Tests for both

### Phase 6: Fish Functions (Issue #5)
- [ ] `frs_fish_obs()` — query bcfishobs observations
- [ ] `frs_fish_habitat()` — query bcfishpass habitat model
- [ ] Tests for both

### Phase 7: Package Polish
- [ ] `devtools::document()` — generate NAMESPACE and man pages
- [ ] `devtools::check()` — clean check
- [ ] NEWS.md
- [ ] PR to main with SRED reference

## Decisions
- Use same env vars as fpr (`PG_*_SHARE`) for zero-config compatibility
- `ngr_dbqs_ltree()` useful for traverse — copy as internal helper to avoid ngr dependency
- One function per R file, one test file per function
- Planning files committed to repo in `planning/`

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
