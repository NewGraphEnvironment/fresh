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

## Live measurement (2026-10-07)

`data-raw/rear_wetland_floor_check.R` on link's persisted `fresh_default`, local fwapg, link `default` config. All three groups are `cw`. Logs are in `data-raw/logs/rear_wetland_floor_237/`: `<wsg>_<sp>.csv`, `_edge.csv` and the `.txt` stamp. Every cell below is **segments (km)** and is copied from those CSVs, with the column named.

"Sub-floor wetland" means a wetland `waterbody_key` with no polygon of `area_ha >= floor`. That is the complement of the W rule's own test, since a key can have several polygons. A first pass used "any polygon < floor" and overcounted; code-check p3 round 1 caught it.

**What the fix removes**

| WSG / sp | floor (ha) | rear predicate, old → new segments | dropped by predicate (`dropped_*`) | dropped from persisted rearing (`dropped_persisted_*`) | wetland keys touched |
|---|---|---|---|---|---|
| NATR BT | 1 | 12,222 → 12,160 | 62 (3.0) | 40 (2.1) | 49 |
| PARS BT | 1 | 11,859 → 11,782 | 77 (3.8) | 60 (3.1) | 64 |
| BULK CO | 0.5 | 8,017 → 8,012 | 5 (0.1) | 2 (0.0) | 5 |

- **Persisted rearing ⊆ old predicate in all three groups** (`persisted_only_n = 0`). The old-only segments are consistent with link's `cluster_rearing` removing them afterwards, but that direction wasn't checked.
- **Nothing gains** (`gained_n = 0`).
- **The persisted loss is a lower bound.** link reruns `cluster_rearing` (TRUE for BT and CO in `default`) on the narrower set, and that can drop more.
- **The delta is small** because the W rule only contributes stream edges (1000 / 1100) that the stream rule rejects. Every dropped segment is on 1000 / 1100 in a sub-floor wetland (code-check p3 round 2).

**What stays in sub-floor wetlands**, admitted by other rules

| WSG / sp | admitted by new predicate (`small_wetland_new_*`) | persisted rearing the new predicate keeps (`small_wetland_kept_*`) | of which edge 1050 / 1150 (`_edge.csv` `kept_*`) |
|---|---|---|---|
| NATR BT | 596 (49.5) | 315 (27.0) | 307 (26.4) |
| PARS BT | 381 (28.9) | 247 (19.3) | 244 (19.1) |
| BULK CO | 35 (2.6) | 18 (1.3) | 18 (1.3) |

- **Edge 1050 / 1150** lines are wetland-flow, admitted by the `edge_types_explicit: [1050, 1150], thresholds: false` carve-out, which has no area floor. Kept is computed before link reruns `cluster_rearing`, so it is an upper bound.
- **The other kept segments are 1000-edge lines admitted by the stream rule:** NATR 8 (0.5 km), PARS 3 (0.2 km).
- **The carve-out floor is out of scope.** Whether the carve-out should take the wetland floor is a bundle design question for link, not part of #237.

## NEWS draft (for `/gh-pr-merge`'s release commit)

Prior branches (#240, #229, #223) left NEWS to the `Release vX.Y.Z` commit, so the entry is drafted here rather than committed to `NEWS.md` on the branch. Outputs move for most bundles, so a minor bump fits the #240 precedent.

```markdown
Closes [#237](https://github.com/NewGraphEnvironment/fresh/issues/237).

**A wetland rule's `wetland_ha_min` now gates `rearing`, not only `wetland_rearing`.**
- The compiler for the main `spawn` / `rear` predicates read only `lake_ha_min`, so a `waterbody_type: W` rule admitted wetlands of every size. The floor now comes from the key of the rule's type (`lake_ha_min` on `L`, `wetland_ha_min` on `W`) through one internal reader. The lake / wetland bucket predicates and the waterbody-connected spawning pass use the same reader.
- **Rearing moves for every bundle with a wetland floor:** fresh's bundled rules and link's `default*` (BT, CH, CO, RB, ST, WCT). The `bcfishpass` bundle has no `W` rules and is unchanged. On link's `fresh_default`, persisted rearing loses at least 40 segments (2.1 km) for NATR BT, 60 (3.1 km) for PARS BT and 2 for BULK CO. It is "at least" because `cluster_rearing` reruns on the narrower set. The change is small because the stream rule already admits most stream edges in wetlands (`data-raw/logs/rear_wetland_floor_237/`).
- The floor holds per rule, not per predicate. Other rear rules still admit segments in smaller wetlands, chiefly the `edge_types_explicit: [1050, 1150], thresholds: false` wetland-flow rule. For NATR BT, about 307 segments (26.4 km) of rearing sit on wetland-flow lines in wetlands under 1 ha. That is an upper bound until `cluster_rearing` reruns.
- The rules loader now rejects an `NA` / `NaN` `lake_ha_min` or `wetland_ha_min`. Before, it compiled to invalid SQL.
- For waterbody-connected spawning on a species whose first lake / wetland rear rule is `W`, the floor is now its `wetland_ha_min` rather than the 200 ha default. No bundled species takes that path.
```
