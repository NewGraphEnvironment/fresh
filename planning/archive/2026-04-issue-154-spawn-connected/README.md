## Outcome

Added `spawn_connected` rules block support. Parser validates fixed keys (direction, waterbody_type, gradient_max, channel_width_min, distance_max, bridge_gradient) separately from spawn/rear rules. Additive step in `.frs_connected_waterbody()` promotes accessible segments in the downstream trace that meet permissive thresholds but failed standard classification. BULK SK spawning from -9.6% to -0.7% vs bcfishpass (24.22 km vs 24.38 km).

## Key Learnings

- spawn_connected is a single config block, not a list of rules — different validation from spawn/rear.
- The additive step reuses lfid_tbl from Phase 1 (downstream trace). Keep temp tables alive when downstream phases need them.
- Fresh ships its own default YAML. Link ships bcfishpass-specific YAML. Fresh parses whatever YAML it receives — no need to bundle link's rules.
- channel_width_min = 0 means no channel width filter. edge_types absent = all edge types qualify.

## Closed By

PR #155

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
