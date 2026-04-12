# Task: connected_distance_max predicate (#133)

## Goal
Add `connected_distance_max` predicate to rules YAML. When used with `requires_connected`, segments further than this distance from the connected habitat type are removed. Caps SK spawning at 3km from rearing lake.

## Status: in progress

## Phases
- [x] Branch + PWF
- [x] Add `connected_distance_max` to valid predicates + validation (requires `requires_connected`)
- [x] Read from rules in `.frs_run_connectivity()`, override `bridge_distance` for `frs_cluster()`
- [x] Update bundled YAML: SK/KO spawn rules get `connected_distance_max: 3000`
- [x] 4 new tests, 675 total pass
- [ ] Code-check
- [ ] PR + merge + NEWS + archive
