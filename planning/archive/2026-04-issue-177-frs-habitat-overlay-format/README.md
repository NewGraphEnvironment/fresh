## Outcome

Dropped `format` and `long_value_col` parameters from `frs_habitat_overlay()`. Function now accepts a single canonical shape (row-per-(segment × species) with per-habitat indicator columns), parameterized by `species_col`, `by`, and `habitat_types`. Callers with non-canonical sources transform first (SQL view, R pivot, or link's `lnk_ingest_bcfishpass()`). Bridge mode retained.

## Closed By

PR #176.
