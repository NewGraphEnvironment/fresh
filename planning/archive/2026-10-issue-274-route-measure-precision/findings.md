# Findings — Route measures reach SQL through %s (15 significant digits), which can name a position past a segment's end (#274)

## Issue context

> **Status, fresh 0.49.0 (#287):** three of the four sites below are fixed. `frs_watershed_at_measure()` and `.frs_resolve_aoi()`'s `list(blk, measure)` form now share `.frs_watershedatmeasure_sql()`, which writes the key with `%d` and the measure through `.frs_sql_exact()` (`%.17g`). **Left:** `R/frs_point_locate.R` still sends both the blue line key and the measure with `%s`. The key has a second defect there: a round key passed as a double goes out as `3.56e+08`, which Postgres reads as `numeric`, so no `fwa_locatealong()` signature matches it. The fix is the same two helpers.

## Problem

Four call sites interpolate a route measure into SQL with a `%s` conversion:

| file | line | function called |
|---|---|---|
| `R/frs_point_locate.R` | 29 | `fwa_locatealong()` |
| `R/frs_watershed_at_measure.R` | 82 | `fwa_watershedatmeasure()`, downstream |
| `R/frs_watershed_at_measure.R` | 95 | `fwa_watershedatmeasure()`, upstream |
| `R/utils.R` | 857 | `fwa_watershedatmeasure()` inside a predicate |

`%s` on a double is R's default 15 significant digits. An IEEE 754 double needs **17** to be
named uniquely (53 mantissa bits, `ceiling(53 * log10(2)) + 1`), so the literal fresh sends is
often not the measure fresh holds — and it can be **larger**.

That matters because measures resolve `[downstream, upstream)`. A measure that parses above a
segment's upstream end falls outside every segment's range, so `fwa_locatealong()` returns no
row, and `fwa_watershedatmeasure()` gets a position the network does not contain. It also means
fresh cannot express a stream's top boundary at all, even under fwapg's reworked closed range.

### Measured 2026-10-28

400 blue lines' top measures (`max(downstream_route_measure + length_metre)`), each sent back as
a SQL numeric literal and **parsed by PostgreSQL** — not by `as.numeric()`, which is itself not
correctly rounded and misleads this test:

| sent as | parses exactly | parses **above** the true measure |
|---|---|---|
| `%s` (today) | 228 of 400 | **86 of 400** (21%) |
| `%.17g` | **400 of 400** | 0 |

Example — `blue_line_key` 354087614, top measure `2273.674113292519`:

```r
sprintf("%s",    2273.674113292519)   # "2273.67411329252"   <- 9.1e-13 m ABOVE the segment end
sprintf("%.17g", 2273.674113292519)   # "2273.674113292519"  <- exact
```

### Not currently reachable, which is why this is its own issue

`frs_point_snap()` clamps its measure to a whole metre (`CEIL(GREATEST(ds, FLOOR(LEAST(us, m))))`),
and no candidate segment has an integer `upstream_route_measure`, so a clamped measure never lands
on a stream's top. The defect bites a caller that passes a raw measure of its own — which
`frs_point_locate()` and `frs_watershed_at_measure()` both accept as public arguments.

## Proposed Solution

- Use `%.17g` for the measure at the four sites above. Measured exact for all 400.
- The same shorthand appears in `tests/testthat/test-frs_fwapg_gate.R` (lines 31, 61, 64), which
  deliberately models what `frs_point_locate()` sends. Those follow the production change rather
  than lead it, or the test stops modelling the caller.
- Worth a note where it is easy to get wrong: **an R round-trip stays inexact even with `%.17g`**,
  because `R_strtod` behind `as.numeric()`/`scan()` is not correctly rounded and loses 1 ULP on
  many values. The string is faithful and PostgreSQL's parser is correctly rounded, so the
  R → SQL direction — the only one these sites use — is fixed. Don't "verify" the fix with
  `as.numeric(sprintf("%.17g", m)) == m`; it fails for reasons that have nothing to do with this.

Found while measuring fwapg's pending `fwa_indexpoint` rework in #266
(PR #273); recorded in `research/fwa_point_snap.md`. Out of scope there, deliberately not changed.



## Exploration, 2026-10-31

- `frs_point_locate()` already sends the key through `as.integer()`, and `sprintf("%s", as.integer(3.56e8))` is `356000000`. The issue's key defect is not present; only the measure is.
- Local Docker fwapg: blue line 354087614's top `max(upstream_route_measure)` sent with `%s` (`2273.67420120248`) parses above the stored top; with `%.17g` (`2273.6742012024752`) exact. (The issue's value 2273.674113292519 is from a different database load.)
- `head_blk` 360447231 at its exact top: parses exact, `old_rule` 0, closed >= 1, so it is still a head case once the gate test sends the exact measure.
- Other measure interpolations in `R/`: `frs_order_child.R:249` is a distance threshold through `.frs_sql_num()`; `frs_col_generate.R` is column expressions. No other position site.

## Gate test after #274, 2026-10-31

- With `FRESH_FWAPG_TRIAL` (both migrations) against local Docker fwapg: the head-case test runs (2 passed) and so does the watershed error pin (2 passed); the gate test skips because `FRESH_FWAPG_CURRENT` is unset. Without the trial, all three skip.
- The gate test does **not** discriminate `%s` from `%.17g` for `head_blk`: its `%s` top rounds *down* (parses below the stored top, see the probe above), so old `frs_point_locate()` would resolve it too. The pin for #274 is the mocked SQL-text test in `test-frs_point_locate.R`.
- The "2 before, 218 after" counts in the gate test and research note come from #266's sample, which sent tops at 15 digits; no committed script re-derives them (`data-raw/point_snap_tie_sweep.R` does not sample tops). Left attributed, not re-measured.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Plan review, 2026-10-31 (review-plan.md)

- **B1 confirmed:** 14 more position measures through `%s`, all the `WHERE blue_line_key = … AND downstream_route_measure <= %s ORDER BY … DESC LIMIT 1` pick: `frs_network.R` (direct, waterbody, `frs_check_upstream`), `frs_network_upstream.R`, `frs_network_downstream.R`, `frs_network_prune.R`, `frs_waterbody_network.R`. My enumeration missed them because the grep needed `sprintf` and `measure` on one line. Fixed in Phase 5.
- `frs_wsg_drainage.R:102` writes outlet measures with `DBI::dbQuoteLiteral()`, measured as 15 digits (`1234567.89123457::float8`). Not changed: `fwa_downstream()` on one blue line answered FALSE both ways for measures 2 ULPs apart, at 17 digits and at 15, so the rounding is not observable there. Bundled `wsg_outlet.csv` has at most 10 significant digits.
- G3: `data-raw/point_snap_tie_sweep.R:334-336` sends measures with `format(d$m, scientific = FALSE)`, a shared-width format at the default 7 significant digits. So #266's sweep counts were measured on rounded measures. The research note should say so (Phase 4 follow-up).
- G1/G2: the "185 of 400" and "2 before / 218 after" counts are from different populations than the issue's 86 of 400. The reviewer's read-only re-measure on the gate's own definition (guarded tops, 345 of 400 with a guarded segment): 165 of 345 parse above at 15 digits; exact tops resolve 2 (old rule) vs 331 (new rule).

- G3 follow-up filed: #289 (sweep writes measures at 7 digits; re-run with `.frs_sql_exact()`).
