# Findings

## Problem
SK spawning near lake outlets uses more permissive thresholds than standard spawning — wider gradient tolerance, no channel width minimum, all edge types. The current subtractive-only approach removes spawning not in the trace but can't ADD spawning for segments that fail standard classification but meet the connected rules. BULK SK: 22.04 km vs 24.38 km bcfishpass (-9.6%).

## spawn_connected block format
Single configuration block per species (not a list of rules like spawn/rear):
```yaml
SK:
  spawn_connected:
    direction: downstream
    waterbody_type: L
    gradient_max: 0.05
    channel_width_min: 0.0
    distance_max: 3000.0
    bridge_gradient: 0.05
```

Valid keys: direction, waterbody_type, gradient_max, channel_width_min, distance_max, bridge_gradient.
Own validation — does NOT mix with spawn/rear valid_predicates.
Never inherits from CSV thresholds — defines its own.

## Flow in .frs_connected_waterbody
1. Phase 1: downstream trace from waterbody outlets → lfid_tbl (keep alive)
2. Phase 2: upstream cluster + waterbody proximity → subtractive prune
3. **Phase 3 (new)**: additive step — set spawning = TRUE for accessible segments in lfid_tbl that meet spawn_connected thresholds
4. Drop lfid_tbl

## Design decisions
- Fresh ships its own default rules YAML. Link ships bcfishpass-specific YAML separately. Fresh parses whatever YAML it receives.
- spawn_connected is a single config block, not a rule list — no OR semantics needed.
- Accessible gate: only accessible IS TRUE segments get promoted.
- edge_types absent = all edge types qualify in trace zone.
- channel_width_min = 0 means no channel width filter.
