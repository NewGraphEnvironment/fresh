# Progress — frs_candidates_pick: score + filter + dedup candidates per key (#207)

## Session 2026-05-11

- Plan-mode exploration — phases approved by user
- Confirmed `frs_point_snap(num_features = N)` returns one row per (point, candidate) — the input shape `frs_candidates_pick` consumes
- Confirmed reuse helpers all in `R/utils.R` (validate_identifier, db_execute, table_columns, sql_num)
- `frs_point_match` (just-shipped v0.30.0) is the structural template
- Param-naming correction adopted: `exp_score` / `exp_filter` (not `score_expr` / `filter_expr`) matching `table_<role>` and `col_<role>` precedent. CLAUDE.md update queued for Phase 4.
- Created branch `207-frs-candidates-pick-score-filter-dedup-c` off main (v0.30.0)
- Scaffolded PWF baseline with approved phases
- Plan file: `/Users/airvine/.claude/plans/snuggly-fluttering-hopper.md`
- Driven from link session — work happens in `~/Projects/repo/fresh`
- Next: start Phase 1 — write `R/frs_candidates_pick.R`
