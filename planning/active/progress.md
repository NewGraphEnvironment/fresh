# Progress — `.frs_rule_to_sql()` ignores `wetland_ha_min` (#237)

## Session 2026-10-07

- Plan-mode exploration — phases approved by user
- Created branch `237-frs-rule-to-sql-ignores-wetland-ha-min-s` off main
- Scaffolded PWF baseline from issue #237 with approved phases
- Next: start Phase 1
- Plan-agent review folded into task_plan as `(review)` items (ce4e44a)
- Phase 1: failing tests for `.frs_rule_to_sql()` W floor, wrong-key floor, `.frs_rule_ha_min()` (incl. NA), rear + spawn predicates, bundled W rules (all 6 species), and the `.frs_run_connectivity()` floor. All fail / error on main behaviour; the W-without-floor pin passes
- Phase 1 committed (2171459)
- Phase 2: `.frs_rule_ha_min()` routes all three floor readers (`.frs_rule_to_sql()`, `build_wb_pred()`, `.frs_run_connectivity()`). Vignette data unaffected: `example_byman_ailport.R` is direct SQL and `vignette_habitat_pipeline.R` calls `frs_classify()`
- `/code-check` ran 3 rounds plus an enumeration:
  - Round 1 (tests only): clean
  - Round 2: NA floor goes silent, fixed in the loader
  - Round 3: an empty floor still went silent, a gap inside the round-2 fix, so only an enumeration could end the loop. Fixed with a key-presence check
  - Enumeration: all 128 cases rejected or correctly floored
- Full suite FAIL 0 / PASS 1254 (3 warnings from the existing live network-features tests)
