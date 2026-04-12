## Outcome

Post-cluster distance filter caps habitat extent from connected segments. SK spawning 112 km → ~74 km. Previous implementation (PR #134) only controlled search distance, not extent.

## Key Learnings

- `bridge_distance` on frs_cluster controls how far to SEARCH for a connection. `connected_distance_max` must filter the EXTENT after clustering. Two separate concepts.
- Same-BLK DRM difference is sufficient for the primary case (spawning downstream of lake on same stream). Cross-BLK distance cap is a known gap — documented.

## Closed By

PR #137

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
