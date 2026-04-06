# Refactor frs_habitat → unified pipeline

## Goal

Rewrite `frs_habitat()` to wrap `frs_network_segment()` + `frs_habitat_classify()` instead of the old `frs_habitat_partition()` + `frs_habitat_species()`. Support province-wide runs, mirai parallel, `to_streams`/`to_habitat` output params.

## Current State

- `frs_network_segment()` — exported, tested, working
- `frs_habitat_classify()` — exported, tested, working
- `frs_habitat()` — still uses old pipeline (partition + species)
- Old functions: `frs_habitat_partition`, `frs_habitat_species`, `frs_habitat_access` — to deprecate

## Key Design Decisions

- `to_streams` + `to_habitat` params on `frs_habitat()` (not `to_prefix`)
- Gradient barriers generated per WSG inside the function (user doesn't pre-generate)
- Access thresholds derived from `params_fresh$access_gradient_max` per species
- Labels: `gradient_{pct}` for gradient barriers, user controls labels for break_sources
- mirai parallel: each worker runs segment + classify for one WSG
- Workers need `password` param for DB reconnection

## Phases

### Phase 1: Rewrite frs_habitat [pending]
- New params: `to_streams`, `to_habitat`, `break_sources`, `password`, `workers`
- Remove: `to_prefix`, `falls`, `falls_where` (already removed in earlier work)
- Flow per WSG:
  1. Generate gradient barriers at all unique access thresholds
  2. `frs_network_segment(aoi = wsg, to = working_table, break_sources = gradient + user sources)`
  3. `frs_habitat_classify(table = working_table, to = to_habitat, species = wsg_species)`
  4. Append working_table to `to_streams` (if provided)
  5. Clean up working tables
- mirai: each WSG is one task, workers run the full per-WSG flow

### Phase 2: Test [pending]
- Sequential: single WSG (ADMS)
- Sequential: multi-WSG (ADMS + BULK)
- Parallel: multi-WSG with mirai (4 workers)
- Verify species-specific accessibility (CO < ST < BT)
- Verify persistent tables accumulate across WSGs
- Run devtools::test() — 528 should still pass

### Phase 3: Benchmark + province test [pending]
- Script for province-wide run using the refactored frs_habitat
- Compare timing to old pipeline
- Log to scripts/habitat/logs/

### Phase 4: Deprecate old functions [pending]
- Add .Deprecated() to frs_habitat_partition, frs_habitat_species, frs_habitat_access
- Update CLAUDE.md architecture section
- NEWS.md + version bump to v0.8.0

## Files to Modify

- `R/frs_habitat.R` — rewrite main function
- `R/frs_habitat.R` — add .Deprecated to old functions
- `man/frs_habitat.Rd` — regenerate
- `scripts/habitat/habitat_province.R` — update to use frs_habitat()
- `NEWS.md` — v0.8.0 entry
- `DESCRIPTION` — version bump

## Errors Encountered

(none yet)
