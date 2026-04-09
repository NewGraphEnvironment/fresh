# fresh 0.10.0

Network cluster connectivity analysis.

- `frs_cluster()` — generic cluster connectivity validation. Groups adjacent segments sharing one label, checks if another label exists upstream, downstream, or both on the network. Disconnected clusters set to FALSE. Uses `ST_ClusterDBSCAN` for spatial clustering and `fwa_downstreamtrace()` for downstream trace with gradient bridge and distance cap ([#107](https://github.com/NewGraphEnvironment/fresh/issues/107))
- Per-species cluster config in `parameters_fresh.csv` — `cluster_rearing`, `cluster_direction`, `cluster_bridge_gradient`, `cluster_bridge_distance`, `cluster_confluence_m`. Anadromous species opt in; resident species do not
- `direction = "both"` evaluates upstream and downstream independently, keeps clusters valid in either direction

# fresh 0.9.0

Flexible AOI, configurable access gating, and feature indexing.

- `frs_habitat()` accepts any AOI — sf polygons, WHERE clauses, ltree filters — not just WSG codes. Add `species` and `label` params for custom runs ([#96](https://github.com/NewGraphEnvironment/fresh/issues/96))
- `gate` parameter on `frs_habitat_classify()` — set `FALSE` to classify raw habitat potential without access restrictions ([#98](https://github.com/NewGraphEnvironment/fresh/issues/98))
- `blocking_labels` parameter — configurable which labels restrict access. Default `"blocked"`. Set `c("blocked", "potential")` for conservative analysis. Only `"blocked"` and `gradient_N` block by default; everything else passes through
- `frs_feature_find()` — locate any point features on the network (crossings, observations, stations) with `col_id` for feature identity ([#92](https://github.com/NewGraphEnvironment/fresh/issues/92))
- `frs_feature_index()` — index upstream/downstream relationships between segments and features as ID arrays ([#93](https://github.com/NewGraphEnvironment/fresh/issues/93))
- `frs_break_find()` slimmed to gradient-only. Point/table modes moved to `frs_feature_find()`
- Province-wide run completed: 229 WSGs, 5.98M segments
- Classify growth penalty fixed: constant-time DELETE by `watershed_group_code` ([#91](https://github.com/NewGraphEnvironment/fresh/issues/91))

# fresh 0.8.0

Unified pipeline, domain-agnostic network segmentation, and major performance improvements.

## New functions
- `frs_network_segment()` — domain-agnostic network segmentation. Extracts, enriches, breaks at any point sources, assigns `id_segment`. One table, one copy of geometry.
- `frs_habitat_classify()` — long-format habitat classification. One row per segment x species with `accessible`, `spawning`, `rearing`, `lake_rearing`. Species-specific accessibility via break label filtering.
- `frs_feature_find()` — locate any point features on the network (crossings, observations, stations). Replaces `frs_break_find()` points/table modes.
- `frs_feature_index()` — index upstream/downstream relationships between segments and features. Stores feature ID arrays per segment.

## Pipeline changes
- `frs_habitat()` rewritten to wrap `frs_network_segment()` + `frs_habitat_classify()`. Auto-generates gradient barriers per WSG from species parameters.
- `to_streams` + `to_habitat` params replace `to_prefix` for persistent output tables.
- mirai replaces furrr for parallel execution — lighter daemons, foundation for crew.aws.batch.
- `frs_break_find()` slimmed to gradient-only (island detection). Point/table modes moved to `frs_feature_find()`.

## Performance
- Island-based gradient barriers: 85% fewer barriers than interval method ([#86](https://github.com/NewGraphEnvironment/fresh/issues/86))
- Accessibility recycled by threshold group: 5 queries → 2 for species sharing thresholds ([#89](https://github.com/NewGraphEnvironment/fresh/issues/89))
- Classify growth penalty fixed: constant time DELETE by `watershed_group_code` ([#91](https://github.com/NewGraphEnvironment/fresh/issues/91))
- Breaks table indexed with ltree GIST for cross-BLK queries: 15x speedup
- Province-wide: 229 WSGs, 5.98M segments completed

## Other
- `id_segment` for unique sub-segment identity after breaking ([#82](https://github.com/NewGraphEnvironment/fresh/issues/82))
- `col_blk` + `col_measure` on break sources for configurable column names ([#80](https://github.com/NewGraphEnvironment/fresh/issues/80))
- `.frs_sql_num()` for locale-safe numeric SQL literals
- Docker-based local fwapg tuned for M4 Max Pro (128GB/16 cores)

# fresh 0.7.0

Local Docker fwapg instance and generic network-referenced classification via `break_sources`.

- Replace `falls` parameter with `break_sources` list across pipeline (`frs_habitat()`, `frs_habitat_partition()`, `frs_habitat_access()`) — accepts any number of point tables with `label`, `label_col`, and `label_map` for flexible classification ([#70](https://github.com/NewGraphEnvironment/fresh/issues/70))
- Add `label` and `source` columns to breaks table for provenance tracking
- Ship `inst/extdata/falls.csv` (3,294 barrier falls) and `inst/extdata/crossings.csv` (533k crossings) with `data-raw/` refresh scripts
- Add Docker-based local fwapg: containerized PostGIS + loader with GDAL/psql/bcdata ([#63](https://github.com/NewGraphEnvironment/fresh/issues/63))
- Fix Phase 2 sequential mode to reuse `conn` instead of calling `frs_db_conn()`

# fresh 0.6.0

Parallelized multi-WSG habitat pipeline — 2.5x speedup over sequential on BULK.

- Add `frs_habitat()` — orchestrator: run the full habitat pipeline across watershed groups with `furrr` parallelism ([#61](https://github.com/NewGraphEnvironment/fresh/issues/61))
- Add `frs_habitat_partition()` — generic partition prep (extract, enrich, pre-compute breaks). Accepts any AOI, not just WSG codes
- Add `frs_habitat_access()` — gradient + falls barrier computation at a threshold, deduplicated across species sharing the same `access_gradient_max`
- Add `frs_habitat_species()` — classify one species with pre-computed access and habitat breaks
- Both Phase 1 (partition prep across WSGs) and Phase 2 (species classification) parallelize via `furrr::future_map()` when `workers > 1`
- Benchmark scripts and logs in `scripts/habitat/`

# fresh 0.5.0

Watershed-group habitat pipeline — run the full pipeline across all species in a WSG.

- Add `where` parameter to `frs_extract()` for SQL predicate filtering, ANDed with `aoi` when both provided ([#60](https://github.com/NewGraphEnvironment/fresh/issues/60))
- Add `frs_wsg_species()` to look up species presence and bcfishpass view names per watershed group from bundled `wsg_species_presence.csv`
- Add `data-raw/pipeline_wsg.R` — runs full habitat pipeline per species per WSG with timing (baseline: 20 min for BULK, 7 species, 32K segments)

# fresh 0.4.1

- Add `frs_categorize()` for priority-ordered boolean-to-category collapse — mapping codes for QGIS, reporting, gq style registry ([#57](https://github.com/NewGraphEnvironment/fresh/issues/57))
- Refine habitat pipeline vignette: code below each narrative section with function links, 2x2 scenario grid, access barriers on habitat map

# fresh 0.4.0

Coho habitat pipeline — classify habitat on the database at any scale. New vignette proves the workflow on the Byman-Ailport subbasin of the Neexdzii Kwa.

- Add `frs_col_join()` for generic lookup table enrichment — channel width, MAD, upstream area, any key ([#51](https://github.com/NewGraphEnvironment/fresh/issues/51))
- Add `frs_edge_types()` lookup helper with bundled FWA edge type CSV (41 codes from GeoBC User Guide)
- Add `to` param to `frs_network()` — write results to DB working tables instead of pulling to R, scales to any number of watershed groups ([#53](https://github.com/NewGraphEnvironment/fresh/issues/53))
- Add `where` param to `frs_classify()` — scope classification by SQL predicate for edge-type-aware and accessibility-filtered habitat modelling
- Add `where` and `append` params to `frs_break_find()` table mode — filter points table and combine multiple break sources (gradient + falls) in one breaks table ([#38](https://github.com/NewGraphEnvironment/fresh/issues/38))
- Add `exclude_edge_types` param to `frs_point_snap()` — only exclude subsurface flow (1425) by default, not wetland connectors (1410) ([#52](https://github.com/NewGraphEnvironment/fresh/issues/52))
- Bundle bcfishpass habitat parameter CSVs and fresh-specific access gradient thresholds ([#54](https://github.com/NewGraphEnvironment/fresh/issues/54))
- Add coho habitat pipeline vignette: extract → enrich → break (gradient + falls) → classify (accessible, spawning, rearing, lake rearing) → aggregate → scenario comparison

# fresh 0.3.1

- Add `from` and `extra_where` params to waterbody specs in `frs_network()` for filtering waterbodies to those connected to habitat streams ([#49](https://github.com/NewGraphEnvironment/fresh/issues/49))
- Network traversal table configurable via `.frs_opt("tbl_network")` ([#44](https://github.com/NewGraphEnvironment/fresh/issues/44))

# fresh 0.3.0

Server-side habitat model pipeline — replaces ~34 bcfishpass SQL scripts with 4 composable functions. See the [function reference](https://newgraphenvironment.github.io/fresh/reference/) for details.

- Add `frs_extract()` for staging read-only data to writable working schema ([#36](https://github.com/NewGraphEnvironment/fresh/issues/36))
- Add `frs_break()` family (`find`, `validate`, `apply`, wrapper) for network geometry splitting via `ST_LocateBetween` and `fwa_slopealonginterval` gradient sampling ([#38](https://github.com/NewGraphEnvironment/fresh/issues/38))
- Add `frs_classify()` for labeling features by attribute ranges, break accessibility (via `fwa_upstream`), and manual overrides — pipeable for multi-label classification ([#39](https://github.com/NewGraphEnvironment/fresh/issues/39))
- Add `frs_aggregate()` for network-directed feature summarization from points ([#40](https://github.com/NewGraphEnvironment/fresh/issues/40))
- Add `frs_col_generate()` to convert gradient/measures/length to PostgreSQL generated columns — auto-recompute after geometry changes ([#45](https://github.com/NewGraphEnvironment/fresh/issues/45))
- Add `.frs_opt()` for configurable column names via `options()` — foundation for spyda compatibility ([#44](https://github.com/NewGraphEnvironment/fresh/issues/44))
- All write functions return `conn` invisibly for consistent `|>` chaining

# fresh 0.2.0

- **Breaking:** All DB-using functions now take `conn` as the first required parameter instead of `...` connection args. Create a connection once with `conn <- frs_db_conn()` and pass it to all calls. Enables piping: `conn |> frs_break() |> frs_classify()` ([#35](https://github.com/NewGraphEnvironment/fresh/issues/35))

# fresh 0.1.0

- Multi-blue-line-key support for `frs_watershed_at_measure()` and `frs_network()` via `upstream_blk` param ([#20](https://github.com/NewGraphEnvironment/fresh/issues/20))
- Add `frs_watershed_at_measure()` for watershed polygon delineation with subbasin subtraction
- Add `frs_network()` unified multi-table traversal function replacing per-type fetch functions
- Add `frs_default_cols()` with sensible column defaults for streams, lakes, crossings, fish obs, and falls
- Add `upstream_measure` param for network subtraction between two points on the same stream
- Add `frs_waterbody_network()` for upstream/downstream lake and wetland queries via waterbody key bridge
- Add `wscode_col`, `localcode_col`, and `extra_where` params for custom table schemas
- Add `frs_check_upstream()` validation for cross-BLK network connectivity
- Add `blue_line_key` and `stream_order_min` params to `frs_point_snap()` for targeted snapping via KNN ([#16](https://github.com/NewGraphEnvironment/fresh/issues/16), [#17](https://github.com/NewGraphEnvironment/fresh/issues/17), [#7](https://github.com/NewGraphEnvironment/fresh/issues/7), [#18](https://github.com/NewGraphEnvironment/fresh/issues/18))
- Add stream filtering guards: exclude placeholder streams (999 wscode) and unmapped tributaries (NULL localcode) from network queries; `include_all` to bypass. Subsurface flow (edge_type 1410/1425) kept in network results (real connectivity) but excluded from KNN snap candidates ([#15](https://github.com/NewGraphEnvironment/fresh/issues/15))
- Add `frs_clip()` for clipping sf results to an AOI polygon, with `clip` param on `frs_network()` for inline use ([#12](https://github.com/NewGraphEnvironment/fresh/issues/12))
- Add `frs_watershed_split()` for programmatic sub-basin delineation from break points — snap, delineate, subtract with stable `blk`/`drm` identifiers ([#31](https://github.com/NewGraphEnvironment/fresh/issues/31))
- Security hardening: quote string values in SQL, validate table/column identifiers, clear error on missing PG env vars, gitignore credential files ([#19](https://github.com/NewGraphEnvironment/fresh/issues/19))
- Input type validation on all numeric params
- Add subbasin query vignette with tmap v4 composition
- Fix ref CTE to always query stream network, not target table

Initial release. Stream network-aware spatial operations via direct SQL against fwapg and bcfishpass. See the [function reference](https://newgraphenvironment.github.io/fresh/reference/) for details.
