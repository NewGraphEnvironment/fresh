## Outcome

Made `.frs_index_working()` idempotent with `IF NOT EXISTS` and added input table indexing to `frs_habitat_classify()` for 35x standalone speedup. Breaks indexing guarded by `gate` flag.

## Closed By

PR #151
