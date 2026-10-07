# Review: p3 (data-raw/rear_wetland_floor_check.R + logs + findings), round 1

## Findings

- **[bug]** data-raw/rear_wetland_floor_check.R:87-89 (`small_wetland`), and the `small_wetland_new_*` columns in all three logs. The "sub-floor wetland" test does not match how the W rule defines a sub-floor wetland. The compiled W clause admits a `waterbody_key` when ANY of its polygons has `area_ha >= floor`. `small_wetland` flags a key when ANY polygon has `area_ha < floor`. `fwa_wetlands_poly` is multi-polygon per key: 19,510 keys have more than one polygon, and 6,730 keys straddle 1 ha (3,085 straddle 0.5 ha). So a segment in a straddling key counts as "in a sub-floor wetland" even though the W rule treats its wetland as above the floor and admits it. This breaks the script's stated meaning, "admitted inside wetlands under the floor, through rules other than the W rule". Edge 1000/1100 segments in straddling keys are admitted by the new W rule itself, and they sit in `small_wetland_new_n`:
  - NATR BT: 139 of 899
  - PARS BT: 256 of 833
  - BULK CO: 18 of 106

  Fix: test `small_wetland` as the complement of the rule's own test. That is `waterbody_key IN (SELECT waterbody_key FROM fwa_wetlands_poly) AND waterbody_key NOT IN (SELECT waterbody_key FROM fwa_wetlands_poly WHERE area_ha >= floor)`, or `GROUP BY waterbody_key HAVING max(area_ha) < floor`. (`area_ha` / `waterbody_key` have no NULLs today, so `NOT IN` is safe. `NOT EXISTS` is safer.)

- **[bug]** planning/active/findings.md "Live measurement" bullets and the NEWS draft. The per-edge-type numbers bound for NEWS inherit the same any-polygon definition, so they overstate. "428 segments (52.5 km) of NATR BT rearing in sub-1 ha wetlands" via 1050 drops to **307 segments (26.4 km)** when the wetland's largest polygon is under 1 ha. The rest sit in wetlands that have a polygon of 1 ha or more. Likewise "1000: 167 segments, 20.7 km" drops to **48 segments**. The other 119 are in straddling keys, which the new W rule also admits. The NEWS line about the 1050/1150 carve-out roughly halves in km once the definition matches the rule's. These numbers also come from no committed script or log. The script reports only the pooled `small_wetland_new_*` (not intersected with persisted `rearing`, not split by edge type), so the NEWS figure can't be reproduced from `data-raw/` (house rule: data generation via scripts, never ad-hoc). Fix: add the persisted-rearing and edge-type split to the script with the corrected definition, then rerun.

- **[fragile]** data-raw/rear_wetland_floor_check.R:14-15 header, and findings.md "wetlands touched". `dropped_wetlands` is `count(DISTINCT waterbody_key)`. That counts wetland waterbodies, not "wetland polygons" as the header says, and a key can own many polygons. The number is right. The header's wording is what's wrong, and it would be wrong if quoted downstream.

- **[fragile]** NEWS draft, "rear loses 62 segments (3.0 km) for NATR BT ...". This is the raw predicate delta. The effect on link's persisted `rearing` is `dropped_persisted_*`: 40 / 2.1 km, 60 / 3.1 km, 2 / 0.0 km. That is only a lower bound, because link reruns `cluster_rearing` (TRUE for BT and CO in `default`) on the narrowed predicate, and removing segments can disconnect further rearing. Present the persisted numbers as what link's output loses (at least), or label the 62 / 77 / 5 explicitly as the pre-cluster predicate change. The same goes for the findings claim that the old-only segments "are what link's `cluster_rearing` removes". It is plausible (`cluster_rearing = TRUE`, and `persisted_only_n = 0`), but the script doesn't verify it. `persisted ⊆ old` is a one-sided check.

## Checked and fine

- The join is on `(id_segment, watershed_group_code)`. Both `fresh_default.streams` and `streams_habitat_{bt,co}` are unique on it for NATR, PARS and BULK (n = distinct).
- Gating on persisted `accessible IS TRUE` matches classify's `a.accessible AND (pred)`. `COALESCE(pred, FALSE)` matches its `CASE WHEN ... ELSE FALSE`.
- The predicate is built through `frs_habitat_predicates()`, so `area_only` filtering and model rule handling match classify. With one WSG, `.frs_preds_by_model()` reduces to the single model, as the script assumes. The mad guard is present.
- Link's `lnk_pipeline_classify()` passes `frs_params(csv = thresholds, rules_yaml = cfg$rules)` from the same `default` bundle (`extends: ~`, so no inherited files). The rear predicate doesn't depend on `params_fresh` fields.
- "Old" is byte-identical to pre-fix output: the W rules in `default` carry no `lake_ha_min`.
- `dropped_persisted_n > 0` confirms `fresh_default` was persisted with the pre-fix compiler.
- In `default`, each species has exactly one W rear rule and no `area_only` rules, so `w_floor` taken from the first W rule is the floor that was stripped.
