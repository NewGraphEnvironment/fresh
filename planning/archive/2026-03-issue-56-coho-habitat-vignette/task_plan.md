# Task: Add `to` parameter to frs_network() + Habitat Pipeline Vignette

## Goal
Let `frs_network()` write results to working tables on the DB instead of pulling to R. This keeps the entire habitat pipeline on PostgreSQL — no R memory bottleneck when scaling to multiple watershed groups. Then build the habitat pipeline vignette that proves it works end-to-end.

## Status: planning

## Why this matters
At Byman-Ailport scale (2167 streams) pulling to R is fine. At province scale (many watershed groups), materializing all geometries in R just to write them back to PostgreSQL blows up memory. The DB should do all the heavy work:

```
frs_network(to = "working.streams") → col_join → col_generate → break → classify → aggregate
```

Everything stays in PostgreSQL until the final read. R orchestrates SQL.

---

## Phase 1: frs_network(to=) implementation ✓

### Change to frs_network()
- Add `to` param (character or NULL, default NULL)
- Add `overwrite` param (logical, default TRUE — consistent with frs_extract)
- When `to` is NULL: current behavior unchanged (returns sf or list of sf)
- When `to` is provided: write to DB table, return `conn` invisibly for piping
- Error if `clip` and `to` both provided (clipping is R-side spatial op)

### Multi-table naming convention
When `tables` has multiple entries and `to` is provided:
- `to` is a **prefix**: e.g. `to = "working.byman"` → `working.byman_streams`, `working.byman_lakes`
- Single-table: uses `to` as-is (no suffix)
- This matches how users think: "put my byman data in working"

### Internal changes
- `frs_network_direct()`: add `to` param
  - When NULL: `frs_db_query(conn, sql)` → returns sf (current)
  - When provided: `.frs_db_execute(conn, "CREATE TABLE <to> AS <sql>")` → returns NULL
- `frs_network_waterbody()`: same pattern
- Main `frs_network()`: handle overwrite (DROP IF EXISTS before CREATE)

### The SQL stays identical
The ltree traversal, network subtraction, waterbody key bridging — all the same. Only the execution path changes (st_read vs CREATE TABLE AS).

---

## Phase 2: Tests for to= ✓

### Unit tests (mocked)
- to=NULL generates SELECT (current behavior)
- to="working.test" generates CREATE TABLE AS SELECT
- Multi-table to="working.prefix" generates suffixed table names
- to + clip errors
- overwrite=TRUE generates DROP IF EXISTS
- Returns conn when to is provided

### Integration tests (live DB)
- Write single table, verify contents match current sf return
- Write multi-table, verify both tables exist with correct names
- Overwrite=TRUE replaces existing table
- Clean up working tables in on.exit

### Existing tests
- All 35+ existing frs_network tests use to=NULL (default) — zero changes needed

---

## Phase 3: Update callers in fresh ☐

### data-raw/example_byman_ailport.R
Current: `frs_network()` → sf → merge channel_width in R
Target: `frs_network(to=)` → `frs_col_join()` on DB → read back

### roxygen examples in R/frs_network.R
- Add `to=` example showing pipeline pattern
- Keep existing sf examples (show both patterns)

### R/frs_clip.R example
- No change needed (clip and to are incompatible, frs_clip works on sf)

### Vignettes
- subbasin-query: no change (reads sf for tmap plotting)
- fwa-network-query: no change (reads sf for analysis)
- NEW habitat-pipeline: uses to= for full pipeline demo

---

## Phase 4: Habitat pipeline vignette ☐

Uses the full pipeline on DB:
1. `frs_network(to = "working.byman_streams")` — extract + stay on DB
2. `frs_col_join()` — channel_width, upstream_area, MAP
3. `frs_col_generate()` — gradient, measures from geometry
4. `frs_break()` — CO spawn gradient threshold
5. `frs_classify()` — accessible, co_spawning, co_rearing, co_lake_rearing (edge_type aware)
6. `frs_aggregate()` — habitat km upstream of crossings
7. Scenario comparison — three gradient thresholds

### Lake rearing section
- bcfishpass scores lake segments rearing=0 (bcfishpass#7)
- fresh fixes via `frs_classify(where = "edge_type IN (1050)")`
- Quantify: X km rearing gained

### Cache pattern
- .Rmd.orig (live) / .Rmd (cached)
- params$update_gis controls
- data-raw script generates cache

---

## Phase 5: Downstream packages (separate PRs, future) ☐

These all use to=NULL (default) — no breakage, no change needed:
- breaks: app_server.R — returns sf for Shiny UI
- restoration_wedzin_kwa: fwa_extract_flood.R, prioritization_score.R — returns sf

They CAN opt into to= later for scaling, but it's not required.

---

## Blast Radius Summary

### Safe (to=NULL default, zero changes)
| File | Why |
|------|-----|
| fresh tests/testthat/test-frs_network.R (35+) | All use default to=NULL |
| fresh vignettes/subbasin-query.Rmd | Reads sf for plotting |
| fresh vignettes/fwa-network-query.Rmd | Reads sf for analysis |
| breaks R/app_server.R | Returns sf for Shiny |
| restoration scripts/ (2 files) | Returns sf |

### Needs update
| File | Change |
|------|--------|
| data-raw/example_byman_ailport.R | Use to= + frs_col_join pipeline |
| R/frs_network.R roxygen | Add to= examples |
| NEW vignettes/habitat-pipeline.Rmd.orig | Full pipeline demo |

---

## Open Questions

1. **Multi-table naming**: prefix+suffix (`to = "working.byman"` → `working.byman_streams`) — confirm this is right?
2. **Should `to` accept a named list** for explicit control? e.g. `to = list(streams = "working.s", lakes = "working.l")`
   - Simpler to just use prefix convention. Named list adds complexity for rare use case.
3. **frs_network + frs_col_join pipe**: when to= is provided, frs_network returns conn — but frs_col_join needs the table name too. The pipe would be:
   ```r
   conn |>
     frs_network(blk, drm, to = "working.streams") |>
     frs_col_join("working.streams", ...)
   ```
   User specifies table name twice. Acceptable? Alternative: return a list with conn + table names.

## Errors Encountered
(none yet)
