# Code check, round 2: frs_channel_width() (#234, phase 1)

Reviewed: `R/frs_channel_width.R` and `tests/testthat/test-frs_channel_width.R` (diff_phase1.patch), checked against the R section and the general mechanisms section of the checklist. Context files read: `R/utils.R` (`.frs_sql_num`, `.frs_quote_string`, `.frs_validate_identifier`, `.frs_db_execute`), the fwapg `channel_width_modelled.sql` and flooded's `fl_flood_surface.R`.

Verification run: `testthat::test_file("tests/testthat/test-frs_channel_width.R")` against the local fwapg gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 74 ]`.

## Findings

- **[severity: fragile, doc]** R/frs_channel_width.R:54-56. The round-1 fix #3 swapped one false fixed threshold for another. The hall2007/poisson2021 crossover depends on precipitation, not just area. Solving `hall2007 == poisson2021` with both presets' own coefficients and offsets (scan over 0.01 to 1e6 ha) gives:

  | precip (mm) | crossover (ha) |
  |---|---|
  | 12 (provincial minimum) | 189 |
  | 100 | 65 |
  | 200 | 43 |
  | 379 (1st percentile) | 29 |
  | 986 (median) | 16 |
  | 2000 | 9 |
  | 4000 | 5 |

  Percentiles come from `fwa_stream_networks_mean_annual_precip.map_upstream`. There is also a second crossing near 0.1 to 0.5 ha. Below it hall2007 is lower again, because its area term goes to 0 while poisson2021 carries the +1 offset.

  So "above it on smaller catchments" is false for most of BC. At the median precipitation, a 20 ha catchment already has hall2007 below poisson2021. "Roughly 30 ha" holds only near the dry end, about the 1st percentile of precipitation. It happens to fit Bulkley.

  Suggested wording: "hall2007 runs below poisson2021 except on small catchments. The crossover depends on precipitation: about 65 ha at 100 mm, 16 ha at 1000 mm and 5 ha at 4000 mm."

  The live test (test file lines 283-287) is safe for its fixed BULK AOI, because the 100 ha cut is above every BULK crossing. Its comment is accurate for BULK. The same cut on an AOI with precipitation below about 40 mm would fail. This is not a defect for the fixed fixture.

No other issues found. The round-1 fixes check out:

1. **pg_attribute / to_regclass lookup.** It resolves `table` the same way the later `ALTER`/`UPDATE` do: case folding, search_path, temp tables. The live test exercises this with `toupper(tbl)` and `to = "CW_Poisson"`. `col_source` is forced (line 131) before `to` is lower-cased (line 134), so the default label column is built from the original `to` and then lower-cased consistently. `sub()` keeps names, so `col_base[[to]]` is safe, and it is only reached after a `%in%` check.
2. **Single-statement overwrite.** One `UPDATE ... SET to = CASE WHEN guard THEN expr END, src = CASE WHEN guard THEN label END` is atomic. The CASE short-circuits per row, and the expressions reference columns, so planner constant-folding cannot evaluate a negative base early. The fill path is also one statement.
3. **Doc reworded.** See the finding above.

## Checked and not flagged

These fail loudly, with no data loss, or are accepted tradeoffs:

- **Array types pass the type guard.** `sub("\\(.*$", "", type)` also strips a trailing `[]`, because the typmod comes before it. So `character varying(20)[]` and `numeric(10,2)[]` pass. The `UPDATE` then fails with a raw Postgres type error instead of the function's own message. The run still fails loudly, so this is not a defect.
- **SQL precedence and literals.** `^` binds tighter than `*` and `/`. Unary minus binds tighter than `^`, so a negative custom exponent renders as `x ^ -0.5` and parses correctly. `.frs_sql_num` puts a space before negative literals, so no `+-` operator lexing occurs. `double ^ numeric-literal` resolves to `double ^ double`. `exp(0.30713)` is numeric and is cast to double when multiplied.
- **fwapg parity.** The expression is algebraically identical to `exp(0.30713 + 0.4577882*(ln(A+1) + ln(P+1) - ln(100) - ln(1000)))` with `round(::numeric, 2)`. The differences are NULL-precipitation handling (already documented) and floating-point paths at .xx5 boundaries (covered by the 0.05 m tolerance).
- **Very long identifiers.** A `to` of 57 or more characters makes `<to>_source` truncate at 63 characters. At exactly 63 characters for `to`, `col_source` truncates to the same name and the `UPDATE` errors with "multiple assignments". This is loud and an extreme edge case.
- **`$` partial matching on the model list.** Every name read with `$` (`k`, `a`, `b`, `a_div`, `digits`, ...) has an exact key, or no sibling with that prefix. Custom lists that contain `k_sql`/`label` are rejected as unknown fields.
- **Unit-test mocks.** `local_mocked_bindings(dbGetQuery, .package = "DBI")` and the `.frs_db_execute` mock cover every DB call the function makes. The identifier-validation tests error before any DB call.
- **Data-dependent assertions in the live tests.** These are fragile only if the fixture data changes: `nrow(filled) == n_null`, `stream_order == 1`, and the parity check, which would go `NA` if a MODELLED row had NULL `map_upstream`. They pass on the current fwapg (74/74).
