# Findings

## Current state
- `.frs_index_working()` in `R/utils.R:312` uses `CREATE INDEX ON %s ...` (no name, no IF NOT EXISTS)
- Called on output tables by: `frs_extract`, `frs_network_segment` (breaks + output), `frs_feature_index`, `frs_habitat_classify` (output only), `frs_habitat` (barriers)
- NOT called on input tables in `frs_habitat_classify` — `table` and `breaks_tbl` assumed pre-indexed
- When users call `frs_habitat_classify` directly (bypassing `frs_habitat`), ltree gist indexes missing → 35x slower

## Index naming
- PostgreSQL requires explicit name for `IF NOT EXISTS`
- Name format: `{table}_{col(s)}_{type}_idx` (e.g., `fresh_streams_wscode_ltree_gist_idx`)
- Must be unique within schema — include table name to avoid collisions
