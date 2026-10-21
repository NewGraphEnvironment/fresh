# Progress — #263 with #262

## Session 2026-10-21

- Phase 0 of link#364's approved plan; branch `263-inherit-near-river-from-the-thresholds-c` off main.
- Read `frs_near_river.R`, `frs_habitat_predicates.R`, `utils.R` (rule compiler), `frs_params.R`, `frs_habitat_classify.R` to place the change.
- Next: Phase 1.
- Phase 1 (#262): `frs_near_river(threshold, distance_max, measure)` walks on `mad_m3s`, `channel_width` or `stream_order`. The output table carries `measure` and `threshold`, and a 0.41.0-shape table stops the call. Rule mappings take one size key or `false`, and the loader normalizes them. The EXISTS matches measure, threshold and distance. Classify checks each measure's column before any write and walks only for classifying species. Rule and walk tests pass: 76 and 54 expectations.
