# Findings: Issue #129

The observation override from #69 put fish passage interpretation (counting, thresholds, species grouping, date filters) in fresh. That belongs in link. The fix: fresh accepts a pre-computed `barrier_overrides` table with simple (blk, drm, species_code) tuples. Link prepares this table via `lnk_barrier_overrides()`.

The `.frs_access_with_observations()` helper and all observation_* CSV columns can be removed. The new `barrier_overrides` approach is much simpler — just a NOT EXISTS against the overrides table in the access query.
