# Findings

The generic frs_cluster approach can't replicate bcfishpass SK spawning because:
1. Downstream: needs cumulative fwa_downstreamtrace distance with sequential gradient stop — not a cluster operation
2. Upstream: needs st_dwithin against lake POLYGON, not just network connectivity to rearing segments

Replace with two-phase `.frs_connected_spawning()` for species where `requires_connected` targets lake-type rearing.

Detection: check if the species' rearing rules include `waterbody_type: L`. If yes, dispatch to two-phase. If no, use generic frs_cluster (future use cases).
