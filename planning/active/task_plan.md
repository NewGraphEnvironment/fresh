# Task: Integration tests name working tables as fixed literals, so two runs against one database collide and produce a failure neither can reproduce (#279)

The integration tests name their working tables as fixed literals in a shared schema. Two runs
against one database therefore create, drop and truncate each other's tables. `frs_*` helpers
that start with `DROP TABLE IF EXISTS` make this silent: the losing run's table disappears
mid-test instead of erroring on create.

## Measured on main @ 98e7cf0

A scratch classifier parsed every test file and sorted each top-level expression into live or
mock. A block is live when it opens a connection (`frs_db_conn(`, `skip_if_no_conn`,
`local_fwapg`, `.frs_db_available`, `dbConnect`), and a top-level expression always counts as live.

- About 448 `working.<name>` literals. About **265 sit in 52 live blocks across 17 files** and
  name 102 distinct tables. The other ~183 sit in `"mock"`-connection blocks, where they are
  only SQL text.
- **No live test shares a fixture table.** `working.streams`, `working.breaks`,
  `working.falls` and `working.features` appear only in mock blocks.
- `frs_habitat()` hardcodes `working.streams_<label>`, `working.barriers_<label>_gradient` and
  `working.breaks_{access,habitat}_<label>_*` (R/frs_habitat.R:441,479,850-933). All 5 live
  `frs_habitat()` tests run in AOI mode with an explicit `label =`, so a per-run label puts
  those internal tables in the run's namespace too.
- Five `information_schema` checks spell `table_schema = 'working' AND table_name = '<x>'`,
  and one test writes `DBI::Id(schema = "working", ...)`.
- `fresh.*` and `bcfishpass.*` literals in live blocks are read-only sources, so they are out
  of scope.

## Decided at the gate

- **Namespace: a prefix inside `working`** (the owner, 2026-11-20, chosen over a schema per
  run). Live tables become `working.t<runid>_<name>`, and `frs_habitat()` labels become
  `t<runid>_<label>`. It needs no CREATE SCHEMA privilege, and one mechanism covers both test
  tables and frs_habitat's internal tables.
- Mock-block literals stay as they are (decided in the approved plan, 2026-11-20). They never
  reach a database, and rewriting ~183 SQL assertions is churn with no collision to fix.

## Phase 1: Helpers and guard (tests first)
- [x] `tests/testthat/helper-db.R`: a run id computed once when the helpers load (`t` + the
      session tempdir's six-character mkdtemp suffix, lower case: unique on one machine and
      random across machines, which PID and time bits are not; review A1); `frs_test_tbl(name)` → `"working.<runid>_<name>"`
      (case preserved for the mixed-case folding test); `frs_test_label(x)` →
      `"<runid>_<x>"`; `frs_test_tbl_parts(tbl)` → schema and table, for
      `information_schema` checks
- [x] End-of-run sweep (`tests/testthat/setup-run_namespace.R`,
      `withr::defer(..., teardown_env())`): when a connection is available, drop every
      `working` table whose name starts `<runid>_`, and message the names of any it had to
      drop, since each is a test that leaked
- [x] Scanner `.frs_test_fixed_names(file)` (helper, using `getParseData()`): flags, in live
      `test_that()` blocks and in top-level expressions, any string constant that names the
      `working` schema (`working.x`, `"working"`, `'working'` inside SQL), and any string
      literal passed as `label =` directly to `frs_habitat()`
- [x] `tests/testthat/test-test_table_names.R`: the scanner checked against both answers on
      inline snippets (a live block with a literal is flagged; a mock block is not; a live
      block using the helpers is clean; a `frs_habitat(label = "x")` is flagged; an
      `information_schema` `'working'` is flagged), then run over every test file expecting
      zero hits. This last assertion is red until Phase 2 lands.

## Phase 2: Migrate the live blocks (mechanical, one commit per batch)
- [x] Batch A: test-frs_break, test-frs_extract, test-frs_col_generate, test-frs_col_join,
      test-frs_aggregate, test-frs_network, test-frs_point_snap, test-frs_classify,
      test-frs_channel_width, test-frs_cluster, test-frs_order_child
- [x] Batch B: test-frs_habitat, test-frs_habitat_classify, test-frs_habitat_overlay,
      test-frs_barriers_minimal, test-habitat_partition_293, test-utils
- Pattern: `tbl <- frs_test_tbl("test_extract")` in place of the literal; `on.exit` drops use
  the same variables; frs_habitat calls take `label = frs_test_label("brktest_a")`, and the
  derived internal names (`streams_<label>`, `barriers_<label>_gradient`) come from that
  label; `information_schema` checks take schema and table from `frs_test_tbl_parts()`; the
  mixed-case `Test_220_Empty` keeps its case.
- [x] The guard test goes green over the whole tree

## Phase 2b: Plan review fold-in (review-279.md; added 2026-11-20 after the review landed)
- [x] `frs_test_label_tbl()` for frs_habitat's own `streams_<label>` / `barriers_<label>_gradient`
      names, whose run id is an infix; the sweep matches the run id anywhere in the name (B4)
- [x] Per-run index names in test-frs_habitat.R and test-utils.R (B1); `pg_indexes` and
      `search_path` sites take their names from `frs_test_tbl_parts()` (G2); `pg_temp.decoy_282`
- [x] Scanner rebuilt: blocks by parse id (S2); live connectors grown transitively, plus
      `frs_fwapg_conn`, `skip_if_no_schema` (G3); "mock" read from string tokens, not comments
      (G3); `working` in any case, fragment, quoting or search_path (B2); fixed index /
      constraint names (B1); every `frs_habitat(label =)` must go through `frs_test_label()`,
      and wsg mode is flagged (B3); a call leaving `to` at a working default, the list read from
      the package's formals (G1); helper-*/setup-* files scanned too (G4). One snippet test per
      shape, each way
- [x] `frs_barriers_minimal()` live call passes `to` (G1)
- [x] Length budget asserted in `frs_test_tbl()` (≤ 36) and `frs_test_label()` (≤ 20) (G5)
- [x] test-frs_migration_trial.R names from the run id, not `sample()` after a global
      `set.seed()` (A5); sweep comment on its connection and on killed runs (G6, G7)

## Phase 3: Verify and document
- [ ] Full suite against the default test database: 0 failures, the same 6 skips as main
      (main @ 98e7cf0: 2643 pass / 0 fail / 6 skip), pass count = main + the guard's own (AC5)
- [ ] **Timing-free proof (AC1):** create a "poison" table in `working` for every name main's
      live tests use (the fixed literals, `streams_<label>` / `barriers_<label>_gradient` for
      each literal label, the three index names as tables); run the migrated suite; every
      poison table survives with its oid unchanged
- [ ] **Positive control (AC1):** the same poison check against one live file from main's
      worktree destroys poison tables
- [ ] **Concurrency acceptance:** two full `devtools::test()` runs at once against one
      database; both clean, skip counts equal to the serial run, start/end times show overlap
      (AC2), and no relation in `working` carries either run id afterwards
      (`strpos(relname, '<runid>_') > 0`, not a LIKE; AC3)
- [ ] Mutation, one per hole the review named (AC4): a fixed literal, `paste0("working.", x)`,
      `"WORKING.x"`, a fixed index name, a label through a variable, a wsg-mode call, a
      `frs_barriers_minimal()` with no `to`, each restored into a real test file; the guard
      goes red on each; revert
- [ ] CLAUDE.md "Testing on alternate hosts": a short paragraph on `frs_test_tbl()` /
      `frs_test_label()`, the guard and what it cannot see, `pg_temp` as the first choice where
      a test needs no real FWA rows, the reaper query for killed runs (G6), and that a
      `FRESH_FWAPG_TRIAL` run holds locks other runs wait on (A4)
- [ ] File a follow-up issue in fresh: `frs_habitat()`'s internal tables hardcode the
      `working` schema (a painted corner under design principle 2), as do the `to` defaults
      of frs_break_find / frs_break / frs_feature_find / frs_feature_index /
      frs_barriers_minimal / frs_habitat_access / frs_habitat_species (S1); a configurable
      working schema would let a run be isolated by schema without label tricks

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: the snippet tests prove the guard returns both answers; the
whole-tree assertion proves the migration is complete; the mutation step proves the guard
fires on a real file; two concurrent full runs on one database prove the namespace isolates
them, which is the behaviour the issue asks for.
