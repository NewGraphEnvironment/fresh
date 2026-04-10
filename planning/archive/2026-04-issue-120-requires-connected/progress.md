# Progress: Issue #120

### 2026-04-09
- Issue reviewed, design planned
- Key decision: `requires_connected` is consumed by `frs_habitat()` orchestrator, not by `frs_habitat_classify()`
- Added `requires_connected` to valid predicates + validation
- Added cluster_spawning columns to parameters_fresh.csv (SK/KO = TRUE, 3km distance)
- Added KO row to parameters_fresh.csv (was missing)
- Updated bundled YAML: SK/KO spawn rules get `requires_connected: rearing`
- New `.frs_run_connectivity()` helper in frs_habitat.R — runs rearing cluster + spawning connectivity checks
- Wired into both sequential and mirai branches after classify
- ADMS verification: SK spawning 15 → 0 (no rearing lake ≥ 200 ha → all spawning disconnected)
- Fixed test: CO rearing assertion updated (cluster check removes 1 segment)
- 657 tests pass
