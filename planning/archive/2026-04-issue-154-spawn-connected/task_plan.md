# Task Plan: Issue #154 — spawn_connected rules

## Phase 1: Parser — recognize spawn_connected block
- [x] Add `spawn_connected` as valid habitat block in `.frs_load_rules()` (alongside `spawn`, `rear`)
- [x] Add `.frs_validate_spawn_connected()` — validate fixed keys
- [x] Attach `$rules$spawn_connected` to species params (flows through existing attachment code)
- [x] Tests: 5 new tests (valid parse, unknown keys, missing keys, invalid direction, params attachment)
- [x] 102 params tests pass, code-check clean
- [x] Commit + code-check

## Phase 2+3: Additive step + wire through dispatcher
- [x] Keep `lfid_tbl` alive past Phase 1 for Phase 3
- [x] Add `spawn_connected` param to `.frs_connected_waterbody()`
- [x] Phase 3 additive UPDATE: spawning = TRUE for accessible segments in trace meeting permissive thresholds
- [x] Edge type filter (optional), channel_width_min (skip if 0), gradient_max (always)
- [x] Wire through: `ps[["rules"]][["spawn_connected"]]` → `.frs_connected_waterbody(spawn_connected=)`
- [x] Drop lfid_tbl after Phase 3
- [x] 705 tests pass, code-check clean
- [x] Commit + code-check

## Phase 4: PR
- [ ] Push, create PR with SRED tag
