# Progress — Route measures reach SQL through %s (15 significant digits), which can name a position past a segment's end (#274)

## Session 2026-10-31

- Plan-mode exploration — phases approved by user
- Created branch `274-route-measures-reach-sql-through-s-15-si` off origin/main
- Scaffolded PWF baseline from issue #274 with approved phases
- Next: start Phase 1
- Phase 1: mocked tests in `test-frs_point_locate.R` (exact SQL text; non-finite/vector measure refused before the DB). Red on main: FAIL 2 (text mismatch; NA reached the DB)
- Phase 2: `frs_point_locate()` writes `%d` key and `.frs_sql_exact()` measure. `devtools::test(filter = "frs_point_locate")`: FAIL 0, PASS 8, SKIP 0 (live test ran against local fwapg)
- Phase 3: gate test's `blk_top()` / `skip_unless_head_case()` use the exact measure; comments updated. Trial run: head-case test ran and passed; no-trial run: all skip
- Phase 4: research/fwa_point_snap.md caveat revised. `document()` writes nothing. lintr on touched files: the only new lints are `object_usage_linter` for `.frs_sql_exact`, from the stale installed fresh 0.48.0, which lacks it; indentation lints follow the files' existing pattern
