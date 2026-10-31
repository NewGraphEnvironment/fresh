# Code-check round 3 — #286 (branch 286-fetchers-fix-row-order-and-add-simplify, HEAD 1dacbb0)

## Checklist read

- **code-check.md** (37 headings): read the prose of all 14 H3s under `## Mechanisms` (table rows and
  evidence blocks skipped; "Serialization loses meaning silently" and "One fact derived twice" read
  from their opening paragraphs). Of the 23 stand-alone/security/spreadsheet headings, none names a
  tool or shape this diff uses; 23 not read in full.
- **code-check-r.md** (115): read in full "`$` on a list partial-matches…", "A database driver's
  value is not a base R type…", "A value compared as `::text`…", "A scalar helper called from
  `glue()`…", "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA`…",
  "An `information_schema` lookup…". 108 not read in full (index lines checked against the diff).
- **code-check-spatial.md** (93): read in full "FWA `upstream_route_measure` misses the next
  segment's start". 92 not read in full (index lines checked; the sf/WKT ones were probed directly
  instead, below).
- **code-check-shell.md** (70), **code-check-infra.md** (38): no shell or infra in the diff; 0 read
  in full, index only.

## The mechanism

Round 2's defect: a number's SQL text was chosen by R's formatting rules, not by the SQL type and
precision the value must keep. `sprintf("%s", 356000000)` is R's `as.character()` spelling
(`3.56e+08`), which Postgres types as `numeric`, and `numeric -> integer` is not an implicit cast,
so no `fwa_watershedatmeasure(integer, double precision)` matched. The same mechanism has a second
face that the fix walked into: a formatter that *rounds* (`%.10g`) chooses the value's precision,
and `fwa_watershedatmeasure()` decides which segment a measure is on with an exact
`s.downstream_route_measure <= v_measure`.

## Findings

- **[severity: bug]** R/frs_watershed_at_measure.R:182-184 (`.frs_watershedatmeasure_sql()`, all
  four call sites) — the round-2 fix formats the measure with `.frs_sql_num()` (`%.10g`), which
  keeps 10 significant digits. FWA measures carry about 15 (`2415.57257727526`,
  `1000540.95820945`), so the text sent is rounded, and half the time it is rounded **below** the
  measure given. When the caller passes a segment's own `downstream_route_measure` (the natural
  "watershed at the bottom of this segment" call), the rounded value is below that segment's start,
  fwapg's `downstream_route_measure <= v_measure` picks the previous segment, and the delineation
  changes or breaks. Measured on the local fwapg:
  - BULK: 10,365 of 20,817 segment starts (50%) round below their own start under `%.10g`; 0 do
    under `as.character()` / `%.15g` (the base branch's `%s` spelling).
  - `frs_watershed_at_measure(conn, 360609038, 2415.57257727526)`: **0 rows** on this branch, 1 row
    on base 08b19b7 (8,548,346 m²). Silent: no error.
  - `frs_watershed_at_measure(conn, 360609038, 3719.54902606317)`: errors on this branch
    (`line_interpolate_point: 2nd arg isn't within [0,1]` from `fwa_upstreambordercrossings`),
    1 row on base.
  - `%.17g` and `as.character()` both return the base result for the first case.
  So the fix regressed every non-integer measure with more than 10 significant digits, which is
  every full-precision FWA measure above ~100 m. Internal callers are unaffected
  (`frs_watershed_split()` passes `frs_point_snap()`'s whole-metre `CEIL` measures, which `%.10g`
  writes exactly up to 9,999,999,999), but external callers passing DB measures are not.
  Fix: format the measure at full precision, e.g. `sprintf("%.17g", as.double(measure))`
  (Postgres `float8in` round-trips it exactly), or `%.15g` to match base's text. Do not change
  `.frs_sql_num()` itself: its other callers compile rule SQL that tests pin byte-for-byte
  (`0.05` would become `0.050000000000000003` under `%.17g`). The new test cannot see this: it uses
  only whole measures (`208877`, `1e6`, `2e6`); a case with `2415.57257727526` expecting that
  text in the SQL would go red against HEAD.
  - **Rule:** code-check-spatial.md "FWA `upstream_route_measure` misses the next segment's start"

- **[severity: fragile]** R/frs_watershed_at_measure.R:184 and R/utils.R:107 (via
  `.frs_validate_simplify_m()` / `.frs_geom_select()` / `area_ha_min`) — a `bit64::integer64`
  value passes `is.numeric()`, `is.finite()` and `> 0`, then `%.10g` formats its raw bits.
  Measured: `.frs_watershedatmeasure_sql(360873822, bit64::as.integer64(208877))` writes
  `fwa_watershedatmeasure(360873822, 1.031989499e-318)` — a delineation at the stream mouth, no
  error — where base's `sprintf("%s")` wrote `208877`. The same value as `simplify_m` becomes a
  tolerance of `1.2e-322` (silently unsimplified). The key side is safe: `as.integer()` dispatches
  to `as.integer.integer64` and writes `360873822`. Low likelihood (needs a measure or tolerance
  fetched from a bigint column), but it is the exact fresh#248 shape and a regression for measures.
  `as.double()` after validation, before formatting, closes it (the full-precision measure
  formatter above should take `as.double()` too).
  - **Rule:** code-check-r.md "A database driver's value is not a base R type — and it fails twice"

## Every value the changed code turns into SQL text

| value | how it is written | verdict | evidence |
|---|---|---|---|
| watershed key (`blue_line_key`, `upstream_blk`) | `%d` of `as.integer()` | safe | validated single non-NA numeric; max FWA `blue_line_key` 380,887,830 < 2^31 (measured), so no NA overflow; `integer64` dispatches correctly (measured). A fractional key now truncates silently where base errored, a caller error, not flagged. |
| watershed measures | `.frs_sql_num()` `%.10g` | **bug** | finding 1 (precision) and finding 2 (integer64) |
| `simplify_m` | `.frs_sql_num()` after `.frs_validate_simplify_m()` | safe except integer64 | finite positive scalar; 10 significant digits is ample for a tolerance; `Inf`/`NA` rejected before formatting |
| `area_ha_min` | `.frs_sql_num()`, no validation | safe (loud on bad input) | character errors in `sprintf` (was injectable via `paste0` before); `NA` writes `area_ha >= NA`, a loud SQL error; `Inf` writes `'Infinity'`; `TRUE` writes `1` silently (caller error) |
| `order_by` | identifiers via `.frs_validate_identifier()` (`^[A-Za-z_][A-Za-z0-9_.]*$`), `*` refused | safe | tests cover `*`, NA, empty, numeric, injection |
| `cols`, `table` (lake/wetland now validated) | `.frs_validate_identifier()` | safe | — |
| `aoi` sf WKT | `st_as_text(digits = 15)` | safe | emits `1e+06` for a round coordinate; PostGIS `ST_GeomFromText('POLYGON ((1e+06 4e+05, …))')` parses it to `1000000 400000` (measured); 15 significant digits is sub-micrometre in BC Albers |
| `aoi` list `blk` + `measure` (now reachable from the fetchers) | `%d` of `as.integer()`; measure `%s` of `as.numeric()` | safe | `as.character()` keeps 15 digits, 0 of 20,817 BULK starts round below (measured); `2e+05` resolves to `fwa_watershedatmeasure(integer, double precision)` via the implicit `numeric -> float8` cast (EXPLAIN measured). Note this path and `frs_watershed_at_measure()` now format the same measure differently until finding 1 is fixed. |
| `aoi` list `table` + `id` | `as.character()` for numeric id | correct | `356000000` becomes `3.56e+08`; `int = numeric` compares exactly, so the right polygon is found (the int column is cast to numeric, so its btree index is not used — performance, not correctness) |
| `aoi` character | `.frs_quote_string()` per code | safe | unchanged |
| `limit` | `as.integer()` via `paste0` | safe | integer prints without exponent |
| `stream_order_min` | `as.integer()` via `paste0` | safe | same |
| `blue_line_key` filter in `.frs_build_where()` | `as.integer()` via `paste0` | safe | same |
| `bbox` | `%s` of double (unchanged code) | safe | `1e+06` is `numeric`, implicitly cast to `float8` by `ST_MakeEnvelope`; 15 digits |
| `watershed_group_code` | `.frs_quote_string()` | safe | unchanged |

## The round-2 test

`frs_watershed_at_measure writes a round key and measure in full` would go red if the key or a
round measure went back to `%s` (`3.56e+08`, `1e+06`), so it guards the round-2 defect. It cannot
see finding 1 (all its measures are whole) or finding 2 (no `integer64` input).
