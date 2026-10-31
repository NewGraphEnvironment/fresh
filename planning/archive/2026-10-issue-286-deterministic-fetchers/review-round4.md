# Code-check round 4 (#286): `.frs_sql_exact()` and the SQL-text enumeration

Reviewed 2026-10-31 against HEAD 898aaf7 (`git diff 08b19b7...HEAD`, the fix is `1dacbb0..HEAD`).
Probes ran from a copy (`$SCRATCH/fresh_rev4`) against the local fwapg; the checkout was not modified.

## Checklist read

- **code-check.md** (37 H3): read in full the Mechanisms prose of "A guard that fails toward pass",
  "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that
  reads its own output", "A guard's scope, escape hatches, and remedies" (to the compression
  paragraph), "A fix lands in one of two callers that share a harness", "Restore the bug and prove
  the guard fires", "A shared working tree, and what generators leave in it". The other 6 Mechanisms
  ("A wrapper's exit", "Zero-length...", "The probe is broken...", "Written data outlives the fix",
  "Serialization loses meaning silently", "One fact derived twice") and the 23 standalone rules:
  index line only. 29 not read in full.
- **code-check-r.md** (115 H3): read in full "A value compared as `::text` in SQL has PostgreSQL's
  spelling", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words", "A database driver's
  value is not a base R type", "Postgres row order is never fixed...", "A `function(...)` mock hides
  arguments", "Tests that silently do not run", "A `skip_if_not()` skips only its own `test_that()`
  block", "testthat counts an uncaught error under `error`", "`identical(-0, 0)` is TRUE",
  "`tolerance` in testthat is RELATIVE", "`expect_false(identical(x, y))` cannot fail", "Under
  `R CMD check`, tests run from a temp dir", "A `pkg::` call in a test...", "`c(name = x)` keeps
  `x`'s own name", "`as.integer("NaN")` is `0`". 100 index-only.
- **code-check-spatial.md** (93), **code-check-shell.md** (70), **code-check-infra.md** (38): index
  lines only; nothing in this diff uses their tools beyond what round 1 covered (sf `st_as_text`
  is unchanged since round 1). 201 not read in full.

## Part 1: `.frs_sql_exact()` itself — no defect

Probed (`p3.R`):

| input | result |
|---|---|
| `2415.5725772752598` (FWA measure) | `"2415.5725772752598"`, Postgres reads back the stored double |
| `bit64::as.integer64(356000000)` | `is.numeric()` TRUE, writes `"356000000"` (not raw bits) |
| `208877L` | `"208877"` |
| `c(a = 5)` | `"5"`, name dropped by `sprintf()` |
| `-0` | `"-0"`; Postgres reads it as 0 |
| `1e-5`, `1e20` | `"1.0000000000000001e-05"`, `"1e+20"`: numeric literals, implicit cast to float8 in every consumer (`fwa_watershedatmeasure(integer, double precision)`, `ST_SimplifyPreserveTopology`, float8 `area_ha`) |
| `matrix(3)` | `"3"` |
| `NULL`, `numeric(0)`, `NA`, `NaN`, `±Inf`, `"1"`, `c(1, 2)` | error, label in message (`||` short-circuits before `as.double()` on length 0) |

Negative values cannot form `--`: no call site puts a `-` before the slot. `area_ha` is
`double precision` in both FWA tables, so `area_ha >= <numeric literal>` compares as float8.
The Postgres round-trip test fails under `%.10g` and under 15 digits (random draws need 17).

## Findings

- **[severity: fragile]** R/utils.R:1000-1006 (`.frs_resolve_aoi()`, list `blk`+`measure` branch) —
  builds its own `fwa_watershedatmeasure(%d, %s)` call with `measure <- as.numeric(aoi$measure)`
  through `%s`, i.e. `as.character()`: 15 significant digits and exponent form
  (`fwa_watershedatmeasure(360609038, 1e+05)`, `..., 1234.56789012346)` for 1234.5678901234569). This
  is the exact call `.frs_watershedatmeasure_sql()` was fixed for in rounds 2 and 3, and the branch
  fixed one builder while this sibling kept the old formatter. It is in a changed function (the
  `digits = 15` line) and the branch newly routes it from all three fetchers' `aoi` argument, whose
  docs point at "the other forms of `frs_extract()`'s `aoi`". The findings table does not list it.
  Measured impact is small: 0 of 4,907,441 FWA `downstream_route_measure` values need more than 15
  digits, so a segment start round-trips; but 4,596,866 `upstream_route_measure` values do, and for
  88 segments the 15-digit text of a segment's `upstream_route_measure` reaches or passes the next
  segment's `downstream_route_measure` (`p4.R`), the same `<=` boundary crossing round 3 found at 10
  digits. In the one such case compared, fwapg returned the same area either way (`p8.R`), so this
  is a consistency gap, not a demonstrated wrong polygon. `NA` measure writes a bare `NA` (loud SQL
  error, not silent). Remedy: have this branch call `.frs_watershedatmeasure_sql(aoi$blk,
  aoi$measure)`, so the one builder decides both formats.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** tests/testthat/test-frs_watershed_at_measure.R:312-327 ("writes a measure at
  full precision") — the fixture `2415.57257727526` has 15 significant digits, so every formatter
  keeping 15 digits round-trips it. Mutation in a copy: `.frs_watershedatmeasure_sql()` changed to
  `sprintf("%.15g", measure)` leaves `test-frs_watershed_at_measure.R` (26 blocks) and
  `test-frs_fetch_live.R` (7 blocks) at 0 failed, 0 error, 0 skipped. `as.character(measure)` is caught
  only by the separate `"e+"` assertion on 1e6 (6 failures), not by this test. So the call site's
  "full precision" is pinned by nothing; only the helper's own `%.17g` is (test-utils.R). The live
  test cannot reach it either, since FWA downstream measures are 15-digit exact (above). Remedy: use a
  17-digit fixture (e.g. `2415.5725772752598 + 2^-41`, or any `runif()` draw) whose `%.15g` text
  differs, and compare against `.frs_sql_exact(m)` text rather than `as.numeric(sent)` so R's parser
  is not in the assertion.
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode"

## Part 2: the enumeration table in findings.md

Rows checked against the code; verdicts on the listed rows are right (key `%d`/`as.integer()`,
max FWA blk < 2^31, NA would write a loud `NA`; measure, `simplify_m`, `area_ha_min` via
`.frs_sql_exact()`; `order_by` identifier-validated; sf `aoi` at 15 digits; geometry column constant).
Missed by the table:

| value | site | formatter | verdict |
|---|---|---|---|
| `aoi = list(blk, measure)` measure | `.frs_resolve_aoi()` | `%s` of `as.numeric()` | **finding 1** |
| `aoi = list(table, id)` numeric id | `.frs_resolve_aoi()` | `as.character()` (`1e+05`) | safe against an integer id column (int = numeric compares by value); a text id column errors loudly |
| `aoi` character | `.frs_resolve_aoi()` | `.frs_quote_string()`; table/column from options, identifier-validated | safe |
| `table`, `cols` | lake/wetland fetch (validation newly added), stream fetch | `.frs_validate_identifier()` | safe |

Not a finding, noted: lake/wetland `area_ha_min` is now exact while the habitat rule path's lake
floor (`utils.R:320`, `frs_habitat_predicates.R:259`) stays at `.frs_sql_num()` 10 digits; they
differ only for a floor with more than 10 significant digits, and `.frs_sql_num()` is an accepted
tradeoff.
