# fresh — Habitat Model Pipeline Plan

## Status: COMPLETE (v0.3.0 released)

## Goal

Build 4 server-side functions that replicate bcfishpass's ~34 SQL scripts as composable R functions: extract, break, classify, aggregate. All write to `working` schema via `DBI::dbExecute()`. Tested against live remote DB.

## Pipeline

```r
conn <- frs_db_conn()
params <- frs_params(conn)

conn |>
  frs_extract("whse_basemapping.fwa_streams_vw", "working.streams", aoi = aoi) |>
  frs_col_generate("working.streams") |>
  frs_break("working.streams", attribute = "gradient", threshold = 0.05) |>
  frs_classify("working.streams", label = "accessible", breaks = "working.breaks") |>
  frs_classify("working.streams", label = "co_spawning",
    ranges = params$CO$ranges$spawn[c("gradient", "channel_width")]) |>
  frs_aggregate(points = "working.breaks", features = "working.streams",
    metrics = c(total_km = "ROUND(SUM(ST_Length(f.geom))::numeric/1000, 1)"))
```

## Completed

- [x] #36 `frs_extract()` — stage data to working schema
- [x] #38 `frs_break()` family — find/validate/apply/wrapper
- [x] #39 `frs_classify()` — ranges/breaks/overrides labeling
- [x] #40 `frs_aggregate()` — network-directed summarization
- [x] #45 `frs_col_generate()` — PostgreSQL generated columns from geometry
- [x] #47 point_snap test speedup (35s→25s)
- [x] #48 classify breaks measure-level precision + fwa_upstream fix
- [x] `.frs_opt()` foundation for #44
- [x] v0.3.0 released (441 tests, 0 errors, 0 warnings)

## Open Issues (next session)

- #49 waterbody `extra_where` + `from` — needs two-CTE architecture (traversal on indexed FWA base table, filter on `from` table). Branch deleted, start fresh.
- #44 configurable column names — `.frs_opt()` foundation done, full pass deferred
- #46 further test AOI reduction — partially done (148s→105s)

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Write helper | `.frs_db_execute()` internal | `frs_db_query()` can't do DDL/DML |
| Return values | All return `conn` invisibly | Consistent `\|>` chaining |
| Break mechanism | `ST_LocateBetween()` on M-values | FWA has route measures |
| Break decomposition | 4 exported sub-functions | Flexibility |
| Generated columns | `frs_col_generate()` | gradient/measures auto-recompute after splits |
| Column name abstraction | `.frs_opt()` with FWA defaults | Spyda compatibility via options() |
| Classify breaks | `fwa_upstream()` not `fwa_downstream()` | Correct direction for barrier check |
| Waterbody traversal | Always on indexed FWA base table | Views without ltree indexes hang |
| Waterbody filtering | Two-CTE: traverse then filter | Separates fast traversal from cheap join |
| Test data | Single BLK streamline (15 segs) | Fast integration tests |
| Examples | Byman-Ailport bundled data + Richfield Creek live DB | Runnable plots + real pipeline |

## Errors Encountered

| Error | Resolution |
|-------|------------|
| MCP pg_write_query blocks DDL | Use R/DBI for write testing, MCP for reads only |
| `frs_break_find` attribute mode: breaks at existing segment boundaries | Use `fwa_slopealonginterval()` for fine-grained gradient sampling |
| `frs_break_apply` inserts NULL gradient | Carry forward all parent cols dynamically, skip generated cols |
| `fwa_downstream` wrong direction for barriers | Switch to `fwa_upstream(break, segment)` |
| `fwa_upstream()` on views hangs | Always traverse indexed FWA base table, filter separately |
| `sf::plot()` with `key.pos` breaks `add = TRUE` | Use `sf::st_geometry()` + manual colors |
