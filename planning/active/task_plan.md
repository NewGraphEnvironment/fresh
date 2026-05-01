# Task Plan — fresh#158: frs_order_child

## Phase 1: Setup
- [x] Branch `158-frs-order-child` from main (HEAD `253abf2`)
- [ ] PWF baseline (task_plan, findings, progress)

## Phase 2: Code change — fresh-side
- [ ] New `R/frs_order_child.R` exporting `frs_order_child(conn, table, habitat, species, label = "rearing", parent_order_min = 5, child_order_min = NULL, child_order_max = NULL, distance_max = NULL)`
- [ ] SQL per the [issue spec](https://github.com/NewGraphEnvironment/fresh/issues/158): post-classification UPDATE that adds `<label> = TRUE` to segments where `accessible IS TRUE`, `<label> IS NOT TRUE`, `s.stream_order = s.stream_order_max`, `s.stream_order_parent >= parent_order_min`, optionally bounded by `child_order_min/max` and `distance_max`
- [ ] roxygen docstring with parameters, examples, biology rationale
- [ ] `devtools::document()` clean

## Phase 3: Tests
- [ ] `tests/testthat/test-frs_order_child.R`: SQL shape (mock `.frs_db_execute`)
  - default invocation emits the canonical SQL with parent_order_min=5
  - `child_order_min/max` bounds appear when set
  - `distance_max` adds `downstream_route_measure <= ...` clause
  - `accessible IS TRUE` and `<label> IS NOT TRUE` guards always present
  - `species` substituted correctly
- [ ] `devtools::test(filter = "frs_order_child")` clean

## Phase 4: Code-check
- [ ] `/code-check` on staged diff

## Phase 5: Release
- [ ] DESCRIPTION: 0.26.0 → 0.27.0
- [ ] NEWS.md: 0.27.0 entry
- [ ] PR with `Fixes #158`
- [ ] Merge, tag

## Phase 6: Link follow-up
- [ ] Bump fresh dep 0.26.0 → 0.27.0
- [ ] dimensions.csv: flip `rear_stream_order_bypass = yes` for BT/CH/CO/ST/WCT in bcfishpass bundle
- [ ] Default-bundle TBD per methodology decision (issue mentions parametric `distance_max` could differ)
- [ ] `lnk_rules_build` already emits `channel_width_min_bypass` field but fresh doesn't read it yet — wire to call `frs_order_child` per-species after classify
- [ ] Verify HORS BT closes from -7.68% to within ±1%
- [ ] 15-WSG distributed re-run

## Verification

- HORS BT rearing_stream: -7.68% → expected within ±1%
- HORS CH/CO/ST: similar closure expected
- COLR/KHOR/CLRH WCT: similar closure expected (provincial Class B)
- bcfishpass-bundle other WSGs: bit-identical (function only fires where `rear_stream_order_bypass: yes` is set)
- default-bundle: TBD per methodology
