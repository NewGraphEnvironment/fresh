# Task: Route measures reach SQL through %s (15 significant digits), which can name a position past a segment's end (#274)

Four call sites interpolate a route measure into SQL with a `%s` conversion, which is R's default 15 significant digits. An IEEE 754 double needs 17 to be named uniquely, so the literal fresh sends can be larger than the measure it holds, and since measures resolve `[downstream, upstream)` that can name a position past a segment's end. fresh 0.49.0 (#287) fixed three of the four; `R/frs_point_locate.R` is left.

## Context (from plan mode)

fresh 0.49.0 (#287) fixed three of the issue's four sites by sending the measure through
`.frs_sql_exact()` (`%.17g`, `R/utils.R:783`) via `.frs_watershedatmeasure_sql()`
(`R/frs_watershed_at_measure.R:185`). The site still open is `R/frs_point_locate.R:28-32`, which
writes `fwa_locatealong(%s, %s)` with the raw measure: 15 significant digits, so a measure
at a stream's top can parse **above** the segment's end and `fwa_locatealong()` returns no row.

**What exploration found (it corrects the issue body):**
- **The key is already correct.** `frs_point_locate()` passes `as.integer(blue_line_key)` to
  `%s`, which prints `356000000`, not `3.56e+08` (probed: `sprintf("%s", as.integer(3.56e8))`).
  The issue's "second defect" is not present. Only the measure is wrong. I'll switch to `%d`
  anyway to match `.frs_watershedatmeasure_sql()`, and correct the issue body.
- **Every other measure interpolation in `R/` is already exact or isn't a position.**
  `frs_order_child.R:249` writes a distance threshold through `.frs_sql_num()`, and
  `frs_col_generate.R` sends column expressions. So this is the last site.
- **Probed on the local Docker fwapg:** blue line 354087614's top, sent with `%s`, parses
  above `max(upstream_route_measure)`; with `%.17g` it parses exact. The gate test's
  `head_blk` 360447231 is still a head case at its **exact** top (`old_rule` 0, closed ≥ 1),
  so the gate test keeps its pin once it sends the exact measure.
- The Postgres round trip of `.frs_sql_exact()` text is already pinned
  (`test-frs_fetch_live.R:122`), so no new round-trip test is needed. The issue's warning
  against verifying with `as.numeric()` is already documented at `test-utils.R:368`.

## Decided at the gate

Approved by the user at the plan gate, 2026-10-31.

- Scope: `frs_point_locate()` plus the gate test that models it, plus the research note's caveat.
- A non-finite or non-scalar measure now errors in R (`.frs_sql_exact()`'s message) before
  reaching the DB. Before, it went out as `NA` and failed in Postgres. This is intended.
- `as.integer()` silently truncating a fractional key stays as it is, consistent with
  `.frs_watershedatmeasure_sql()`. It's out of scope.

## Phase 1: Tests first
- [x] `tests/testthat/test-frs_point_locate.R`: a mocked test (`local_mocked_bindings(frs_db_query = ...)`,
      the pattern at `test-frs_watershed_at_measure.R:290`). It asserts the SQL is
      `fwa_locatealong(356000000, 1234567.8912345679)` for key `356000000` (double) and measure
      `1234567.8912345678`, and contains no `e+`
- [x] Same file: a non-finite measure (`NA`, `Inf`) errors before the DB with
      `downstream_route_measure must be a single finite number`
- [x] Confirm both fail on the current code

## Phase 2: Fix `frs_point_locate()`
- [x] `sprintf("... fwa_locatealong(%d, %s)", as.integer(blue_line_key), .frs_sql_exact(downstream_route_measure, "downstream_route_measure"))`
- [x] Phase 1 tests pass, along with the existing live test in the same file

## Phase 3: Gate test follows the caller (`tests/testthat/test-frs_fwapg_gate.R`)
- [x] `blk_top()` returns the stored `m` unrounded, because that is now what `frs_point_locate()` can express.
      Rewrite its comment: the 15-digit rounding caveat is gone
- [x] `skip_unless_head_case()` writes `m` with `.frs_sql_exact()` (lines 61, 64)
- [x] Update the `head_blk` comment: the flip no longer depends on 15-digit rounding
- [x] Run gated: `FRESH_FWAPG_TRIAL=<both migrations>` with `devtools::test(filter = "frs_fwapg_gate")`
      against local Docker fwapg. The head-case test must run (not skip) and pass. Without the trial it must skip

## Phase 4: Docs
- [x] `research/fwa_point_snap.md`: replace the "`%.17g` would round-trip; not changed in #266" caveat
      with what now holds (fixed in #274). Bump its Verified date
- [x] `devtools::document()` (no roxygen changes expected); `lintr::lint_package()` clean on touched files

## Phase 5: The rest of the class (plan correction from the Plan review)

The plan's "last site" claim was wrong: the grep needed `sprintf` and `measure` on one line, and the
`downstream_route_measure <= %s` segment pick puts them on different lines. 14 more sites.

- [x] Mocked tests: every `downstream_route_measure <= <x>` literal is the `%.17g` text, in
      `frs_network()` (direct, waterbody, and the `upstream_blk` check, with and without `upstream_measure`),
      `frs_network_upstream()`, `frs_network_downstream()`, `frs_network_prune()`, `frs_waterbody_network()`.
      Shared extractor in `tests/testthat/helper-sql_measure.R`. Red before the fix
- [x] Send each through `.frs_sql_exact()`
- [x] `frs_wsg_drainage()` left as is: its measures go to `fwa_downstream()`, which answered the same for
      two outlets 2 ULPs apart at both precisions (probed); bundled outlets have at most 10 digits

## Owed at the end (reported, done after merge)
- [ ] Edit the #274 issue body: remove the incorrect key claim from the Status block; list the segment-pick sites this branch fixed and `frs_wsg_drainage()` left as is

## Validation
- [x] Tests pass: full `devtools::test()` against local fwapg, plus the gated filter with `FRESH_FWAPG_TRIAL`
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

Verification: the Phase 1 mocked test is the red→green pin (shown red before Phase 2). The
gated head-case test runs `frs_point_locate()` at a stream's exact top against the trialled
migration and must return a row. NEWS line and the 0.49.1 bump go through `/gh-pr-merge`.

