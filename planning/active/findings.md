# Findings: Issue #133

The `requires_connected` predicate uses `frs_cluster()` which already has a `bridge_distance` parameter. But that's the distance cap for the GRADIENT BRIDGE check (how far to search for spawning downstream of rearing), not a cap on how far spawning can be from rearing.

What #133 needs is different: after clustering identifies valid clusters (connected to rearing), REMOVE individual segments within valid clusters that are too far from the nearest rearing segment. This is a post-cluster distance filter, not a bridge distance.

Two approaches:
A) Add a distance filter AFTER frs_cluster — measure network distance from each spawning segment to the nearest rearing segment, remove those > connected_distance_max
B) Use bridge_distance on frs_cluster as a proxy — frs_cluster's bridge_distance already caps how far to search. If set to 3000, clusters more than 3km from rearing are already removed. But segments WITHIN a valid cluster could still be > 3km from the actual rearing segment if the cluster is large.

Approach A is more precise. But approach B is simpler and may be sufficient for the use case (SK spawning within 3km of lake). The SK rearing lake generates rearing segments ON the lake — so the "distance to rearing" is the distance to the lake flow line, not to the lake shore.

Actually, looking at frs_cluster more carefully: the `bridge_distance` parameter only applies to the DOWNSTREAM direction trace. The upstream direction has no distance cap. For `requires_connected: rearing` on SK spawning, spawning must connect to rearing. The connection direction depends on `cluster_spawn_direction` in params_fresh (currently "both" for SK).

Simplest approach: read `connected_distance_max` from the rule, and pass it as the `bridge_distance` override to `frs_cluster()` in `.frs_run_connectivity()`. This overrides the CSV's `cluster_spawn_bridge_distance`. If the rule sets 3000, the cluster search is capped at 3km in the downstream direction, which is what bcfishpass does.

But this doesn't cap the UPSTREAM direction. bcfishpass's Phase 2 (spawning upstream of lake) uses FWA_Upstream with clustering — no explicit distance cap in the SQL, just connectivity. So the 3km cap only applies to downstream spawning (Phase 1 — outlet spawning).

For now: use `connected_distance_max` as the bridge_distance override for frs_cluster. This handles the primary case (capping downstream spawning distance from lake outlet). The upstream direction is uncapped — matching bcfishpass Phase 2 behavior.
