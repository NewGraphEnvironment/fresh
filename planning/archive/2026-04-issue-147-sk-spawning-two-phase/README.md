## Outcome

Two-phase connected spawning for SK/KO matching bcfishpass v0.5.0. Phase 1 downstream trace + Phase 2 upstream cluster with lake proximity. Auto-dispatched when rearing has waterbody_type: L.

## Key Learnings

- Subtractive approach (remove non-qualifying) preserves spawn threshold classification. Additive (set FALSE then TRUE) loses threshold info.
- lake_ha_min must be read from rearing rules, not hardcoded — code-check caught this.
- Two fundamentally different algorithms (downstream trace vs upstream cluster) can't be replicated by a single generic frs_cluster call.

## Closed By

PR #148

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
