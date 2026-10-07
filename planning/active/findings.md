# Findings — `.frs_rule_to_sql()` ignores `wetland_ha_min` (#237)

## Issue context

**If done:** a `waterbody_type: W` rule with `wetland_ha_min` admits only wetlands at least that big, in the `rearing` predicate as well as in `wetland_rearing`. **If never:** a bundle that declares `wetland_ha_min: 1.0` gets rearing on stream edges in wetlands of any size, and the declared floor reaches only the `wetland_rearing` column.

## Problem

`frs_params.R` validates `wetland_ha_min` on a W rule (fresh#168 added it to the allowlist), and `build_wb_pred()` (`R/frs_habitat_predicates.R`) applies it to `wetland_rear_pred`. `.frs_rule_to_sql()` (`R/utils.R`), which compiles the main rear predicate, reads only `lake_ha_min`:

```r
if (!is.null(rule[["lake_ha_min"]])) { ... area_ha >= ... } else { SELECT waterbody_key FROM <tables> }
```

So link's `default` BT and RB rear rule

```yaml
- waterbody_type: W
  edge_types_explicit: [1000, 1100]
  wetland_ha_min: 1.0
```

compiles to `(s.edge_type IN (1000, 1100) AND s.waterbody_key IN (SELECT waterbody_key FROM whse_basemapping.fwa_wetlands_poly))`, with no area clause (fresh@v0.36.2).

Measured in link's `fresh_default` (55 WSGs): 159,876 of 375,178 wetland polygons are under 1 ha; 2,270 segments (108 km) sit in them, 1,566 (76 km) BT-accessible.

Found while measuring discharge at observations for link#302: a classifier written from `rules.yaml` disagreed with the compiled predicate.

## Proposed Solution

In `.frs_rule_to_sql()`, take the area floor from `lake_ha_min` for `L` and `wetland_ha_min` for `W` (or either key for either type, as `frs_params` validates). Check whether any bundle relies on today's behaviour before changing it; link's `default*` bundles declare `rear_wetland_ha_min` in `dimensions.csv` (1 for BT/RB/CH/ST, 0.5 for CO), so outputs would move.

Relates to fresh#168.


## Plan-mode exploration (2026-10-07)

- The loader (`.frs_load_rules`, `R/frs_params.R:256-286`) ties `lake_ha_min` to `L` only and `wetland_ha_min` to `W` only. The compiler should read the floor the same way.
- `build_wb_pred()` already reads the type's key (`ha_key` argument), so `wetland_rearing` is right and `rearing` is wrong. Two readers of one fact drifted.
- Fresh's bundled `inst/extdata/parameters_habitat_rules.yaml` has a `W` rear rule with `wetland_ha_min` for BT, CH, CO (0.5), ST, WCT and RB, so bundled defaults move, not only link's.
- A third copy is in `R/frs_habitat.R:1254`: the waterbody-connected spawning path (`.frs_connected_waterbody()`) reads only `lake_ha_min` and defaults to 200 ha. A `W`-first rear rule with `requires_connected` spawning would get 200 ha regardless of `wetland_ha_min`. No bundled species hits it (SK, KO are `L` only).
- `data-raw/vignette_habitat_pipeline.R` uses `frs_classify()` directly, not the rules YAML.

## Plan-agent review (2026-10-07)

No blockers. Folded into `task_plan.md` as `(review)` items: an NA-floor guard in the helper, a test for the `frs_habitat.R:1254` path, a spawn-rule test, `.frs_validate_rule` docs, and a sounder Phase 3 design (real `sp_params`, old/new on one branch, model per WSG, agreement with persisted `rearing`, a Pacific WSG for CO).

Two points to carry into NEWS:
- **"If done" holds per rule, not per predicate.** Bundled and link rear rules include `edge_types_explicit: [1050, 1150], thresholds: false`, which admits wetland-flow lines in wetlands of any size. The `W` rule with its floor only adds stream edges (1000 / 1100) that the stream rule rejects: cw < 1.5, NULL cw, or steeper than the inherited gradient. So the delta is smaller than the issue's 76 km of BT-accessible segments in small wetlands. Whether the 1050 / 1150 carve-out should also take a floor is a separate question for the user.
- **The `bcfishpass` bundle has no `W` rules** and does not move.
