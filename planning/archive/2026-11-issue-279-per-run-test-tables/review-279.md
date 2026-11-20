# Plan review — #279 (Plan agent, spawned 2026-11-20T15:45Z, delivered ~16:00Z)

Written here by the parent session from the agent's reply (Plan agents cannot write files).
Verdicts in parentheses are the parent's, after probing.

## Blockers
- B1 Fixed index names in live tests collide (relations in `working`): test-frs_habitat.R
  `persist_282_streams_pkey`, test-utils.R `test_282_atomic_pkey`, `test_282_uniq_pkey`. Guard
  cannot see them. (CONFIRMED; habitat one already fixed in batch B; utils two to fix; add a
  scanner rule for `CREATE [UNIQUE] INDEX <ident> ON`.)
- B2 Scanner regex misses `"working."` (paste0 fragment), `"working.%s"`, `"WORKING.x"`,
  `"\"working\".x"`, `SET search_path TO working, public`. (CONFIRMED by grepl; broaden, one
  snippet per shape.)
- B3 Labels through a variable get past the guard: `.rules_test_run()`, `run()` in the 282 and
  293 tests. Wsg mode ignores `label` entirely. (Sites already wrapped in batch B; invert the
  rule: every `label =` to frs_habitat in a checked expression must contain `frs_test_label(`;
  flag a live wsg-mode frs_habitat call.)
- B4 frs_habitat names carry the run id as an infix (`streams_<run>_<lbl>`): the prefix sweep and
  `frs_test_tbl("streams_<lbl>")` drops miss them. (CONFIRMED; already fixed in batch B with
  `frs_test_label_tbl()` and a `strpos` sweep.)

## Gaps
- G1 Default `to = "working.…"` in frs_break_find/frs_break/frs_feature_find/frs_feature_index/
  frs_barriers_minimal/frs_habitat_access/frs_habitat_species; live call relying on one:
  test-frs_barriers_minimal.R:211. (Fix the call; scanner rule built from `formals()`.)
- G2 `SET search_path TO working, public` + unqualified `"test_282_rc_src"` (test-utils.R:590);
  unqualified `DROP TABLE IF EXISTS decoy_282`. (CONFIRMED: the utils one failed the batch B run.)
- G3 Live pattern lacks `frs_fwapg_conn(`, `skip_if_no_schema(`, file-local connectors
  (`bcfp_conn`); "mock" exemption greps comments. (Grow the pattern transitively; read "mock" from
  string tokens, not text.)
- G4 Scanner reads only test-*.R; include helper-*/setup-* except the two defining files.
- G5 Identifier length never asserted; ~5-char margin to 63. (Assert table part ≤ 36, label ≤ 20.)
- G6 Killed runs leak, never reaped. (Document a reaper query.)
- G7 Sweep connects only through frs_db_conn(). (Comment it.)

## Assumptions
- A1 Plan says PID+time; code uses the mkdtemp suffix, which is better. (Update plan text.)
- A2 Helpers load once; fine.
- A3 `CREATE SCHEMA IF NOT EXISTS working` can race on a fresh DB. (Note it.)
- A4 FRESH_FWAPG_TRIAL holds locks for a test. (Acceptance runs without it; note in docs.)
- A5 `public.frs_trial_<sample()>` names after a global `set.seed(286)` can coincide across runs;
  rolled back, so blocking not failure. (Check; put the run id in.)

## Ordering
- O1 Fix the guard before migrating. (Batch A/B already landed mechanically; the guard
  broadening runs over the migrated tree before the final commit.)
- O2 The red whole-tree assertion fails intermediate commits. (Accepted: green at batch B.)

## Acceptance
- AC1 Two concurrent green runs are a weak test of a rare race: add a positive control on main,
  and a timing-free proof (poison tables for every name main used, oids unchanged after the
  migrated run). (Adopted.)
- AC2 Prove both concurrent runs exercised the DB (skip counts, overlap timestamps).
- AC3 State the leftover query (infix, not a sloppy LIKE).
- AC4 One mutation per known hole.
- AC5 Pass count will be main + the guard's expectations.

## Scope / nits
- S1 Follow-up issue should cover the default-`to` functions too.
- S2 Scanner span compares parse cols with srcref bytes; collect descendants by parse id instead.
- S3 Leaving mock literals is sound.
