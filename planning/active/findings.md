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
