# Code-check review: fresh#240 Phase 1, round 2

Scope: staged diff to `R/frs_habitat_predicates.R`, `man/frs_habitat_predicates.Rd`,
`tests/testthat/test-frs_habitat_predicates.R`, `tests/testthat/test-frs_habitat_classify.R`
(unstaged `R/frs_params.R` / `tests/testthat/test-frs_params.R` not reviewed; not in the diff).

## Findings

- **[severity: fragile]** `R/frs_habitat.R:1133-1136` (not in the diff). The exported
  `frs_habitat_species()` is a second, independent decider of lake rearing, and it still
  gates it on the rear channel-width window: `frs_classify(label = "<sp>_lake_rearing",
  ranges = list(channel_width = params_sp$ranges$rear$channel_width), where = "... waterbody_key
  IN (SELECT waterbody_key FROM fwa_lakes_poly)")`. After this diff, `frs_habitat_classify()`
  (via `frs_habitat_predicates()`) sizes the lake bucket by polygon area only, while
  `frs_habitat_species()` still uses the inflow width and ignores `lake_ha_min`. The two
  entry points now give different `lake_rearing` for the same species and network, which is
  the stream-size artifact fresh#240 removes, left in place on the other path. This is a
  decision for the PR, not a defect in the lines changed. Either bring that path in line,
  or record it as a deliberate legacy carve-out (NEWS / issue body), so nobody reads
  "lake buckets are area-only" as package-wide. (The vignette line
  `vignettes/habitat-pipeline.Rmd:176`, "Lake rearing uses channel width on lake-connected
  segments", describes this legacy path and stays true for it.)

## Checked and clean

- **Round-1 fix is accurate.** The comment at `test-frs_habitat_classify.R:273-275` says
  the BT value comes from the bundled `waterbody_type: L` rule. `frs_habitat(rules = NULL)`
  resolves to the bundled `inst/extdata/parameters_habitat_rules.yaml`
  (`R/frs_habitat.R:221-223`). Bundled BT carries `waterbody_type: L, lake_ha_min: 10.0`
  (yaml lines 38-42). Correct.
- **Predicate change.** `build_wb_pred()` now returns `"FALSE"` only for a missing rule,
  and otherwise returns the same `s.waterbody_key IN (SELECT ...)` string as before, minus
  the size clause. `ha_min` still goes through `.frs_sql_num()`. A NULL `waterbody_key`
  gives a NULL `IN`, so CASE WHEN gives FALSE, the same as before. No new injection surface.
- **No orphans.** `size_rear`, `size_sql()` and `size_inherit()` are still used (rules-path
  inheritance at :161, CSV rear at :180).
- **Caller.** `frs_habitat_classify.R:286-325` still wraps both bucket predicates in
  `a.accessible AND (...)`. The cw and mad predicate sets are now identical for these two
  columns, so `.frs_preds_by_model()` merging them per WSG is harmless.
- **Tests can fail.** The old `build_wb_pred()` would fail the exact-string
  `expect_equal` at `test-frs_habitat_predicates.R:179` (old output had a cw prefix). It
  would fail `:190` (old output `"FALSE"`), and the `expect_identical` pins at `:390-394`
  (old mad output carried `mad_m3s`; old cw output with no window was `"FALSE"`).
  `sp_with_rules(rear_cw = NULL)` really does drop the window: `list(channel_width = NULL)`
  omits the element.
- **Rd matches roxygen** (regenerated, staged).
- The forward reference to `requires_connected: spawning` is an accepted tradeoff and is
  not re-flagged.
