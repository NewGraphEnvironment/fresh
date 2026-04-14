## Outcome

Fixed multi-BLK lake outlet ordering (wscode topology instead of DRM), partition by waterbody_key instead of blue_line_key, extracted reusable `.frs_trace_downstream()`, renamed to `.frs_connected_waterbody()` with parameterized waterbody poly tables. Added `.frs_waterbody_tables()` helper so `waterbody_type: L` includes reservoirs (FWA digitization artifact, not ecology). BULK SK spawning from -22.6% to +0.1% vs bcfishpass.

## Key Learnings

- DRM is per-BLK — comparing across BLKs for multi-BLK waterbodies is meaningless. Use wscode_ltree for network-topological ordering.
- `fwa_lakes_poly` and `fwa_manmade_waterbodies_poly` are split by digitization origin, not ecology. A 200ha reservoir functions identically to a 200ha lake for fish rearing.
- Downstream trace (distance cap + gradient stop) is a generic network operation — extract as reusable building block, don't embed in use-case-specific functions.
- Name internal functions by mechanism (`.frs_connected_waterbody`) not use-case (`.frs_connected_spawning`).

## Closed By

PR #152

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
