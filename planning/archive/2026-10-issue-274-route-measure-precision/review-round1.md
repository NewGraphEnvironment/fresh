# Code-check round 1: #274 branch diff

## Checklist read

- index_code-check*.md (all five): in full.
- code-check-infra.md (41,794 bytes, over 40,000): the diff touches no infra; none of its headings apply. 0 sections read, all skipped.
- code-check-r.md: read "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's"; "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words..."; "A `function(...)` mock hides arguments the real callee no longer accepts"; "testthat counts an uncaught error under `error`, not `failed`"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED package"; "Postgres row order is never fixed unless the query fixes it...". That is 6 read; the rest were skipped on their index lines (no tool or shape in this diff).
- code-check-shell.md: none of its headings name anything in this diff (it has no shell). 0 read.
- code-check-spatial.md: none apply (the diff only formats SQL for fwa_locatealong). 0 read.
- code-check.md: every H3 under `## Mechanisms` read as prose (table rows skipped); no "Rules that stand alone" headings apply.

## Clean

No issues found.

### Checked, not findings

- `fwa_locatealong(integer, double precision)` is the only overload on the local fwapg (PG 17.5). A `%.17g` literal parses as numeric, and numeric to float8 is an implicit cast with a correct rounding, so the exact double reaches `v_measure`. `%d` on `as.integer()` gives the same text `%s` gave for an integer, and NA comes out as `NA` the way it did before.
- Blue line 360447231's guarded top is `1528.8506958829107`. At that exact value `skip_unless_head_case()` returns old_rule 0, closed 1, at_top TRUE, so the pin still holds at full precision. The top segment's geometry end M is the same value, and `ST_LocateAlong()` returns one point there. On the stale database `fwa_locatealong()` returns no row, so the red side is real.
- Modelling note, not a defect: inside `fwa_locatealong()`, `v_measure::numeric` keeps 15 digits (float8 to numeric uses DBL_DIG). The skip query instead rounds a 17-digit numeric literal. The two can disagree only when a value sits within about 1e-11 of a 4-decimal boundary. They agree for the pinned stream.
- The mock tests pass in a copy (`NOT_CRAN=true`, test_file: 0 failed, 0 error). Both would fail on the old code: the old `%s` gives `1234567.89123457`, and NA, Inf and a vector would reach the mocked `frs_db_query`, whose stop message does not match. The literal `1234567.8912345678` parses to `0x1.2d687e427f2dap+20` in both R here and Python's correctly rounded parser, and `%.17g` of it is `1234567.8912345679`, so the expected string does not depend on R_strtod's inaccuracy.
- External caller `stewardship_upper_wedzin_kwa/scripts/edna_positions-resolve.R:190` passes a numeric scalar measure, so the new input validation does not break it.
