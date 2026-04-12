# Task: SK spawning two-phase connected filter (#147)

## Goal
Replace generic frs_cluster + distance_filter for `requires_connected: rearing` with two-phase bcfishpass approach: downstream trace from lake outlets (3km cap, gradient stop) + upstream cluster with lake polygon proximity.

## Status: in progress

## Design
When `.frs_run_connectivity()` encounters `requires_connected` on spawn rules AND rearing includes `waterbody_type: L`, use `.frs_connected_spawning()` instead of the generic `frs_cluster` + `.frs_distance_filter()`.

`.frs_connected_spawning()` does:
1. Set ALL spawning = FALSE for this species (start clean)
2. **Downstream**: fwa_downstreamtrace from rearing lake outlets, cumulative distance, 3km cap, stop at first > 5% gradient. Set spawning = TRUE for qualifying segments.
3. **Upstream**: FWA_Upstream of rearing, cluster with ST_ClusterDBSCAN, st_dwithin(cluster, fwa_lakes_poly, 2). Set spawning = TRUE for qualifying clusters.

## Phases
- [x] Branch + PWF
- [x] `.frs_connected_spawning()` — Phase 1 downstream trace + Phase 2 upstream cluster + lake proximity
- [x] Wired into `.frs_run_connectivity()` — auto-detects lake-connected rearing
- [x] Subtractive approach preserves spawn thresholds from classify
- [x] 692 tests pass
- [ ] Code-check
- [ ] PR + merge + archive
