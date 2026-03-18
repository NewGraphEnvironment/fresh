# fresh — Findings

## DB Connection Patterns
- fpr uses `Sys.getenv('PG_DB_SHARE')` etc. for defaults — zero config for existing users
- fpr `fpr_db_query()` uses `sf::st_read()` for spatial results, `DBI::dbGetQuery()` for non-spatial
- `frs_db_query()` only does SELECT via `sf::st_read()` — need `.frs_db_execute()` for writes

## FWA Schema (fwapg)
- Key tables: `fwa_stream_networks_sp` (base, has ltree GiST indexes), `fwa_streams_vw` (enriched, has channel_width + mad_m3s), `fwa_lakes_poly`, `fwa_wetlands_poly`
- `fwa_stream_networks_sp`: has `wscode_ltree`, `localcode_ltree` — GiST indexed for fast traversal
- `fwa_streams_vw`: has `wscode`, `localcode` (no `_ltree` suffix) — NO ltree indexes (it's a view)
- `fwa_stream_networks_channel_width`: separate lookup table for channel_width
- Network topology via `blue_line_key`, `downstream_route_measure`, `localcode_ltree`, `wscode_ltree`

## bcfishpass Schema
- `bcfishpass.streams` — base table with GENERATED ALWAYS columns for gradient, measures, length, segment ID
- `bcfishpass.streams_vw`, `streams_co_vw`, etc. — views joining to barriers/habitat
- Key columns: `wscode`, `localcode` (ltree type but NO `_ltree` suffix)
- Views do NOT have ltree GiST indexes — `fwa_upstream()` traversal hangs on views
- `channel_width` comes from fwapg (`fwa_streams_vw`), copied to bcfishpass

## bcfishpass break_streams() Pattern
- Uses `ST_LocateBetween()` on M-values — no geometry splitting needed
- gradient is GENERATED ALWAYS: `round(((ST_Z(end) - ST_Z(start)) / ST_Length(geom))::numeric, 4)`
- Also generated: `downstream_route_measure` (start M), `upstream_route_measure` (end M), `length_metre`
- `segmented_stream_id` generated from `blk::text || '.' || round(start_m * 1000)::text`
- break_streams carries forward: channel_width, mad_m3s, upstream_area_ha, stream_order_parent/max, map_upstream
- Does NOT carry gradient — it auto-recomputes from generated column

## fwa_slopealonginterval()
- `fwa_slopealonginterval(blk, interval, distance, start_m, end_m)`
- Computes gradient at `interval` metre resolution along a blue_line_key
- Uses Z values from geometry to compute rise/run over `distance` metres
- Produces break measures that fall WITHIN existing FWA segments
- Must use valid start/end measures from the FWA base table (strict validation)

## Network Traversal Functions
- `fwa_upstream(wsc_a, loc_a, wsc_b, loc_b)` — returns TRUE if b is upstream of a
- `fwa_downstream(wsc_a, loc_a, wsc_b, loc_b)` — returns TRUE if b is downstream of a
- For barrier accessibility: use `fwa_upstream(barrier, segment)` to check if segment is above barrier
- Same-BLK barrier check: compare `downstream_route_measure` directly (no ltree needed)
- Cross-BLK: `fwa_upstream` with ltree codes from indexed FWA base table

## Waterbody Network Pattern
- Waterbody tables (lakes, wetlands) have NULL localcode — can't use fwa_upstream directly
- Bridge through stream network: collect DISTINCT waterbody_key from upstream streams, JOIN to polygon table
- Traversal MUST use indexed FWA base table (`fwa_stream_networks_sp`)
- Filtering (by habitat, stream order, etc.) is a separate step AFTER traversal
- Two-CTE architecture: `wbkeys_network` (fast traversal) → `wbkeys_filtered` (cheap join to from table)

## Column Name Variations
- FWA base table: `wscode_ltree`, `localcode_ltree`
- fwapg views (`fwa_streams_vw`): `wscode`, `localcode`
- bcfishpass: `wscode`, `localcode`
- fresh `.frs_opt()`: configurable via `options(fresh.wscode_col = "wscode")`
- Stream guards (`.frs_stream_guards()`) accept wscode_col/localcode_col params

## Working Schema
- `working` schema: confirmed CREATE TABLE + DROP TABLE access via `DBI::dbExecute()`
- MCP pg_write_query blocks DDL ("dangerous patterns") — use R/DBI for testing writes
