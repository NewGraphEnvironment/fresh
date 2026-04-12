# Progress: Issue #133 (reopened)

### 2026-04-12
- Branch `133-connected-distance-filter` created
- PWF initialized
- Previous fix (PR #134) passed connected_distance_max as bridge_distance — wrong. Need post-cluster distance filter.
- Implemented `.frs_distance_filter()` — same-BLK uses abs(DRM difference), cross-BLK uses fwa_upstream both directions
- Wired after frs_cluster in .frs_run_connectivity() when connected_distance_max is set
- 675 tests pass
