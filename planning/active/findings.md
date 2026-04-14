# Findings

## Bug 1: lake_outlets picks wrong tributary
`DISTINCT ON (waterbody_key)` with `ORDER BY waterbody_key, downstream_route_measure ASC` picks the segment with the smallest DRM on any BLK. For multi-BLK waterbodies, DRM is relative to each BLK — comparing across BLKs is meaningless. Need `ORDER BY waterbody_key, wscode_ltree, localcode_ltree, downstream_route_measure` to pick the network-topological outlet.

**Example**: waterbody_key 329064462 (BULK) spans 10 BLKs. DRM ordering picks BLK 360504780 DRM 0 (wrong tributary). wscode ordering picks BLK 360846413 DRM 9718 (actual outlet).

## Bug 2: cumulative distance partitions by BLK not waterbody
`PARTITION BY lo.blue_line_key` in the window function means the cumulative distance resets per-BLK. For a lake with one outlet but downstream traces crossing BLKs, this is wrong — distance should accumulate per waterbody (per lake trace). Same issue in `downstream_capped` and `nearest_barrier` partitions.

## Original two-phase design (from PR #148)
- Phase 1: downstream trace from lake outlets via `fwa_downstreamtrace`, capped at `connected_distance_max`, stopped at first gradient > `bridge_gradient`
- Phase 2: upstream cluster via `fwa_upstream` + `ST_ClusterDBSCAN` + `ST_DWithin` against lake polygons
- Detection: dispatched when rearing rules include `waterbody_type: L`
- Subtractive approach preserves spawn threshold classification
- `lake_ha_min` read from rearing rules, not hardcoded

## Key lesson from original implementation
Two fundamentally different algorithms (downstream trace vs upstream cluster) can't be replicated by a single generic `frs_cluster` call. The downstream phase uses `fwa_downstreamtrace` with cumulative distance; the upstream phase uses network traversal + spatial clustering + lake polygon proximity.

## Refactor: decompose into reusable pieces
- `.frs_trace_downstream(conn, origins_sql, target, distance_max, gradient_max)` — generic downstream trace. Takes any origins SQL producing `(origin_id, blue_line_key, downstream_route_measure)`. Returns `linear_feature_id`s into a target table. Reusable for any downstream trace use case (waterbody outlets, barrier impacts, reach delineation).
- `.frs_connected_waterbody()` replaces `.frs_connected_spawning()` — name reflects mechanism (waterbody connection) not use-case (spawning). Takes `waterbody_poly` param so the same function works for lakes (`fwa_lakes_poly`) or wetlands (`fwa_wetlands_poly`).
- Caller in `.frs_run_connectivity()` detects `waterbody_type` from rearing rules generically — not hardcoded to `L`. Supports `L` and `W`; `R` (rivers) excluded since river polygons don't have area thresholds in the same way.
