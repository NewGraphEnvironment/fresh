# Progress — `.frs_rule_to_sql()` ignores `wetland_ha_min` (#237)

## Session 2026-10-07

- Plan-mode exploration — phases approved by user
- Created branch `237-frs-rule-to-sql-ignores-wetland-ha-min-s` off main
- Scaffolded PWF baseline from issue #237 with approved phases
- Next: start Phase 1
- Plan-agent review folded into task_plan as `(review)` items (ce4e44a)
- Phase 1: failing tests for `.frs_rule_to_sql()` W floor, wrong-key floor, `.frs_rule_ha_min()` (incl. NA), rear + spawn predicates, bundled W rules (all 6 species), and the `.frs_run_connectivity()` floor. All fail / error on main behaviour; the W-without-floor pin passes
