# Findings

## Root cause: upstream path gradient is fundamentally broken
FWA_Upstream() returns ALL upstream segments including tributaries. For one ADMS cluster, this is 4,770 segments. row_number() ordered by wscode places tributary segments between adjacent mainstem segments. A steep tributary gets a lower row_number than nearby spawning on the mainstem, incorrectly disconnecting rearing that has spawning 123m away with zero gradient.

The downstream trace (fwa_downstreamtrace) is linear — it follows the mainstem only. row_number works because there are no branches. The upstream network branches — path gradient can't work with row_number on a tree.

## Resolution
- **Upstream**: boolean FWA_Upstream check (spawning exists anywhere upstream). No gradient/distance constraint.
- **Downstream**: path-based gradient check via fwa_downstreamtrace. Segment-by-segment, row_number works because trace is linear.
- **Both**: upstream boolean + downstream path gradient. Valid if connected in either direction.

## Why downstream-only path gradient is correct
bcfishpass only applies path gradient checking downstream. The downstream trace follows the mainstem via fwa_downstreamtrace which returns segments in network order. The upstream check is always boolean. The CH rearing +6% excess is from the downstream check — this issue adds the path gradient/distance constraints to the downstream trace in frs_cluster (already present in .frs_cluster_downstream, just needs to be exercised via direction="both").

## Species with cluster_rearing = TRUE
| Species | Direction | bridge_gradient | bridge_distance |
|---------|-----------|-----------------|-----------------|
| CH | both | 0.05 | 10000 |
| CO | both | 0.05 | 10000 |
| SK | both | 0.05 | 10000 |
| ST | both | 0.05 | 10000 |
| WCT | both | 0.05 | 10000 |
