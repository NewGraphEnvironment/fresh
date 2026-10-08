# Review: #247 Phase 3 (`frs_feature_find(points = )`), round 1

## Findings

- **[severity: bug]** R/frs_feature_find.R:200 — `rows$feature_id <- as.character(snapped[[id_out]])`
  renders a double id in scientific notation. A numeric `col_id` stays
  double through the temp table and back (`frs_point_snap()` returns it
  as `numeric`), and `as.character(100000)` is `"1e+05"`, as is
  `as.character(2e6)`. Integer64 fields read from a GeoPackage or
  shapefile (for example `stream_crossing_id`) come back from `sf` as
  double, so any round id ends up stored as `"1e+05"` and no longer
  joins back to its source. Reproduced against local fwapg: an sf point
  with `id = 200000` wrote `feature_id = '2e+05'` to `to`. Fix: format
  numerics without scientific notation (for example
  `format(x, scientific = FALSE, trim = TRUE)` for doubles, or keep the
  native value in the temp table and cast `feature_id::text` in SQL).
  The table path does the cast server side, so it does not have this
  problem.

- **[severity: fragile]** R/frs_feature_find.R:212-219 together with
  `.frs_feature_find_write()` — appending across paths fails in one
  direction. In create mode the table path writes `col_id AS feature_id`
  with the column's native type (for example `integer`), while the
  points path always inserts `text`. A table-path call followed by a
  points-path `append = TRUE` call to the same `to` fails with
  `column "feature_id" is of type integer but expression is of type text`
  (reproduced live). The other order works, because Postgres
  assignment-casts integer to text. The plan says "`feature_id` cast to
  text". Either cast `feature_id` to `::text` in the table path's
  create-mode SELECT so both paths produce the same column type, or
  cast it to the target column's type in the points INSERT.

## Checked and OK

- `label_col` lookup by `match(snapped[[id_out]], key)`: types line up
  for integer `id_point`, character, factor (match coerces) and double
  ids.
- A snap that drops every point gives a 0-row `sf`. `st_drop_geometry`
  and the temp write handle it, and `to` is created empty with the right
  columns (verified live).
- The temp table is dropped by `on.exit`. `label_src` passes
  `.frs_label_expr()` identifier validation. `label_col` itself never
  reaches SQL.
- Tests: all 4 new `feature_find` tests pass, and the live one runs
  rather than skips on local fwapg. Fixture BLKs: a = 360710019,
  b = 360361683, c = 360615745, all distinct, so the BLK-scoping
  exclusion of site c is exercised for real. The mock tests are not
  vacuous: `written$feature_id` / `label_src` would fail on a positional
  mapping.
