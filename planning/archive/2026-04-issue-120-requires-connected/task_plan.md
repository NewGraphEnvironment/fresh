# Task: SK/KO spawning requires connected rearing (issue #120)

## Goal
Add `requires_connected` predicate to the rules YAML. When a spawn rule has `requires_connected: rearing`, spawning segments must be spatially connected to rearing segments via `frs_cluster()`. Disconnected spawning gets set to FALSE.

## Status: complete

## Key design questions

1. **Where does the connectivity check run?**
   - Option A: Inside `frs_habitat_classify()` — but it doesn't have cluster params (bridge_gradient, bridge_distance, confluence_m)
   - Option B: Inside `frs_habitat()` — has both params and params_fresh, already calls classify
   - Option C: User calls `frs_cluster()` manually
   
   **Recommendation: Option B** — `frs_habitat()` orchestrates. After classify, scan species rules for `requires_connected`, call `frs_cluster()` with params from `parameters_fresh.csv`.

2. **What cluster params for SK/KO spawning?**
   - bcfishpass uses 3km distance for SK spawning-lake connectivity (vs 10km for rearing-spawning)
   - Need new columns in `parameters_fresh.csv`: `cluster_spawning`, `cluster_spawn_direction`, `cluster_spawn_bridge_gradient`, `cluster_spawn_bridge_distance`
   - Or: reuse the existing cluster columns with a convention that `frs_cluster()` direction is reversed

3. **Does `frs_habitat_classify()` need to know about `requires_connected`?**
   - No — it just classifies. The connectivity filter runs AFTER classification.
   - `requires_connected` is a post-classification instruction consumed by the orchestrator.

4. **What about standalone `frs_habitat_classify()` users?**
   - They won't get the connectivity filter automatically
   - They can call `frs_cluster()` manually after classify
   - Document this clearly

## Phases

- [ ] Branch + PWF
- [ ] Add `requires_connected` to valid predicates (just accept it, no error)
- [ ] Add cluster_spawning columns to `parameters_fresh.csv`
- [ ] Wire `frs_habitat()` to call `frs_cluster()` after classify for species with `requires_connected` rules
- [ ] Update bundled YAML: SK/KO spawn rules get `requires_connected: rearing`
- [ ] Integration test: ADMS SK spawning = 0 (no lakes >= 200 ha → no rearing → no connected spawning)
- [ ] Code-check
- [ ] PR + merge + NEWS + archive
