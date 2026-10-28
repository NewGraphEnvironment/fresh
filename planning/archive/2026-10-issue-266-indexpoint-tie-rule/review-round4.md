# Review round 4 — the gate (live tests, helpers, sweep changes, prose)

## Checklist read

- `code-check-infra.md` — read in full (38,115 bytes).
- Index of all five read in full (`ck_index.txt`, 1,081 lines).
- Sections read in the larger files, selected by the shapes this diff uses:
  - `code-check.md` — the prose of every H3 under `## Mechanisms` (a guard that fails
    toward pass; a fixture that cannot reach the failure mode; a proxy is not the
    property; verification that reads its own output; a guard's scope and escape
    hatches; a fix in one of two callers; restore the bug and prove the guard fires;
    a wrapper's exit is not the work; zero-length/empty/unset; the probe is broken
    before the world is; written data outlives the fix; serialization loses meaning
    silently; one fact derived twice), plus `## Rules that stand alone`
    (`An assertion that matches an interpolated value cannot see the claim around it`,
    `Do not edit files a long test run is reading`, `Test the cold/create path`,
    `A preview flag is only safe if it previews`, `Documentation Staleness`).
  - `code-check-r.md` — testthat rows (`Tests that silently do not run`,
    `testthat counts an uncaught error under error, not failed`,
    `A skip_if_not() skips only its own test_that() block`,
    `expect_gt() and friends take no info argument`,
    `expect_false(identical(x, y)) cannot fail when the two are different types`,
    `tolerance in testthat is RELATIVE`, `testthat's failure snapshots land in tests/`,
    `A pkg:: call in a test passes devtools::test() and fails R CMD check`,
    `Under R CMD check, tests run from a temp dir against the INSTALLED package`);
    DBI/Postgres rows (`A database driver's value is not a base R type`,
    `A value compared as ::text in SQL has PostgreSQL's spelling`,
    `Postgres row order is never fixed unless the query fixes it`,
    `sprintf("%g", x) writes Inf and NA into SQL as bare words`,
    `An information_schema lookup by the literal table name misses what Postgres resolves`);
    `data-raw/` rows (`A data-raw/ script must load the source tree, not the installed
    package`, `on.exit() at a script's top level never fires`, `Regenerated binaries
    churn git even when nothing changed`, `Rscript reads a script as it runs`,
    `sort() and order() collate by LC_COLLATE`, `system2(stdout = TRUE) warns on a
    non-zero exit`, `paste() with a zero-length argument returns length ONE`,
    `as.integer("NaN") is 0`, `$ on a list partial-matches`).
  - `code-check-spatial.md` — the FWA/measure rows
    (`FWA upstream_route_measure misses the next segment's start`,
    `FWA main flow is not edge type 1000 alone`,
    `A Freshwater Atlas main stem's downstream end lies on the receiving river's
    centreline`, `A name is not a key`, `pdist::pdist() loses centimetres`).
  - `code-check-shell.md` — `A verification command can be shadowed by a shell function
    or alias` (which bit during this review: `diff` resolves to a git wrapper here, so
    the reproducibility comparison below was redone with `/usr/bin/diff` and `cmp`).

## What was run

All three gate states, on the local docker fwapg (stale: `fwa_indexpoint(point geometry,
tolerance, num_features)`, `exbc` still in `fwa_watershedatmeasure`, no `fwapg.db_version`):

| state | result | matches the claim |
|---|---|---|
| neither var set | 3 skips, 0 failures | yes |
| `FRESH_FWAPG_TRIAL` = both migrations | 4 passes, 1 skip (the gate test, `FRESH_FWAPG_CURRENT` unset) | yes |
| `FRESH_FWAPG_CURRENT=true`, stale DB | 5 failures across all 3 tests, 0 skips | yes |

In state 3 the failures are the load-bearing ones: `nrow(located)` 0, the CRS assertion,
`expect_no_error` catching `line_interpolate_point`, and both gate assertions. In state 2
the `expect_error` red side on the second connection fired and passed, so the second
connection neither deadlocked nor saw the trial's uncommitted catalog rows — consistent
with the migration files containing only `CREATE/DROP FUNCTION` and `COMMENT` (no relation
DDL, so nothing an executing session would block on).

Also run: the capped sweep (`FRESH_SWEEP_PSCIS=50 OBS=20 CROSSINGS=50 EXPENSIVE=5
TIED=5`), twice, end to end, exit 0 both times. `lintr::lint()` on the three changed R
files: 0 lints after dropping the two accepted linters. The committed
`data-raw/logs/indexpoint_266/*` were backed up and restored with `git checkout`; the
database is back to the old signature with no `working.tie266_*` tables left.

## Findings

- **[fragile] tests/testthat/test-frs_fwapg_gate.R:39-55 (and :21-29) —
  `skip_unless_head_case()` models the red side over a NARROWER segment population than
  `fwa_locatealong()` scans, so for ~0.55% of blue lines it declares a head case where the
  pre-rework function resolves, and the pin would go green on an un-migrated database.**

  The guard counts `old_rule` / `closed` / `at_top` with fresh's candidate guards attached
  (`localcode_ltree IS NOT NULL AND NOT wscode_ltree <@ '999' AND edge_type <> 1425`), and
  `blk_top()` takes its `max(upstream_route_measure)` over the same guarded set. The
  installed `fwa_locatealong()` has no such filter — its `WHERE` is `blue_line_key =
  v_blkey AND round(ds,4) <= round(m,4) AND round(us,4) > round(m,4)`, over every segment
  of the blue line (read from `pg_proc.prosrc` on the live database). So where a blue line
  carries an unguarded segment (1425 connector, NULL local code, `999.*`) whose range holds
  the guarded max, `old_rule = 0` while the real old rule matches.

  Measured on the stale docker fwapg, 20,000 blue lines sampled by
  `md5(blue_line_key::text)`: **109 (0.55%)** have `old_rule = 0` over the guarded set and
  `> 0` over all segments. Confirmed against the function itself — for each of these,
  `skip_unless_head_case()` would NOT skip (`old_rule=0, closed>=1, at_top=TRUE`) and the
  pre-rework `whse_basemapping.fwa_locatealong()` returns 1 row:

  ```
  blk 354088855  m=74.3359597627605   -> stale fwa_locatealong rows = 1
  blk 354088938  m=4.03291383473823   -> stale fwa_locatealong rows = 1
  blk 355992174  m=59.1591338249961   -> stale fwa_locatealong rows = 1
  ```

  `expect_gt(nrow(located), 0L)` passes there, pre-migration — a silent green, which is the
  single failure mode this whole gate exists to prevent.

  The pin as written is **not** affected: `head_blk = 360447231` has exactly two segments,
  both guarded, nothing above the top (verified), and state 3 showed it red. The defect is
  in the guard, not today's pin — but the guard's own comment claims "that predicate
  selecting nothing is the red side, and it is the same query on any database, whichever
  version of the function is installed", and that claim is what licenses trusting the pin
  on another database, another fwapg vintage, or after a pin swap. It is false.

  Fix: drop the three guard clauses from `skip_unless_head_case()`'s two `FILTER` counts so
  its population is the function's population (every segment of the blue line). `blk_top()`
  can keep its guards — it is choosing a measure, not modelling the predicate — and with the
  counts widened the 109 cases then skip correctly instead of passing vacuously.

- **[fragile] tests/testthat/helper-db.R:75-77 — `frs_fwapg_current_wanted()` accepts only
  `true` and `1`; every other truthy spelling silently reverts the suite to skipping.**

  `tolower(Sys.getenv("FRESH_FWAPG_CURRENT")) %in% c("true", "1")` is FALSE for `"true "`
  (a trailing space, which survives a Makefile `VAR = true `, a YAML `env:` block, or
  `export FRESH_FWAPG_CURRENT="true "`), and for `yes`, `y`, `t`, `on`, `TRUE\n`. On any of
  those the three tests go back to skipping with no indication that the request was not
  understood — a guard whose escape hatch is a typo, failing toward pass. Everything else
  about this gate is built so a stale database cannot hide; this is the one input that can
  turn it off quietly.

  Fix: `trimws()` the value, and treat a value that is neither recognised-true nor
  (empty | `false` | `0`) as an error rather than as "not set".

- **[fragile] data-raw/point_snap_tie_sweep.R:723 — `sweep_summary.csv` is a tracked
  artifact that still carries the non-reproducible `secs` column, so every rerun churns
  it.**

  `secs` was deliberately removed from the printed body at line 698 ("Leaving it here made
  two otherwise identical runs differ"), but `summary` is written whole to the CSV. Measured
  with two consecutive capped runs over identical inputs: `sweep.txt`'s body is byte-identical
  (`cmp` clean), and `sweep_summary.csv` differs only on `secs` (`8.8 -> 9`, `9.4 -> 9.3`).
  All four files under `data-raw/logs/indexpoint_266/` are tracked.

  Fix: write `summary[, setdiff(names(summary), "secs")]` to the CSV as well, so the timings
  live only in `sweep.txt`'s header.

## Attacks that did not find anything

- **`blk_top()`'s round trip is idempotent.** `as.numeric(sprintf("%s", m))` then
  `sprintf("%s", .)` inside `frs_point_locate()` reproduces the same 15-significant-digit
  string (`1528.85069588291` for the pin, checked on the database); a decimal of <= 15
  significant digits round-trips exactly through a double. The guard's SQL therefore sees
  the same literal the call sends. R's `as.character()` can emit scientific form
  (`1e+05`), but PostgreSQL parses that as a numeric constant and
  `round(1e+05::numeric, 4)` is well-formed, so the value does not diverge either.
- **`skip_unless_head_case()`'s `%1$s` / `%2$d` interpolation.** Three uses of one
  positional argument, SQL valid, `%2$d` fed an integer literal; no malformed statement and
  no second numeric value.
- **The `count(*)` type.** RPostgres returns bigint as `integer64`; `Ops.integer64` is
  registered on load (RPostgres imports bit64, and bit64 is in `Suggests`), so `== 0L` and
  `>= 1L` compare numerically, not bitwise. Verified by replicating the guard query. The
  zero-row case returns one row with `at_top = NA`, and `isTRUE(NA)` short-circuits to a
  skip before the counts are read.
- **`env` propagation and defer ordering.** `local_fwapg_indexpoint()` forwards `env`
  explicitly; `withr::defer()` prepends, so the queue at test exit is
  `disconnect(plain)`, `rollback(conn)`, `disconnect(conn)`. Had the order been wrong the
  rollback would have errored on a closed connection — state 2 produced no errors, and the
  database was back to the old signature afterwards.
- **The second connection in test 2.** The migrations touch only functions
  (`CREATE OR REPLACE FUNCTION`, two `DROP FUNCTION`, `COMMENT ON FUNCTION`); no relation
  takes `AccessExclusiveLock`, so `plain` neither waits nor reads uncommitted catalog rows.
  Confirmed by the state-2 run, where its `expect_error` matched
  `line_interpolate_point` from the committed (old) definition.
- **`FRESH_FWAPG_CURRENT` combinations.** Trial set + current set: the two pins pass and
  the gate test fails, because committed state is still stale — the right direction.
  Current set + database genuinely current: `frs_indexpoint_current(plain)` is TRUE, the
  red-side block is skipped, and `expect_no_error` plus the gate assertions carry the test;
  not vacuous (the call can and does error on a stale database). Current set + stale
  database: `local_fwapg_indexpoint()` correctly does not skip, and all three tests are red.
- **`expect_no_error` is not vacuous.** It fails in state 3 (`line_interpolate_point`) and
  passes in state 2 — the restore-the-bug direction is proven, not assumed.
- **The gate test's own query is not caught.** `'whse_basemapping.fwa_indexpoint'::regproc`
  is unambiguous both before and after the migration (the migration drops the 3-arg
  overload as it creates the 5-arg one), so the uncaught-throw design does not misfire on a
  database that merely has both.
- **`on.exit()` inside `test_that()`** does fire (checked directly), so the gate test's
  connection is closed.
- **`sprintf` specifier/argument counts** in the new `tied` CTE (`%s %s %d %s %d` against
  `positions, positions, n_tied, positions, n_expensive`), in `n_tied_all`, and in the three
  rewritten body lines: all balanced, all in the right order. The capped run's body reads
  `5 sampled positions plus 5 of the 20 tied ones`, which is the intended binding.
- **`format(d$m, scientific = FALSE)` in `chunked()`.** Its vector-wide 7-significant-digit
  rule does perturb values (299,351 of 536,831 CSV measures), but by at most **2.3e-10 m**
  against a predicate that compares `round(..., 4)` — immaterial to every count the sweep
  reports. `blue_line_key` is unaffected (0 of 536,831).
- **`out[[k]] <- got` when a whole chunk errors.** `[[<-` with NULL shortens the list, but
  every write is at a strictly increasing index and every removal shifts only
  higher indices down, so no result is ever overwritten; the results are NULL-filtered and
  rejoined on `ord`, never on arrival order.
- **`system("git rev-parse --short HEAD", intern = TRUE)`** warns rather than raises on a
  non-zero exit, and the script checks `length(head_sha) != 1L || !nzchar(head_sha)`
  instead of relying on the `tryCatch`.
- **`.frs_test_drop` / `frs_point_snap` / `frs_migration_trial` visibility** in the sweep:
  `pkgload::load_all(".")` defaults to `export_all = TRUE`, so the internals resolve, and
  the script loads the source tree rather than an installed copy.
- **Reproducibility.** Two capped runs over identical inputs produced a byte-identical
  `sweep.txt` body.

## Prose, checked against the evidence

Every number in `research/fwa_point_snap.md` and `NEWS.md` agrees with
`data-raw/logs/indexpoint_266/sweep.txt` and `planning/active/findings.md`:

| claim | log / findings | verdict |
|---|---|---|
| 3,463 tied groups, 440 within one stream (NEWS and note) | `pscis 2536/301` + `obs 927/139` = 3,463 / 440 | agrees |
| four CSV measures now resolve: wsg_outlet 356363393@322.567, 360880826@2100.018; crossings 356355973@4494.620, 360862508@10821.825 | `## answers that moved: 5` — same four, `was FALSE / now TRUE` | agrees |
| one position stops erroring, 359434058 @ 159 | fifth moved row; `base: 1 x line_interpolate_point`, absent in the other two states | agrees |
| 293 of 970 pre-existing errors in all three states | `watershed_error 294 / 293 / 293`, `errors by message` 293 x `more than one row returned by a subquery` | agrees |
| state table: 0/0/0 locatealong, 42/38/38 CSV, 85/86/86 watershed, 294/293/293 errors | `## three states` block | agrees |
| 49,725 positions, 23,540 CSV measures (20,000 + 3,294 + 246), 970 expensive | log body | agrees |
| trace_empty 2, unchanged | `trace_empty 2 / 2 / 2` | agrees |
| 2 before / 218 after of 400 streams; 185 of 400 round the top up | findings.md:312-320 | agrees |
| population figures (4,907,441 / 208,189 / 37,416 / 2,989,828 / 246 / 19,905 / 378,971) | drift guard, all 0 | agrees |

One apparent contradiction resolves correctly: findings.md:243 lists 360447231 among the
blue lines that do **not** flip, while the gate test pins it as one that does. The earlier
five-stream probe sent the full-precision measure; `blk_top()` sends the
15-significant-digit one, which for this stream rounds *down* into the closed range. The
test's own comment says exactly that, and the three-state run confirms it (red stale, green
trialled).

`CLAUDE.md`'s new section is accurate: the `FRESH_PG*` names, the `:` separator matching
`.Platform$path.sep`, the skip/fail semantics, and the `SET LOCAL lock_timeout = '60s'`
all match the code. `withr` is in `Imports`, as NEWS claims. `DESCRIPTION` is still
0.43.0 against a `# fresh 0.44.0` NEWS heading, which is the repo's stated convention
(version bump as the branch's final commit), not a defect.
