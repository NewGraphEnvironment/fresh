# Progress — #263 with #262

## Session 2026-10-21

- Phase 0 of link#364's approved plan; branch `263-inherit-near-river-from-the-thresholds-c` off main.
- Read `frs_near_river.R`, `frs_habitat_predicates.R`, `utils.R` (rule compiler), `frs_params.R`, `frs_habitat_classify.R` to place the change.
- Next: Phase 1.
- Phase 1 (#262): `frs_near_river(threshold, distance_max, measure)` walks on `mad_m3s`, `channel_width` or `stream_order`. The output table carries `measure` and `threshold`, and a 0.41.0-shape table stops the call. Rule mappings take one size key or `false`, and the loader normalizes them. The EXISTS matches measure, threshold and distance. Classify checks each measure's column before any write and walks only for classifying species. Rule and walk tests pass: 76 and 54 expectations.
- Phase 2 (#263): `frs_params()` reads the ten `*_river_*` columns into `params[[sp]]$near_river$<stage>`. It stops on half pairs and bad values, and warns on an unknown `*_river_*` column. `.frs_rule_near_river()` resolves explicit, then `false`, then inherited (only when the rule inherits and has a size test). The compiler and `.frs_near_river_specs()` share it through `.frs_stage_rules()` and `.frs_stage_inherit()`. Classify builds predicates and walks only for the models applied. The bundled CSV gained the columns as NA.
- Byte identity is tested against fresh 0.41.0's own output: `data-raw/predicates_fixture_0410.R`, run from a v0.41.0 worktree, froze 66 predicate sets for fresh's bundled rules and link's `default` and `bcfishpass` bundles. Two planted defects were each caught in a scratch copy: no `channel_width` strip under mad, and inheriting with no size test.
- Full suite: 1,823 expectations, 0 failures, 0 errors, 2 skips, 3 warnings.
