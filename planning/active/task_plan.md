# Task Plan: Issue #154 — spawn_connected rules

## Phase 1: Parser — recognize spawn_connected block
- [ ] Add `spawn_connected` as valid habitat block in `.frs_load_rules()` (alongside `spawn`, `rear`)
- [ ] Add `.frs_validate_spawn_connected()` — validate fixed keys: `direction`, `waterbody_type`, `gradient_max`, `channel_width_min`, `distance_max`, `bridge_gradient`
- [ ] Attach `$rules$spawn_connected` to species params (single block, not list of rules)
- [ ] Tests: parse valid spawn_connected, error on unknown keys, error on missing required keys
- [ ] Commit + code-check

## Phase 2: Additive step in .frs_connected_waterbody
- [ ] Keep `lfid_tbl` alive past Phase 1 (currently dropped after mapping to id_segments)
- [ ] After Phase 2 (subtractive), add Phase 3: UPDATE spawning = TRUE for segments where:
  - `linear_feature_id IN lfid_tbl` (in the downstream trace)
  - `accessible IS TRUE` (from habitat table)
  - `gradient <= gradient_max`
  - `channel_width >= channel_width_min` (or channel_width_min = 0 skips check)
  - edge_type filter if present in spawn_connected
- [ ] Pass spawn_connected config into `.frs_connected_waterbody()`
- [ ] Drop `lfid_tbl` after Phase 3
- [ ] Tests
- [ ] Commit + code-check

## Phase 3: Wire through frs_habitat dispatcher
- [ ] Read `spawn_connected` from `params[[sp]]$rules$spawn_connected`
- [ ] Pass to `.frs_connected_waterbody()` call
- [ ] Commit + code-check

## Phase 4: PR
- [ ] Push, create PR with SRED tag
