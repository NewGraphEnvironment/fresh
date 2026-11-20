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
- Baseline, main @ 98e7cf0 from a worktree, full suite: 2643 pass / 0 fail / 6 skip, ~15 min.
- Phase 2 batch B: 6 files migrated (frs_habitat, habitat_classify, habitat_overlay,
  barriers_minimal, habitat_partition_293, utils). Its first run: 505 pass, 2 failures in
  test-utils.R, both bare table names the guard cannot see (`pg_indexes WHERE tablename = '…'`
  and an unqualified name under `SET search_path TO working`).
- Plan review landed (review-279.md): 4 blockers, 7 gaps. B4's infix names and one of B1's three
  index names were already fixed in batch B; the rest folded in as Phase 2b. Guard green over
  every test, helper and setup file.
- Filed #310 (scratch tables hardcode the working schema: frs_habitat internals and seven `to`
  defaults). CLAUDE.md gained "Per-run test table names (#279)".
- Phase 3 under way: poisoned 192 names main's tests use (186 created, 6 pre-existing fixtures,
  oids recorded; the three old index names left out so a concurrent main run on a shared
  database is not broken by them), then two full suites launched at once, ~16:05Z.
