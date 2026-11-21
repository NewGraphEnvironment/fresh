# Code-check round 4: #279 (per-run test table names)

Reviewed: `git diff 98e7cf0...HEAD -- . ':(exclude)planning'` at f1a1f09, plus the full
contents of each changed file.

## Checklist read

- code-check-infra.md: in full.
- code-check-r.md: by heading. Read: "An `information_schema` lookup by the literal table
  name misses what Postgres resolves"; "Postgres row order is never fixed unless the query
  fixes it…"; "Tests that silently do not run"; "A `skip_if_not()` skips only its own
  `test_that()` block"; "Under `R CMD check`, tests run from a temp dir against the
  INSTALLED package"; "`tempfile()` lives in the session tempdir…"; "A database driver's
  value is not a base R type…"; "`deparse(body(f))` excludes formal defaults…". Not read:
  the remaining ~110 headings (no tool, shape or pattern in this diff).
- code-check-shell.md: by heading. Read none; the diff has no shell, and the only shell
  used in review was read-only `git`. Not read: all ~85 headings.
- code-check-spatial.md: by heading. Read none; the diff touches no sf/terra/GDAL code.
  Not read: all ~95 headings.
- code-check.md: prose of every H3 under `## Mechanisms` read (tables skipped), with
  closest attention to "A guard that fails toward pass", "A fixture that cannot reach the
  failure mode", "A proxy is not the property", "A guard's scope, escape hatches, and
  remedies", "Restore the bug and prove the guard fires". No other headings read.

## Round 3's fix (test-frs_feature_index.R)

- `schemaname = pg_my_temp_schema()::regnamespace::text`: `regnamespace` exists from
  PostgreSQL 9.5 and `pg_my_temp_schema()` from 8.3, so every version fwapg runs on has
  both. `regnamespaceout` prints `pg_temp_N` unquoted, which is what `pg_indexes.schemaname`
  holds; `name = text` resolves (native operator from PG 12, implicit cast before). The
  session's temp schema exists because `.fi_fixture()` created temp tables first.
- With no index built the query returns zero rows and `expect_gt(length(defs), 0)` fails;
  with only other indexes, `expect_match(..., all = FALSE)` fails. The assertion is still
  able to fail.

## What was probed

- Built a worktree at HEAD (now removed); ran `test-test_table_names.R` there: 16 results,
  0 failed, 0 errors, 0 skipped.
- Enumerated every block the scanner exempts (non-live `test_that()` and mock top-level
  expressions) that holds a `working`/index string: all 12 are pure SQL-builder or mocked-DBI
  tests (`test-frs_channel_width.R` 226/236, `test-habitat_partition_293.R` 8,
  `test-utils.R` 284-823). None reaches a database. No exempt block calls a DBI function
  without a mock.
- Learnt live set: base list + `bcfp_conn`, `local_fwapg_indexpoint`.
- Catalog lookups in tests (`information_schema`, `pg_indexes`, `pg_class`, `to_regclass`,
  `pg_attribute`): every one is schema-qualified through `frs_test_tbl_parts()`, resolved
  through `to_regclass('pg_temp.…')` (session-local), filtered on `pg_my_temp_schema()`, or
  on a per-run name. None compares a bare temp-table name.
- Unqualified permanent DDL in live tests: none (only mocked strings and
  `.frs_migration_trial_sql()` text parsing). The one unqualified `DROP decoy_282` was
  qualified to `pg_temp.` on this branch.
- Package code that builds `working.` names itself: only `to` defaults (learnt),
  `frs_habitat()`'s label tables (per-run via `frs_test_label()`),
  `frs_habitat_partition(label =)` and `frs_habitat_species(to = NULL)` (no test calls
  either). Every other scratch name the package builds is either derived from its input
  or `pg_temp`/`TEMPORARY`.
- Length budget: the longest chains reached (`streams_<20>_acc_NNNNN_ovr_xx`,
  `<to_habitat>_near_river` + `_geom_gist_idx`, `barriers_<20>_gradient` +
  `_localcode_btree_idx`) stay at or under 63 bytes; acc-table indexes are unnamed.
- Sweep: matches only relations containing `<run>_` in `working`; relkinds mapped to
  the right DROP; `IF EXISTS` covers cascaded children. No test leaves a connection inside
  an open transaction (each `dbBegin()` test rolls back/disconnects in `on.exit`), so the
  teardown DROP cannot wait on this run's own lock.
- `frs_migration_trial` tables now `public.frs_trial_<run>_x` on the local fwapg, inside
  rolled-back transactions.

## Clean

No issues found.
