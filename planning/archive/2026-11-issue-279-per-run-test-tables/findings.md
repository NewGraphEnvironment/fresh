# Findings — Integration tests name working tables as fixed literals, so two runs against one database collide and produce a failure neither can reproduce (#279)

## Issue context

**If done:** two test runs can share one database, so a mutation sweep, a suite run and a reviewer's probe need not take turns. **If never:** they collide on table names, and the failure that results is reported against whichever run lost the race, reproduces for nobody, and reads exactly like a real regression.

## Problem

The integration tests name their working tables as fixed literals in a shared schema. Measured on the current tree: **271 occurrences of 75 distinct `working.<name>` literals across 17 of 49 test files**, and none of them derives a per-run suffix — no `Sys.getpid()`, no `tempfile()`, no interpolation of any kind.

**Since then, and seen biting (2026-11-19).** PR #309 added `test-habitat_partition_293.R`, whose custom-AOI test creates and drops `working.p293_habitat`, `working.p293_streams`, `working.p293_solo_habitat` and `working.p293_solo_streams` (a `git grep` for `working.<name>` in `tests/testthat/`: 8 more occurrences, 4 more distinct names, one more file than `main`). A reviewer running that file while a mutation sweep ran the same file on one database made a test error that passed on its own, and the sweep had to be stopped and rerun from scratch.

Two runs against one database therefore create, drop and truncate each other's tables. `frs_*` helpers that start with `DROP TABLE IF EXISTS` make it silent: the loser's table disappears mid-test rather than erroring on create.

## How it presented

During #242, a suite run started while a mutation sweep was still finishing its last round. The suite reported a failure; two immediate re-runs were clean, and three consecutive runs afterwards gave 138 pass / 0 fail. The failure was real — it just belonged to the interaction, not to the code under test.

That is the expensive shape. A failure that cannot be reproduced gets attributed to the change under review, and the time goes on re-reading a correct diff. It also forced every long job in that session to be serialized: the sweep, the full suite and each reviewer round took turns, with the agent idle in between, purely because none of them could safely overlap.

## Proposal

A per-run namespace, applied once rather than 271 times by hand:

1. A helper in `tests/testthat/helper-db.R` returning a run-unique prefix or schema — `working_test_<pid>_<n>`, or a schema created and dropped around the run.
2. Tests take their table names from it instead of writing `working.` literals.
3. A guard that fails the suite on a new fixed `working.` literal, so the convention cannot erode — the same shape as the pkgdown allowlist: verified against both answers before shipping, since a guard that only ever returns one value is indistinguishable from a broken one.

Worth deciding up front, because it shapes the migration:

- **Prefix inside `working`, or a schema per run?** A schema is cleaner to drop wholesale and makes a leaked table obvious; a prefix is a smaller diff and needs no create/drop privileges.
- **What about the tables that are deliberately shared** — `working.streams`, `working.breaks` and friends read by several files? Those may be fixtures rather than scratch, and if so they want building once per run rather than renaming.

Mechanical either way, and it is the one change in this family that compounds: everything else in the test suite gets cheaper to run in parallel afterwards.

## Note

Raised in #277 as "worth its own issue if it bites again". It bit during #242, hence this.

The new tests added in #242 (`tests/testthat/test-frs_connectivity_wsg.R`, `tests/testthat/helper-synthetic.R`) use `pg_temp` only, which is session-local and immune to this. That is the shape to copy where a test does not need to read real FWA rows.

Relates to #242, #277.



## Errors Encountered

| Error | Resolution |
|-------|------------|

## Guard mutations (2026-11-20, AC4)

Each mutation went into a scratch copy of the real test file, and the scanner was run over every
guarded file with the copy in place of the original, so the tree was never touched while the
suites ran. Unmutated: 0 hits.

| Mutation | File | Guard |
|---|---|---|
| fixed literal `"working.test_extract"` | test-frs_extract.R | red (working@135) |
| `paste0("working.", "test_extract")` | test-frs_extract.R | red (working@135) |
| `"WORKING.test_extract"` | test-frs_extract.R | red (working@135) |
| fixed index name `test_282_uniq_pkey` | test-utils.R | red (index@730) |
| `label = label` in `.rules_test_run()` | test-frs_habitat_classify.R | red (label@179) |
| `wsg = "BULK"` added to a live call | test-frs_habitat.R | red (wsg@313) |
| `frs_barriers_minimal()` without `to` | test-frs_barriers_minimal.R | red (to@211) |
| `"SET search_path TO working, public"` | test-utils.R | red (working@592) |

Not covered, by design and documented in CLAUDE.md and the helper's header: a bare table name
compared against `table_name`, and a name assembled in a variable elsewhere.

## Phase 3 measurements (2026-11-20, the default test database from the PG* env)

**Baseline**, main @ 98e7cf0 from a worktree, one full suite: 2643 pass / 0 fail / 6 skip.

**Concurrency.** Two full `devtools::test()` runs of this branch launched at once (run ids
`ttabtcp`, `ts4ifwd`):

| run | start (UTC) | end (UTC) | pass | fail | error | skip |
|---|---|---|---|---|---|---|
| a | 16:05:09 | 16:19:59 | 2671 | 0 | 0 | 6 |
| b | 16:05:09 | 16:20:02 | 2671 | 0 | 0 | 6 |

2671 = 2643 + the guard's 28 expectations. The 6 skips are the same in both: three
fwapg-gate tests and one migration-trial test (`FRESH_FWAPG_TRIAL` unset), and two
`frs_params` tests (no `bcfishpass` schema). Afterwards no relation in `working` carried either
run id (`strpos(relname, '<runid>_') > 0`), and neither run's sweep found anything to drop.

**Poison (timing-free).** Before the two runs, every `working.<name>` literal in main's test files
plus the `streams_`, `barriers_…_gradient`, `rt_streams_` and `rt_habitat_` names for each label
main's live tests pass: 192 names, 186 created as one-column tables and 6 already present, all
oids recorded. Main's three fixed index names were not poisoned: a table by that name would
break any concurrent main run on a shared database.

After the runs: 168 untouched; 24 destroyed, none recreated. Those 24 were every database name
in main's `test-utils.R` (`test_114_*`, `test_282_*`, `test_idx_idem`) plus the six `p293`
names (`p293_*`, `streams_p293b`, `barriers_p293b_gradient`), and those six were the "already
present" ones: another client's live tables, sitting in `working` before the poison was
created.

- **Discriminating probe:** re-poisoned the 24 and ran this branch's `test-utils.R` and
  `test-habitat_partition_293.R` alone (281 pass). 0 destroyed. This branch never touches those
  names.
- **So:** an outside client ran main's fixed-name tests on the same database during the window.
  No test process was running on this machine afterwards. The parallel #305 session
  (`fresh-305`) was committing its `/code-check` rounds from 16:07 to 16:20Z, which makes it a
  candidate, but its records name only `filter = "frs_db_conn"`: **unattributed**.
- Both of this branch's runs passed through that collision. This is the scenario #279 is about,
  this time with nothing failing.

**Positive control.** Main's own `test-frs_extract.R`, run from the main worktree against the
poisoned database (23 pass), destroyed `test_extract`, `test_extract_both` and
`test_extract_where`. The check detects the collision it exists to catch.

**Cleanup.** All poison tables were dropped: 183 by the recorded list, and 6 more (the
re-poisoned `p293` names) by their `poison_279` column. 0 relations with that column remain.
