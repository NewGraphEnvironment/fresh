# Task: Fix distance filter with cross-BLK Euclidean fallback (#133)

## Goal
Same-BLK: DRM difference (exact network distance). Cross-BLK: ST_Distance on geometries (Euclidean). Both capped at connected_distance_max.

## Status: in progress

## Why
- PR #137: cross-BLK had no distance cap → 11.7km segment survived 3km cap
- PR #138: removed cross-BLK entirely → overcorrected, SK spawning 113→14.9 km (bcfishpass: 85.7)
- Spawning and rearing are on DIFFERENT BLKs (stream vs lake flow line) — cross-BLK IS the normal case for SK

## Phases
- [x] Branch + PWF
- [x] Updated `.frs_distance_filter()`: same-BLK DRM OR cross-BLK ST_Distance
- [x] 675 tests pass
- [ ] Code-check
- [ ] PR + merge + archive
