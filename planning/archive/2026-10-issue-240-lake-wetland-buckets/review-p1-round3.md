# Review — fresh#240 phase 1, round 3

## Clean

No issues found in the staged diff.

What was checked:
- `build_wb_pred()` now returns polygon membership + area only; `size_rear` and
  `size_sql()` are still used by the rear predicate, so no orphans.
- The cw and mad bucket predicates are now byte-identical, so
  `.frs_preds_by_model()` (R/utils.R:915) wraps two identical arms in a CASE.
  This is redundant but correct.
- `frs_habitat_classify()` (R/frs_habitat_classify.R:286-325) only embeds the
  predicate strings. The `mad_m3s` column guard (line 156) is keyed on `models`,
  not on predicate content, so dropping `mad_m3s` from the bucket predicates
  cannot skip that guard.
- Searched fresh `R/`, `tests/` and link `R/` for code that rebuilds the
  lake/wetland bucket with a size test. None found. Every other consumer only
  reads the `lake_rearing` / `wetland_rearing` columns.
- `vignettes/habitat-pipeline.Rmd:176` ("Lake rearing uses channel width") is
  about a manual `frs_classify()` call, not `frs_habitat_predicates()`, so this
  change does not make it stale.
- `NOT_CRAN=true` run of `test-frs_habitat_predicates.R` against the working tree:
  FAIL 0, PASS 91. The exact-string expectation at line 179 matches the 9-space
  indent the sprintf emits.

Accepted tradeoffs were not re-flagged: the `requires_connected` roxygen,
`edge_types` ignored on L/W rules, and the legacy `frs_habitat_species()` lake path.
