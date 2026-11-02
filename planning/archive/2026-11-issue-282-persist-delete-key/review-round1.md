# Code check — round 1 (branch `282-custom-aoi-persist-deletes-other-watersh`)

## Checklist read

- `code-check-infra.md` — **in full** (41,794 bytes).
- `code-check.md` — `## Mechanisms` preamble and the H3 prose of "A guard that fails
  toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the
  property"; plus "Test the cold/create path of idempotent code, not just the warm
  no-op", "Documentation Staleness", "An assertion that matches an interpolated value
  cannot see the claim around it". Not read in full: the remaining 11 Mechanisms H3s,
  `## Rules that stand alone` (most), `## Security`, `## Spreadsheets and PDFs` —
  roughly 30 headings.
- `code-check-r.md` — read in full: "`on.exit()` at a script's top level never fires",
  "A `data-raw/` script must load the source tree, not the installed package",
  "`deparse(body(f))` excludes formal defaults", "An `information_schema` lookup by the
  literal table name misses what Postgres resolves", "A database driver's value is not a
  base R type", "A value compared as `::text` in SQL has PostgreSQL's spelling",
  "`expect_gt()` and friends take no `info` argument", "Under `R CMD check`, tests run
  from a temp dir against the INSTALLED package", "`R CMD build` ships every top-level
  directory not in `.Rbuildignore`", "Postgres row order is never fixed…",
  "`sprintf(\"%g\", x)` writes `Inf` and `NA` into SQL as bare words", "Tests that
  silently do not run", "`paste()` with a zero-length argument returns length ONE".
  Index-scanned and skipped as not reached by this diff: ~90 headings.
- `code-check-shell.md` — index only; no shell, `sed`, `git` or `gh` code in this diff.
  ~75 headings not read.
- `code-check-spatial.md` — index only; no terra/sf/GDAL code in this diff (the SQL
  touches PostGIS tables but no geometry operation is added). ~110 headings not read.

Probes run (all in a scratch dir, nothing written to the repo tree; DB writes confined
to `working.rev1_probe_*`, dropped after):

1. Re-ran `.frs_persist_streams()` three times against a stale target to test the
   added-key guard's idempotency. **Reproduced finding 1.**
2. `SELECT count(*) FROM (SELECT linear_feature_id … HAVING count(DISTINCT
   watershed_group_code) > 1)` on `whse_basemapping.fwa_stream_networks_sp` → **0**, and
   4,907,441 rows / 4,907,441 distinct `linear_feature_id`. The design premise the
   custom-AOI key rests on **holds**.

## Findings

- **[bug]** `R/utils.R:1299-1310` (`.frs_persist_streams()`) — the added-key NULL guard
  fires **only on the first call**, and the condition it guards survives. Measured:

  ```
  run 1: ERROR: working.rev1_probe_dst was missing linear_feature_id, which …
         dst = {id_segment=7, linear_feature_id=NULL}
  run 2: NO ERROR — guard inert
         dst = {7, NULL}, {7, 42}      <- the stale NULL row and the job's row, both
  run 3: ok
         dst = {7, NULL}, {7, 42}
  ```

  `.frs_persist_columns()` at `:1289` runs its `ALTER TABLE … ADD COLUMN` immediately
  and `.frs_db_execute()` is a bare `DBI::dbExecute()` with no transaction (`R/utils.R:1023`),
  so by the time the guard raises at `:1304` the column exists on the target
  permanently. On the next call `cols_added` is `character(0)`, `key %in%
  cols$cols_added` is `FALSE`, and the run proceeds to the exact outcome the guard was
  written to prevent: the pre-existing NULL-key rows are not matched by the DELETE,
  survive the INSERT, and stay as a stale copy of the same ground indefinitely.

  The guard's predicate is a **proxy** — "this call added the key column" — for the
  property it needs, which is "the target holds rows whose key is NULL". The property is
  directly measurable (`SELECT count(*) FROM <to> WHERE <key> IS NULL`, or a `count(*)`
  of rows not matched by the delete predicate) and is true on every subsequent run, not
  just the first. The error message ("Backfill … or drop … and re-run") invites a re-run,
  and a re-run with neither remedy applied silently passes.

  The test suite cannot see this: both new `.frs_persist_streams` tests
  (`tests/testthat/test-utils.R:498` and `:545`) `DROP TABLE IF EXISTS` the target before
  each run, so they only ever exercise the cold path. The mutation sweep row
  `"282 added-key NULL guard"` (`dev/mutation_sweep_sites_persist_282.csv:9`) is killed
  by the cold-path test, so the sweep reports the guard as covered while the second call
  is unprotected.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "Test the cold/create path of idempotent code, not just the warm no-op"

- **[bug]** `R/utils.R:1193-1200` (`.frs_persist_delete_key()`), reached from
  `R/frs_habitat.R:523` and `:668` — `!is.null(wsg_code)` is a proxy for "this run
  covers the whole watershed group", and in the documented **WSG + custom AOI** mode
  (`R/frs_habitat.R:10-13`, `:311-322`) it does not. There `job_aoi` becomes
  `watershed_group_code = 'X' AND (<aoi>)`, so the run holds a strict subset of group X,
  while the delete removes **all** of group X from `to_streams` and the INSERT writes
  back only the subset. Every row of group X outside the AOI is lost — the same
  deletes-what-it-will-not-put-back shape this branch is fixing, in the sibling arm of
  the same new chooser.

  Worse for an `sf` / named-list AOI with `wsg`: `:321` sets `job_aoi <- aoi` with no
  group predicate at all, so the working table can hold rows from several groups while
  the delete scopes to one. Those other groups' rows are then inserted on top of rows
  that were never deleted — duplication rather than loss.

  This behaviour is pre-existing, but the claims asserted about it are new and are
  false for mode 3:
  - `R/utils.R:1166-1167` — "The job segmented the whole group, so deleting it and
    reinserting is a clean replace."
  - `man/frs_habitat.Rd` / `R/frs_habitat.R:55-56` — "With `wsg`, the partition is the
    watershed group."
  - `NEWS.md:14` — "re-run the affected group with `wsg`, the whole-group overwrite
    being self-healing." A repair run issued as `wsg` + `aoi` makes the damage larger,
    and that is the shape a user narrowing a repair would reach for.

  The cheap fix is to key off what the run actually covers rather than off which
  argument was supplied — e.g. take the group arm only when `aoi` is `NULL`, or scope
  the group delete to the groups present in `from` and the segments it holds. At minimum
  the three claims above need the mode-3 carve-out stated, and `NEWS.md`'s repair
  instruction needs "with `wsg` alone, no `aoi`".
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "A guard's scope, escape hatches, and remedies"

- **[fragile]** `R/utils.R:1312-1316` (`.frs_persist_streams()`) — the partition DELETE
  and the INSERT run as two autocommitted statements (`.frs_db_execute()` →
  `DBI::dbExecute()`, no `BEGIN`). An INSERT that fails after the DELETE has run loses
  the partition from a table whose own roxygen calls it the persisted copy. Calling
  `.frs_persist_columns()` first removes the one known cause (fresh#114's column drift),
  which is why the ordering comment at `:1270-1273` exists, but a `statement_timeout`, a
  cancelled query, a disk-full, a constraint added by hand or a dropped connection all
  land in the same place. Pre-existing behaviour, but this branch creates the single
  place where one `BEGIN … COMMIT` would cover both the sequential and the mirai path,
  and the function's own documentation records the hazard without closing it.
  - **Rule:** code-check-infra.md "Two-statement DELETE/INSERT into a persist table is not atomic"

- **[fragile]** `data-raw/audit_persist_282.R:31` — `on.exit(DBI::dbDisconnect(conn))` at
  a script's top level registers on the global environment, which never exits, so the
  handler is never called and the disconnect the line promises does not happen. The
  script also `stop()`s at `:36` on a missing column, with the connection open. Use
  `withr::defer(DBI::dbDisconnect(conn), envir = globalenv())`.
  - **Rule:** code-check-r.md "`on.exit()` at a script's top level never fires"

- **[fragile]** `planning/active/findings.md:121`, `planning/active/task_plan.md:61`
  and `:190`, `planning/active/review-plan.md:137` and `:150` — all five state that the
  watershed-group predicate "uses `IS NOT DISTINCT FROM`", and three of them make the
  NULL-matching behaviour of that operator load-bearing for the ALTER-before-DELETE
  guard's rationale. The shipped statement is `watershed_group_code = <quoted>`
  (`R/utils.R:1254-1256`). Behaviourally this is moot — `wsg_code` cannot be `NULL` in
  that arm — but the planning record now describes a predicate the code does not use,
  and `review-plan.md:137`'s "G1 … NULL-group rows that `IS NOT DISTINCT FROM` will not
  match" is the reasoning behind the guard that finding 1 shows to be one-shot, so the
  two should be reconciled together.
  - **Rule:** code-check.md "Documentation Staleness"

## Checked and clean

- Identifier handling: every new table name goes through `.frs_validate_identifier()`
  (`^[A-Za-z_][A-Za-z0-9_.]*$`) and `wsg_code` through `.frs_quote_string()`; the
  mirai path's raw `'%s'` interpolation is gone. No injection surface added.
- Every `sprintf()` in the new code has matching placeholder and argument counts
  (checked one by one). No float or measure is written into SQL here, so
  `.frs_sql_exact()` / `.frs_sql_num()` are not in play.
- `.frs_persist_columns()`'s widened return has exactly one non-test caller
  (`R/utils.R:1289`); the only other reference is `tests/testthat/test-utils.R`, updated
  in the same diff. No caller still treats it as a string.
- `deparse(body(frs_habitat))` enumeration is sound: both persist sites are lexically
  inside `frs_habitat` (`.run_job` at `:375` and the mirai closure at `:566`), `deparse`
  breaks between arguments rather than inside `.frs_persist_streams(`, and string
  literals are not wrapped, so the `"DELETE FROM"` count of 2 is stable. The positive
  controls mean a rename fails loudly.
- The custom-AOI key's premise is measured and holds: `linear_feature_id` is globally
  unique in FWA (4,907,441 / 4,907,441), 0 values span a watershed group, and no
  `ST_Intersection` / `frs_clip()` / `ST_LocateBetween` appears in `R/frs_habitat.R`,
  `R/frs_extract.R` or `R/frs_network_segment.R`, so an AOI is a row predicate and never
  truncates a segment.
- `.Rbuildignore` already carries `^data-raw$` and `^dev$`, so neither new file ships.
- `.frs_same_relation()`'s case-fold comparison is adequate for the one call that
  matters: `streams_tbl` is always `paste0("working.streams_", job_label)`
  (`R/frs_habitat.R:429`, `:598`), so target and source are compared qualified-to-qualified.
- Not re-flagged, per the brief: the `to_barriers` `blue_line_key` delete (fresh#294),
  the +25 `indentation_linter` warnings, and `NEWS.md` 0.46.0's `id_segment` sentence.
