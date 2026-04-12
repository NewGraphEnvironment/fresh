# Task: connected_distance_max post-cluster filter (#133 reopened)

## Goal
After frs_cluster finds connected clusters, filter out individual segments whose network distance to the nearest connected habitat segment exceeds `connected_distance_max`. Currently it only controls the cluster search distance, not the extent.

## Status: in progress

## Phases
- [x] Branch + PWF
- [x] New `.frs_distance_filter()` — same-BLK DRM distance + cross-BLK ltree check
- [x] Wired into `.frs_run_connectivity()` after frs_cluster when connected_distance_max set
- [x] 675 tests pass
- [ ] Code-check
- [ ] PR + merge + NEWS + archive
