# Progress

## 2026-03-18 — Session 1 (planning)

- task_plan.md written: full pipeline, vignette sections, scenario comparison
- findings.md: lake rearing gap data, Skeena specifics, data sources

## 2026-03-18 — Session 2 (pre-vignette functions + architecture discovery)

### Completed
- `frs_edge_types()` — new exported helper + CSV (28 edge types). Tests pass.
- `frs_classify(where=)` — new param scopes classification by SQL predicate. Tests pass.
- `frs_col_join()` — new exported function for generic lookup table enrichment. Tests pass (unit + integration).
- `data-raw/example_byman_ailport.R` — fixed stale API (added conn param throughout), added channel_width enrichment.
- `inst/extdata/byman_ailport.rds` — regenerated with channel_width + channel_width_source columns.
- GitHub issue #51 filed for frs_col_join.
- Full test suite: 479 tests pass, 0 failures.

### Architecture discovery
- Realized `frs_network()` is the bottleneck: pulls all geometries to R memory, then pipeline functions need them back on DB.
- At province scale this blows up. Need `frs_network(to=)` to keep data on PostgreSQL.
- Mapped all 46+ callers across fresh, breaks, restoration_wedzin_kwa.
- Default `to=NULL` preserves all existing behavior — zero breakage for current callers.
- Only `data-raw/example_byman_ailport.R` and the new vignette need updating.

### Open decisions (for user)
1. Multi-table naming: `to = "working.byman"` → `working.byman_streams`, `working.byman_lakes` (prefix + suffix)?
2. Pipe ergonomics: user specifies table name in both `frs_network(to=)` and `frs_col_join("working.streams")` — acceptable?

### Files created/modified this session
| File | Action |
|------|--------|
| R/frs_edge_types.R | Created |
| inst/extdata/edge_types.csv | Created |
| tests/testthat/test-frs_edge_types.R | Created |
| R/frs_classify.R | Modified (added where param) |
| tests/testthat/test-frs_classify.R | Modified (added where tests) |
| R/frs_col_join.R | Created |
| tests/testthat/test-frs_col_join.R | Created |
| data-raw/example_byman_ailport.R | Modified (conn param, channel_width) |
| inst/extdata/byman_ailport.rds | Regenerated |
| man/frs_classify.Rd | Regenerated |
| man/frs_edge_types.Rd | Created |
| man/frs_col_join.Rd | Created |

### Next steps
1. Resolve open decisions on multi-table naming
2. Implement frs_network(to=) — Phase 1
3. Tests — Phase 2
4. Update data-raw script to use pipeline — Phase 3
5. Build habitat pipeline vignette — Phase 4
