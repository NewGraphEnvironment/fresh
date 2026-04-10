# Findings: Issue #120

## The pattern

SK/KO spawning requires proximity to a qualifying rearing lake. bcfishpass implements this as a 2-phase trace (downstream + upstream from lake outlets, 3km cap, 5% gradient bridge). 

In fresh, this maps cleanly to `frs_cluster()` with reversed labels:
- `label_cluster = "spawning"` (what to check)
- `label_connect = "rearing"` (what it must connect to)
- `bridge_distance = 3000` (3km, bcfishpass SK value)
- `bridge_gradient = 0.05`

The `requires_connected` predicate in the YAML signals that a species' spawn/rear classification needs a post-classification connectivity check.

## Implementation path

1. `requires_connected` is a hint consumed by `frs_habitat()`, NOT by `frs_habitat_classify()`
2. After classify runs, the orchestrator scans species rules for `requires_connected`
3. For each match, call `frs_cluster()` with the appropriate label swap
4. Cluster params come from `parameters_fresh.csv` (new columns)

## What needs to change

- `R/frs_params.R` — accept `requires_connected` as valid predicate
- `R/frs_habitat.R` — post-classify cluster call for species with `requires_connected`
- `inst/extdata/parameters_fresh.csv` — add cluster_spawning columns for SK/KO
- `inst/extdata/parameters_habitat_rules.yaml` — SK/KO spawn rules get `requires_connected: rearing`
