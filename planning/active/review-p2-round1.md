# Code-check review — fresh#240 phase 2, round 1 (staged diff: R/frs_params.R, tests/testthat/test-frs_params.R)

## Findings

- **[severity: fragile]** R/frs_params.R:373-393 and :186-204 (cross-repo contract with link) — link's
  `lnk_rules_build()` already has a `rear_requires_connected` / `rear_connected_distance_max`
  dimensions column pair, and its documented contract
  (`link/inst/extdata/configs/dictionary_dimensions.csv` rows 29-30: "applied to every emitted rear
  rule") is implemented by `add_rc()` being called on **every** rear rule it emits
  (`link/R/lnk_rules_build.R:283, 321, 325, 328, 335, 338, 365, 379`): stream, river (R),
  `edge_types_explicit` 1050/1150, wetland and lake rules alike, and it also emits a lake rule both at
  `rear_rules[[1]]` (:283) and later (:379). With this commit, any non-empty value in that column
  produces a `rules.yaml` that `.frs_load_rules()` refuses: the new rear block errors on the
  stream / R / edge-type rules ("uses requires_connected without waterbody_type: L or W"), a value of
  `rearing` errors on the L/W rules, an empty distance errors, and a second L rule trips
  `.frs_validate_rear_connected()`. Today every shipped `dimensions.csv` has the column all-NA, and
  all five shipped rules YAMLs load (verified below), so nothing breaks now. But the only existing
  producer of rear `requires_connected` is now incompatible by construction, and the failure surfaces
  as a load-time stop in fresh rather than at `lnk_rules_build()`. The link follow-up (#310 /
  whatever wires this column) must change `add_rc` to stamp only the first L and first W rear rule,
  and the dictionary row's "applied to every emitted rear rule" must change with it. Not a defect in
  the fresh diff itself; flagged so the link side is not discovered by a failed build.

No bugs found in the staged fresh code itself.

## Verified

- All shipped rules YAMLs load with the staged code (`devtools::load_all` + `.frs_load_rules`):
  `fresh/inst/extdata/parameters_habitat_rules.yaml`, and link's `bcfishpass`, `default`,
  `default_extrabreaks`, `default_rearbreaks` `rules.yaml` -> all `ok`. No shipped YAML carries
  `requires_connected` on a rear rule (every hit is a spawn rule with `rearing`).
- Spawn behaviour unchanged: the new per-rule block is gated on `habitat == "rear"`, and
  `.frs_validate_rear_connected()` is called only for `rear`.
- `is.finite(cdm)` / `cdm <= 0` are safe: the pre-existing check above already guarantees `cdm` is a
  numeric length-1 value when present, so no length-0 / character / list reaches them.
- YAML edge cases on a rear L rule with `requires_connected: spawning`:
  `.inf`, `.nan`, `~`, empty value, `0`, `-5` -> "finite number > 0" error; `'3000'`, `true`,
  `[1, 2]`, `1e3`, `1.0e3` (R yaml reads the last two as strings) -> pre-existing "numeric scalar"
  error; `[3000]` and `requires_connected: [spawning]` are accepted (single-element sequences collapse
  to length-1 vectors; harmless). `3000.5` accepted.
- `.frs_validate_rear_connected()` matches `.frs_find_waterbody_rule()` (utils.R:380), which picks the
  first rule with `identical(waterbody_type, wb_code)`; the validator uses the same `identical()`
  test, so "first" agrees. `idx[-1]` on an empty `idx` is `integer(0)` (no-op).
- `.frs_run_connectivity()` (HEAD) reads only spawn-rule `requires_connected`, so a rear-rule key is
  inert until the later commit lands; no interaction with the spawn-side waterbody lookup, which reads
  the first L-or-W rear rule's `waterbody_type` / `lake_ha_min` only.
