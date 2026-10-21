# #263 with #262: near_river measured three ways, inherited from the thresholds CSV

Closes #262 and #263; released as fresh 0.42.0. Consumer: NewGraphEnvironment/link#364 (Phase 0 of its plan).

**Outcome.** `frs_near_river()` measures "a river nearby" by discharge, channel width or stream order (`threshold`, `distance_max`, `measure`). Its output records `measure` and `threshold`. A rule's mapping names one size key, or `false`. The thresholds CSV can carry ten `<stage>_river_*` columns, which `frs_params()` stores as `params[[sp]]$near_river`. A rule that inherits thresholds and has a size test takes its stage's pair; `model` resolves to width under `cw` and discharge under `mad`. One resolver, `.frs_rule_near_river()`, serves the compiler and the walk's pair list. With the columns absent or NA every rule compiles as in 0.41.0, which a fixture frozen from 0.41.0's own output checks. Classify now walks before it writes the habitat table.

## Measurement

On BULK at 1 km, the walk by width (20 m) and by order (5) equals, row for row, the discharge walk on a copy whose `mad_m3s` holds that measure: 0 rows apart in either direction, 13 to 16 s per walk. The independent reference from #259 reads discharge only and lives outside the repo, so it does not score width or order; the equivalence check tests what #262 changed.

| BULK main flow | rows | discharge (wet) | width | order |
|---|---|---|---|---|
| 1250 river polygon | 1,118 | 1,114 | 1,118 | 1,118 |
| 1200 through lake | 2,935 | 2,931 | 1,145 | 2,935 |

Review: four `/code-check` rounds. Rounds 1 to 3 each found one way classify could delete habitat rows and then stop on a walk input: a blank cell, an old table shape, then other columns and numbers, then a `text` column. The fix that closed the class runs the walk before classify touches `to`; the enumeration is in findings.md. Round 4 found nothing.

## Evidence

`data-raw/logs/near_river_262/` (`data-raw/near_river_measure_check.R`); `tests/testthat/fixtures/predicates_0410/` (`data-raw/predicates_fixture_0410.R`).
