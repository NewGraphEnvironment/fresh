## Outcome

A `waterbody_type: W` rule's `wetland_ha_min` now gates `rearing` (and `spawning`), not only `wetland_rearing`.
- **Cause:** `.frs_rule_to_sql()` read only `lake_ha_min`, so the main predicates admitted wetlands of every size. A second copy of the bug made the waterbody-connected spawning pass read only `lake_ha_min`, defaulting to 200 ha.
- **Fix:** `.frs_rule_ha_min()` now pairs each type with its key (`lake_ha_min` on L, `wetland_ha_min` on W). All three readers go through it: the rule compiler, the bucket predicates and the connectivity floor.
- **Loader:** it now rejects an empty, null, NA or NaN floor. Those would otherwise mean "no floor".
- **What changes:** every bundle with a wetland floor (fresh's bundled rules and link's `default*`: BT, CH, CO, RB, ST, WCT). The `bcfishpass` bundle has none.

What was learned:
- **Two readers of one fact drifted.** The bucket predicate read the right key; the main compiler didn't. One helper ends that.
- **Guards that fail toward "no floor" need loader rejection on every route to NULL / NA.** Code-check found NA (round 2), then empty YAML values (round 3, inside the round-2 fix). A 128-case sweep of key × type × value ended the loop.
- **A per-key area test must use the complement of the rule's own test.** A wetland key can have several polygons. The measurement's first cut used "any polygon < floor" and overcounted. See [research/fwa_waterbody_key_polygons.md](../../../research/fwa_waterbody_key_polygons.md).
- **The fix holds per rule, not per predicate.** Most rearing left in small wetlands sits on 1050 / 1150 wetland-flow lines, admitted by a separate rule with no floor. That is raised with link as link#311.

## Measurement

These come from `data-raw/rear_wetland_floor_check.R` on link's persisted `fresh_default` with link's `default` config, at `487f0cc`. All three groups are on the `cw` model. Cells are segments (km).

| WSG / sp | floor (ha) | dropped by predicate | dropped from persisted rearing (lower bound) | kept in sub-floor wetlands | of which 1050 / 1150 |
|---|---|---|---|---|---|
| NATR BT | 1 | 62 (3.0) | 40 (2.1) | 315 (27.0) | 307 (26.4) |
| PARS BT | 1 | 77 (3.8) | 60 (3.1) | 247 (19.3) | 244 (19.1) |
| BULK CO | 0.5 | 5 (0.1) | 2 (0.0) | 18 (1.3) | 18 (1.3) |

- **Smaller than the issue's 76 km.** The stream rule already admits most 1000 / 1100 lines in wetlands, so the W rule only added the ones that fail its gradient or width test.
- **The reconstruction matches link.** Persisted rearing ⊆ the old predicate in all three groups. "Lower bound" because link's `cluster_rearing` reruns on the narrower set.
- **Multi-polygon keys** (fwapg, 2026-10-07): `fwa_wetlands_poly` has 333,526 keys. 19,510 have more than one polygon, up to 1,688; 6,730 straddle 1 ha. `fwa_lakes_poly` has 9 multi-polygon keys. Query:
  `SELECT count(*) FILTER (WHERE n > 1), max(n), count(*) FILTER (WHERE mn < 1 AND mx >= 1) FROM (SELECT waterbody_key, count(*) n, min(area_ha) mn, max(area_ha) mx FROM whse_basemapping.fwa_wetlands_poly GROUP BY 1) k`
- **Tests:** `devtools::test()` FAIL 0 / PASS 1254. The 3 warnings come from the existing live network-features tests.

## Evidence

- `data-raw/logs/rear_wetland_floor_237/*`
- `data-raw/rear_wetland_floor_check.R`
- review records: `review-p*-round*.md` in this directory
- downstream: NewGraphEnvironment/link#311

Closed by: PR for #237 (branch `237-frs-rule-to-sql-ignores-wetland-ha-min-s`)
