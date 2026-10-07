# Code-check review — fresh#240 Phase 1, round 1

Scope: staged diff to `R/frs_habitat_predicates.R`, `man/frs_habitat_predicates.Rd`,
`tests/testthat/test-frs_habitat_predicates.R`, `tests/testthat/test-frs_habitat_classify.R`.

## Clean

No bugs, security issues or data-loss paths found in the code change.

What was checked:

- **No orphans.** `size_rear` is still read (rules-path inheritance at
  `R/frs_habitat_predicates.R:161`, CSV rear path at `:180`); `size_sql()` and
  `size_inherit()` are still used. `build_wb_pred()` no longer needs `model`; nothing
  dangling.
- **Callers.** The only caller is `frs_habitat_classify()` (`R/frs_habitat_classify.R:286-295`),
  which builds cw and mad predicate sets and merges them via `.frs_preds_by_model()`. With
  `lake_rear` / `wetland_rear` now identical under both models, the per-WSG merge is a
  no-op for those two columns; still wrapped in `a.accessible AND (...)`, so access gating
  is unchanged.
- **SQL.** The emitted predicate is the same `s.waterbody_key IN (SELECT waterbody_key
  FROM <poly>[ WHERE area_ha >= n])` as before minus the leading size clause and `AND`;
  `ha_min` still goes through `.frs_sql_num()`. No injection surface added.
- **Tests can fail.** Restoring the old `build_wb_pred()` turns red: the exact-string
  `expect_equal` at `test-frs_habitat_predicates.R:179` (old code prepends
  `s.channel_width >= 1.5 AND s.channel_width <= 9999`), the `expect_match` at `:190`
  (old code returns `"FALSE"` for cw with no rear width), and the `expect_identical`
  pins at `:390-394` (old mad output carried `s.mad_m3s`, old cw-no-window output was
  `"FALSE"`). `sp_with_rules(rear_cw = NULL)` leaves `ranges$rear$channel_width` reading
  as NULL, so the cw-no-window case is genuinely exercised.

## Non-blocking notes (not defects in this diff's behaviour)

1. **Roxygen states behaviour that does not exist yet** — `R/frs_habitat_predicates.R:43-44`
   (and the regenerated `.Rd`): "Connection to spawning is applied after classification,
   for rules that carry `requires_connected: spawning` (see [frs_habitat()])". At this
   commit `.frs_run_connectivity()` (`R/frs_habitat.R:1175-1270`) never reads
   `requires_connected` on a rear rule and never touches `lake_rearing` /
   `wetland_rearing`. `.frs_validate_rule()` already accepts `requires_connected: spawning`
   on any rule, so a user who opts in today gets the key validated and silently ignored.
   Fine if Phase 3 lands in the same PR; wrong if this commit ships alone.

2. **Comment in `test-frs_habitat_classify.R:273-275` is inaccurate.** `.rules_test_run(...,
   rules = NULL)` runs the *bundled* rules (see the sibling tests at `:202-213`), and bundled
   BT carries `waterbody_type: L, lake_ha_min: 10` and `waterbody_type: W, wetland_ha_min: 1`
   (`inst/extdata/parameters_habitat_rules.yaml`). So "with no rules it is FALSE" does not
   describe this call; BT `lake_rearing` here is the area bucket. The assertion
   (`!is.na`) still passes, so no failure — comment only.

3. **Pre-existing, now more visible:** `build_wb_pred()` reads only `*_ha_min` from the L/W
   rule. The bundled L/W rules also carry `edge_types_explicit: [1000, 1100]`, which the
   bucket has always ignored. With the size clause gone, polygon membership is the whole
   test, so every accessible segment with that `waterbody_key` (any edge type) is in the
   bucket. Consistent with the new docs ("polygon membership, filtered by ha_min"), and
   arguably intended for a polygon-unit bucket — flagged only so it is a decision, not an
   accident.
