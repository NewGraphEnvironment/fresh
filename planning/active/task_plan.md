# Task: `.frs_rule_to_sql()` ignores `wetland_ha_min`, so the rear predicate admits wetlands of every size (#237)

`frs_params.R` validates `wetland_ha_min` on a W rule (fresh#168 added it to the allowlist), and `build_wb_pred()` (`R/frs_habitat_predicates.R`) applies it to `wetland_rear_pred`. `.frs_rule_to_sql()` (`R/utils.R`), which compiles the main rear predicate, reads only `lake_ha_min`, so a `W` rule with `wetland_ha_min: 1.0` compiles with no area clause and `rearing` admits wetlands of any size.

## Phase 1: Failing tests
- [ ] `test-frs_params.R`: `.frs_rule_to_sql(list(waterbody_type = "W", wetland_ha_min = 1))` → `fwa_wetlands_poly WHERE area_ha >= 1`
- [ ] `test-frs_params.R`: a `W` rule with no floor keeps an unfiltered `SELECT waterbody_key FROM ...fwa_wetlands_poly` (pins current behaviour)
- [ ] `test-frs_params.R`: a floor key on the wrong type is not applied (a `W` rule carrying `lake_ha_min` → no area clause). Same contract as the loader and `build_wb_pred()`
- [ ] `test-frs_habitat_predicates.R`: `rear` predicate from a `W` rule with `wetland_ha_min = 1.5` carries `area_ha >= 1.5` (the issue's "if done" line). Also check `rear` and `wetland_rear` use the same floor
- [ ] `test-utils.R`: new helper `.frs_rule_ha_min()` returns the `L` floor, the `W` floor, and `NULL` for `R` / no type / a mismatched key
- [ ] Confirm the new tests fail on `main` behaviour
- [ ] (review) `test-utils.R`: `.frs_rule_ha_min()` returns `NULL` for an `NA` floor (keeps `build_wb_pred()`'s `!is.na` guard; `.frs_sql_num(NA)` would emit invalid SQL)
- [ ] (review) `test-frs_habitat_predicates.R`: a spawn `W` rule with `wetland_ha_min` gets the floor too (`.frs_rules_to_sql()` compiles spawn rules)
- [ ] (review) `test-frs_habitat.R`: `.frs_run_connectivity()` passes a `W`-first rear rule's `wetland_ha_min` to `.frs_connected_waterbody()` as `waterbody_ha_min` (mock pattern at `test-frs_habitat.R:549`)

## Phase 2: Fix — one place that reads the floor
- [ ] Add `.frs_rule_ha_min(rule)` to `R/utils.R`, next to `.frs_find_waterbody_rule()`: `lake_ha_min` for `L`, `wetland_ha_min` for `W`, otherwise `NULL`
- [ ] `.frs_rule_to_sql()`: use the helper in place of `rule[["lake_ha_min"]]`. Collapse the duplicated if/else into one `vapply` with an optional `WHERE`. Update the `@param rule` doc to list `wetland_ha_min` and fix the comment at `utils.R:241`
- [ ] (review) `.frs_validate_rule` roxygen (`frs_params.R:208`) names `wetland_ha_min` alongside `lake_ha_min`
- [ ] `build_wb_pred()` (`frs_habitat_predicates.R:193`): drop the `ha_key` argument and use the helper, so `rear` and the bucket can't drift apart again
- [ ] `frs_habitat.R:1254`: read the floor through the helper, keeping the 200 ha default when absent. Comment why
- [ ] Grep for any other `lake_ha_min` reader that should be type-aware. `frs_params.R:562` `rear_lake_ha_min` → `ranges$lake_ha` is CSV-side with no consumer; leave it and note it in findings
- [ ] Confirm the vignette cached data doesn't depend on rules YAML (`example_byman_ailport.R`)
- [ ] `devtools::test()` green, `lintr` clean, `devtools::document()`

## Phase 3: Live measurement
- [ ] `data-raw/rear_wetland_floor_check.R`: on link's persisted `fresh_default` for NATR and PARS (BT), plus a Pacific WSG for CO at 0.5 ha (CO isn't in NATR / PARS), evaluate the full compiled `rear` predicate old vs new on accessible segments. Report segments / km that leave `rearing`. This is net of the stream-edge rule, which can still admit a segment in a small wetland. Write logs to `data-raw/logs/rear_wetland_floor_237/`
  - (review) Build real `sp_params` from link's `rules.yaml` + `parameters_habitat_thresholds.csv` via `frs_params()`, in `frs_habitat_classify()`'s shape. `ranges = list()` would drop the inherited thresholds on the stream rule
  - (review) "Old" = the same rules with `wetland_ha_min` removed from the W rule. Count `accessible AND old AND NOT new`, on one branch
  - (review) Read the model per WSG from link's `parameters_habitat_method.csv` and pass `model =`
  - (review) Report agreement of the reconstructed old predicate with persisted `rearing`, and the delta both on the predicate alone and intersected with persisted `rearing`
- [ ] Record the numbers in `findings.md`

## Phase 4: Release notes and handoff
- [ ] NEWS.md entry: what changed, that bundled and link `default*` rearing moves, and the measured delta. The version bump is left to `/gh-pr-merge`
- [ ] Tell link its `default*` bundle outputs move (comms thread or link issue). Confirm wording and channel with the user before posting

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
