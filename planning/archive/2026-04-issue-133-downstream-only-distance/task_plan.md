# Task: Distance cap downstream only (#133, corrected)

## Goal
connected_distance_max applies ONLY to spawning segments that are DOWNSTREAM of the nearest rearing. Upstream spawning has no distance cap — limited only by spawn-eligible contiguity.

## Key insight
A segment is "downstream of rearing" when rearing is UPSTREAM of it:
- Same-BLK: `s.drm < r.drm` (segment is below rearing on the stream)
- Cross-BLK: `fwa_upstream(s.ws, s.lc, r.ws, r.lc)` (rearing is upstream of segment)

The filter removes spawning segments where:
- The nearest rearing is upstream (segment is downstream of rearing)
- AND the distance to that rearing > connected_distance_max

Segments where rearing is downstream or lateral (segment is upstream of rearing) are KEPT regardless of distance.

## Phases
- [x] Branch + PWF
- [x] Rewrite `.frs_distance_filter()` — directional: upstream unlimited, downstream capped
- [x] 675 tests pass
- [ ] Code-check
- [ ] PR + merge + archive
