# Progress — Integration tests name working tables as fixed literals, so two runs against one database collide and produce a failure neither can reproduce (#279)

## Session 2026-11-20

- Plan-mode exploration — phases approved by user (namespace: prefix inside `working`)
- Created branch `279-integration-tests-name-working-tables-as` off origin/main
- Scaffolded PWF baseline from issue #279 with approved phases
- Next: start Phase 1
- Phase 1: per-run helpers (`frs_test_tbl()`, `frs_test_label()`, `frs_test_tbl_parts()`,
  `frs_test_sweep()`) in helper-db.R, the run-end sweep in setup-run_namespace.R, the scanner in
  helper-test_names.R and its guard test. The 7 snippet tests pass both ways; the whole-tree
  assertion is red as planned: 287 hits (279 working, 8 label) across the 17 files the plan named.
- Phase 2 batch A: 11 files migrated. The 172 whole-string literals were rewritten by parse
  position, and SQL with an embedded name became `sprintf()`/`paste()` around `frs_test_tbl()`;
  the information_schema checks and `DBI::Id()` now take their parts from `frs_test_tbl_parts()`.
  The first run showed the guard's "top-level is always live" rule was too broad: it rewrote a
  mock helper in test-frs_channel_width.R. Narrowed it: a top-level expression that drives a
  `"mock"` connection and matches no live pattern is left alone, with a snippet test for it.
