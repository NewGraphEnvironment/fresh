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
