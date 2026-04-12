# Task: Fix distance filter cross-BLK bypass (#133)

## Goal
Remove the cross-BLK branch from `.frs_distance_filter()` that bypasses the distance cap. Lake rearing on a different BLK was keeping spawning segments 11.7km away alive.

## Status: in progress

## Phases
- [x] Branch + PWF
- [x] Remove cross-BLK OR branch — same-BLK DRM only
- [x] 675 tests pass
- [ ] Code-check
- [ ] PR + merge + archive
