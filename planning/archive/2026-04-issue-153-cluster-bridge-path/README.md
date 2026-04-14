## Outcome

Downstream cluster check now applies bridge_gradient and bridge_distance segment-by-segment along the fwa_downstreamtrace path. Upstream check remains boolean FWA_Upstream. CH rearing excess reduced from +6% on BULK.

## Key Learnings

- FWA_Upstream returns all upstream segments including tributaries. row_number() on a branching network interleaves tributary segments with mainstem — a steep tributary gets a lower rn than nearby mainstem spawning. Path gradient checking cannot work with row_number on a tree structure.
- fwa_downstreamtrace is linear (follows mainstem only) — row_number works because there are no branches. Path gradient is reliable downstream only.
- direction="both" correctly combines: upstream boolean (spawning exists anywhere upstream) + downstream path gradient (segment-by-segment gradient/distance check).

## Closed By

PR #157

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
