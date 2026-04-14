# Findings

## Current architecture
- `frs_cluster(direction="both")` evaluates upstream and downstream independently
- **Downstream** (`.frs_cluster_downstream`): traces via `fwa_downstreamtrace`, applies `bridge_gradient` and `bridge_distance` segment-by-segment. Correct.
- **Upstream** (`.frs_cluster_upstream`): uses `FWA_Upstream()` to check if spawning exists ANYWHERE upstream. No gradient or distance constraint. Too permissive.
- **Both** (`.frs_cluster_both`): cluster valid if connected in EITHER direction. Upstream check passes clusters that downstream would reject.

## Root cause hypothesis
CH uses `direction=both`. A rearing cluster downstream of a >5% gradient has spawning far upstream past the steep section. The upstream check says "yes, spawning exists upstream" (ignoring gradient). The downstream check would reject it (gradient barrier before spawning). But `both` keeps it because upstream passed.

The upstream check needs the same bridge_gradient/bridge_distance constraints as downstream, but applied in the upstream direction.

## bcfishpass approach (load_habitat_linear_ch.sql Phase 3)
1. Cluster rearing with ST_ClusterDBSCAN
2. Trace downstream from each cluster minimum via FWA_Downstream
3. Cap at 10km (bridge_distance), assign row_number() sequentially
4. Find first segment with gradient >= 0.05 (bridge_gradient)
5. Find nearest downstream spawning
6. Keep cluster only if spawning rn < gradient_barrier rn

Key difference: bcfishpass only traces DOWNSTREAM for CH rearing cluster validation. It doesn't check upstream at all. The `direction=both` in our params may be wrong for this species, or the upstream check needs gradient constraints.

## Species with cluster_rearing = TRUE
| Species | Direction | bridge_gradient | bridge_distance |
|---------|-----------|-----------------|-----------------|
| CH | both | 0.05 | 10000 |
| CO | both | 0.05 | 10000 |
| SK | both | 0.05 | 10000 |
| ST | both | 0.05 | 10000 |
| WCT | both | 0.05 | 10000 |
