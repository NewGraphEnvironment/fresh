## Problem

bcfishpass builds access and habitat models via ~45 SQL scripts that are hardcoded to species-specific tables and the `bcfishpass` schema. The underlying operations are generic network manipulations — splitting, classifying, validating, summarizing — that apply far beyond fish passage.

fresh already wraps fwapg network traversal (`fwa_upstream`, `fwa_downstream`, `fwa_indexpoint`). These new functions extend fresh from querying the network to manipulating it.

## Core Operations

Distilling the bcfishpass `01_access` and `02_habitat_linear` SQL scripts down to their essence:

| What bcfishpass does | What it actually is |
|---|---|
| `barriers_gradient.sql` | Break geometry where attribute exceeds threshold |
| `barriers_falls.sql` | Break geometry at features from a point table |
| `barriers_anthropogenic.sql` | Break geometry at features from a point table |
| `barriers_subsurfaceflow.sql` | Filter/remove features by attribute value |
| `model_access_*.sql` | Break with evidence — drop breaks with upstream observations |
| `load_streams_access.sql` | Classify features by relationship to breaks |
| `load_habitat_linear_*.sql` | Classify features by multi-attribute thresholds |
| `load_habitat_known.sql` | Classify with manual overrides |
| `add_length_upstream.sql` | Aggregate along network from points |
| `load_crossings_upstream_*.sql` | Aggregate along network from points |

~45 scripts collapse to **4 abstract operations**.

## AOI — Flexible Spatial Partitioning

Watershed group codes are the default partition (bcfishpass convention), but the `aoi` parameter accepts anything that resolves to network features:

| `aoi` input | What happens | Use case |
|---|---|---|
| `"BULK"` | Filter by `watershed_group_code` | Standard bcfishpass-style run |
| `c("BULK", "MORR", "ELKR")` | Multiple WSGs | Regional build |
| `sf` polygon | Intersect with stream network | Custom study area, Neexdzii Kwa-style watershed from `fwa_watershedatmeasure` |
| `list(blk = 360873822, measure = 1000)` | Build watershed via `fwa_watershedatmeasure`, then intersect | Single-point watershed delineation as AOI |
| `NULL` (default) | No spatial filter — whole province | Full build (rare) |

Resolution logic (internal):
1. Character vector → `WHERE watershed_group_code IN (...)`
2. sf polygon → upload as temp table, `ST_Intersects` join
3. blk+measure list → call `fwa_watershedatmeasure()` first to get the polygon, then treat as sf
4. NULL → no spatial predicate

The key insight: WSGs are just the coarsest convenient partition. Anything smaller works — a `fwa_watershedatmeasure` polygon, a hand-drawn AOI, a sub-basin from breaks. The functions don't care about the partition semantics, only the spatial extent.

```r
# WSG — standard
frs_break(conn, aoi = "BULK", ...)

# Multiple WSGs
frs_break(conn, aoi = c("BULK", "MORR"), ...)

# Custom watershed (Neexdzii Kwa style)
neexdzii <- frs_db_query(conn,
  "SELECT * FROM fwa_watershedatmeasure(360873822, 1000)")
frs_break(conn, aoi = neexdzii, ...)

# Shorthand for the above
frs_break(conn, aoi = list(blk = 360873822, measure = 1000), ...)

# Sub-basin from breaks package
sub <- breaks::brk_delineate(conn, blk = 360873822, measure = 1000)
frs_break(conn, aoi = sub, ...)
```

## Proposed Functions

### `frs_break()`

Break geometry on the network where conditions are met. Optionally validate breaks against evidence in one step.

```r
# Break segments where gradient > 5%
frs_break(conn, aoi = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05,
          schema = "working")

# Break segments at features from a table
frs_break(conn, aoi = "BULK", type = "segment",
          table = "whse_basemapping.fwa_obstructions_sp",
          schema = "working")

# Break segments at user-defined points
frs_break(conn, aoi = "BULK", type = "segment",
          points = my_points, schema = "working")

# Break with evidence — validate inline
frs_break(conn, aoi = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05,
          evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
          where = "species_code IN ('CH','CO','PK','SK','CM')
                   AND observation_date >= '1990-01-01'",
          count_threshold = 5, schema = "working")

# Custom watershed AOI — Neexdzii Kwa
frs_break(conn, aoi = list(blk = 360873822, measure = 1000),
          type = "segment", attribute = "gradient", threshold = 0.05,
          schema = "working")

# sf polygon AOI
frs_break(conn, aoi = my_study_area, type = "segment",
          attribute = "gradient", threshold = 0.05,
          schema = "working")

# Break lake polygon where a tributary enters
frs_break(conn, aoi = "BULK", type = "waterbody",
          blk = 360873822, measure = 1000, schema = "working")

# Break watershed at a pour point
frs_break(conn, aoi = "BULK", type = "watershed",
          blk = 360873822, measure = 1000, schema = "working")
```

**Essence:** given criteria and a geometry type, produce break points or split geometries. `type` determines what gets broken — segments, waterbodies, or watersheds. `aoi` determines spatial extent — WSG codes, sf polygons, or blk+measure specs. When `evidence_table` is provided, breaks are validated inline: breaks with upstream evidence exceeding `count_threshold` are removed.

| type | bcfishpass scripts replaced |
|---|---|
| `"segment"` | `barriers_gradient.sql`, `barriers_falls.sql`, `barriers_subsurfaceflow.sql`, `barriers_anthropogenic.sql`, `barriers_dams.sql`, `barriers_dams_hydro.sql`, `barriers_pscis.sql`, `barriers_user_definite.sql`, `remediations_barriers.sql` |
| `"segment"` + evidence | `model_access_bt.sql`, `model_access_ch_cm_co_pk_sk.sql`, `model_access_ct_dv_rb.sql`, `model_access_st.sql`, `model_access_wct.sql` |
| `"waterbody"` | (new — e.g. split lake at tributary entry for nutrient modelling) |
| `"watershed"` | absorbs existing `frs_watershed_split()` |

### `frs_classify()`

Label features by any combination of: attribute ranges, spatial relationship to breaks, and manual overrides. All three inputs optional (at least one required). Pipeable for multi-step labelling.

```r
# --- Attribute ranges only ---
frs_classify(conn, aoi = "BULK",
             table = "working.streams",
             ranges = list(gradient = c(0, 0.025),
                           channel_width = c(2, 20),
                           mad_m3s = c(0.5, 100)),
             label = "spawning", schema = "working")

# --- Breaks only (reachability) ---
frs_classify(conn,
             table = "working.streams",
             breaks = "working.breaks",
             label = "accessible", schema = "working")

# --- Combined, custom AOI ---
frs_classify(conn, aoi = list(blk = 360873822, measure = 1000),
             table = "working.streams",
             ranges = list(gradient = c(0, 0.025), channel_width = c(2, 20)),
             breaks = "working.breaks",
             overrides = "working.known_habitat",
             schema = "working")

# --- Piped for readability ---
conn |>
  frs_classify(table = "working.streams",
               breaks = "working.breaks",
               label = "accessible") |>
  frs_classify(ranges = fresh::habitat_thresholds$ch_spawning,
               label = "spawning") |>
  frs_classify(overrides = "working.known_habitat",
               label = "spawning_confirmed")
```

**Essence:** unified labelling function. `ranges` classifies by attribute values. `breaks` classifies by network position relative to break points. `overrides` applies manual corrections. Any column in the source table is a valid attribute — no function signature change when new attributes arrive. Geometry-agnostic: works on segments, lakes, wetlands, watershed pieces.

| Input | bcfishpass scripts replaced |
|---|---|
| `breaks` | `load_streams_access.sql`, `streams_model_access.sql` |
| `ranges` | `load_habitat_linear_bt.sql`, `load_habitat_linear_ch.sql`, `load_habitat_linear_cm.sql`, `load_habitat_linear_co.sql`, `load_habitat_linear_pk.sql`, `load_habitat_linear_sk.sql`, `load_habitat_linear_st.sql`, `load_habitat_linear_wct.sql`, `load_streams_mapping_code.sql`, `horsefly_sk.sql` |
| `overrides` | `load_habitat_known.sql`, `user_habitat_classification_endpoints.sql` |

### `frs_aggregate()`

At given points, summarize features along the network in either direction. Wraps the network traversal + spatial join + aggregation SQL that would otherwise be ~30-40 lines per query. The network nuance — `fwa_upstream()` / `fwa_downstream()` with ltree — is the thing native SQL can't do without the fwapg functions.

```r
# Habitat upstream of crossings
frs_aggregate(conn,
              points_table = "bcfishpass.crossings",
              target_table = "working.habitat_classified",
              metrics = c("length_m", "area_ha"),
              direction = "upstream", schema = "working")

# Distance to ocean
frs_aggregate(conn,
              points_table = "working.my_sites",
              target_table = "working.streams",
              metrics = c("length_m"),
              direction = "downstream", schema = "working")

# Lake area upstream of a point
frs_aggregate(conn,
              points_table = "working.my_sites",
              target_table = "working.lakes",
              metrics = c("area_ha"),
              direction = "upstream", schema = "working")
```

**Essence:** for each point in a table, traverse the network in the specified direction, find features on that network, and aggregate their attributes. Direction-agnostic, geometry-agnostic. Uses existing `frs_network_upstream()` / `frs_network_downstream()` under the hood.

| bcfishpass scripts replaced |
|---|
| `add_length_upstream.sql`, `load_crossings_upstream_access_01.sql`, `load_crossings_upstream_access_02.sql`, `load_crossings_upstream_habitat_01.sql`, `load_crossings_upstream_habitat_02.sql`, `load_crossings_upstream_habitat_wcrp.sql` |

### `frs_params()`

Load parameter sets from any source — bcfishpass tables in pg (default), a custom pg table, or a local CSV. Returns a list ready for `purrr::walk()` over `frs_break()` / `frs_classify()`.

```r
# Default: bcfishpass parameter tables already in pg
params <- frs_params(conn)

# Custom: your own table with experimental thresholds
params <- frs_params(conn, table = "working.my_thresholds")

# Offline/local: CSV shipped with package or your own
params <- frs_params(csv = system.file("parameters/habitat_thresholds.csv", package = "fresh"))
params <- frs_params(csv = "my_experimental_thresholds.csv")
```

**Essence:** normalize parameter sources into a consistent list. Decouples the pipeline from any single parameter source. The bcfishpass pg tables are the default because that's where the authoritative params live. Local CSV enables rapid experimentation without touching the database.

## Parameter-Driven Pipeline

The CSV (or pg table) has one row per species with all thresholds. `purrr::walk()` iterates the whole pipeline per species:

```r
params <- frs_params(conn)  # or frs_params(csv = "my_experimental.csv")
aoi <- "BULK"  # or c("BULK", "MORR"), or an sf polygon, or list(blk, measure)

params |>
  purrr::walk(~{
    conn |>
      frs_break(aoi = aoi, type = "segment",
                attribute = "gradient", threshold = .x$gradient_max,
                evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
                where = glue::glue("species_code IN ({.x$species_codes})"),
                count_threshold = .x$obs_threshold,
                schema = "working") |>
      frs_classify(table = "working.streams",
                   breaks = "working.breaks",
                   ranges = .x$ranges,
                   label = .x$species)
  })
```

### Scenario Testing

Edit a local CSV, run on any AOI, compare outputs. No database changes needed to test new parameter combinations.

```r
# Experiment: shift all spawning gradient mins from 0 to 0.0036
# 1. Copy CSV, edit gradient_min column
# 2. Run both scenarios on target AOIs

# AOI can be WSGs, a custom watershed, or any sf polygon
aoi <- c("BULK", "MORR", "ELKR")
# aoi <- list(blk = 360873822, measure = 1000)  # Neexdzii Kwa
# aoi <- my_study_area_sf                        # any sf polygon

baseline <- frs_params(conn)  # current bcfishpass params
experiment <- frs_params(csv = "experiment_gradient_min_0036.csv")

# Run baseline
baseline |> purrr::walk(\(p) {
  conn |>
    frs_break(aoi = aoi, type = "segment",
              attribute = "gradient", threshold = p$gradient_max,
              schema = "working_baseline") |>
    frs_classify(table = "working_baseline.streams",
                 ranges = p$ranges, label = p$species)
})

# Run experiment
experiment |> purrr::walk(\(p) {
  conn |>
    frs_break(aoi = aoi, type = "segment",
              attribute = "gradient", threshold = p$gradient_max,
              schema = "working_experiment") |>
    frs_classify(table = "working_experiment.streams",
                 ranges = p$ranges, label = p$species)
})

# 3. Compare: summary tables of lengths/areas
baseline_summary <- frs_aggregate(conn,
    points_table = "bcfishpass.crossings",
    target_table = "working_baseline.habitat_classified",
    metrics = c("length_m", "area_ha"),
    direction = "upstream", schema = "working_baseline")

experiment_summary <- frs_aggregate(conn,
    points_table = "bcfishpass.crossings",
    target_table = "working_experiment.habitat_classified",
    metrics = c("length_m", "area_ha"),
    direction = "upstream", schema = "working_experiment")

# 4. Compare and visualize
dplyr::left_join(baseline_summary, experiment_summary,
                 by = "crossing_id", suffix = c("_baseline", "_experiment"))
```

Schema separation (`working_baseline` vs `working_experiment`) keeps results side-by-side for comparison without overwriting anything.

## Existing fresh functions covering remaining scripts

| fresh function | bcfishpass scripts |
|---|---|
| `frs_fish_obs()` | `load_observations.sql`, `load_qa_observations_naturalbarriers.sql` |
| `frs_stream_fetch()` | `load_streams.sql` |
| `frs_network()` | `load_crossings.sql`, `load_crossings_dnstr_observations.sql`, `load_crossings_upstr_observations.sql`, `load_streams_dnstr_species.sql`, `load_streams_upstr_observations.sql` |
| `frs_dam_fetch()` (new, small) | `load_dams.sql`, `load_falls.sql` |

## Example Workflow: Lake Nutrient Modelling

Tributary brings P and N into a lake, but the portion of the lake upstream of where the trib enters doesn't receive that load. Need to model lake portions differently.

```r
entry <- frs_point_snap(conn, x = -126.5, y = 54.5,
                        blue_line_key = lake_blk)

conn |>
  frs_break(type = "waterbody",
            blk = entry$blue_line_key,
            measure = entry$downstream_route_measure,
            schema = "working") |>
  frs_classify(table = "working.lake_pieces",
               breaks = "working.breaks",
               label = "nutrient_zone", schema = "working")
```

## Example Workflow: Fish Habitat Model (bcfishpass replacement)

```r
params <- frs_params(conn)
aoi <- "BULK"  # or any valid aoi spec

params |>
  purrr::walk(~{
    conn |>
      frs_break(aoi = aoi, type = "segment",
                attribute = "gradient", threshold = .x$gradient_max,
                evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
                where = glue::glue("species_code IN ({.x$species_codes})"),
                count_threshold = .x$obs_threshold,
                schema = "working") |>
      frs_classify(table = "working.streams",
                   breaks = "working.breaks",
                   label = "accessible") |>
      frs_classify(ranges = .x$ranges,
                   label = paste0(.x$species, "_spawning")) |>
      frs_classify(overrides = "working.known_habitat",
                   label = paste0(.x$species, "_confirmed"))
  })

frs_aggregate(conn,
              points_table = "bcfishpass.crossings",
              target_table = "working.habitat_classified",
              metrics = c("length_m", "area_ha"),
              direction = "upstream", schema = "working")
```

## Summary

| Function | Essence | Scripts replaced |
|---|---|---|
| `frs_break()` | Break geometry + optional evidence validation | 14 |
| `frs_classify()` | Label by ranges, breaks, overrides (any combo, pipeable) | 14 |
| `frs_aggregate()` | Summarize along network from points | 6 |
| `frs_params()` | Load params from pg table, custom table, or CSV | — |
| **Total** | **4 functions** | **34 scripts** |

Remaining scripts covered by existing fresh functions or thin fetch wrappers.

## Output Strategy

All functions write results server-side to `{schema}.{table}` — no data crosses the wire by default.

```r
# Default: write to pg (zero R memory)
frs_break(conn, aoi = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05, schema = "working")

# Return sf object for inspection (small queries)
result <- frs_break(conn, aoi = "BULK", type = "segment",
                    attribute = "gradient", threshold = 0.05, collect = TRUE)

# Export to parquet after server-side compute
frs_break(conn, aoi = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05, schema = "working",
          parquet = "breaks_gradient_BULK.parquet")
```

Default schema set once per session:

```r
options(fresh.schema = "working")
```

## Design Principles

1. **AOI-agnostic** — WSG codes, sf polygons, blk+measure watersheds, or NULL for full extent; functions don't care about the partition semantics
2. **Geometry-agnostic** — functions work on segments, lakes, wetlands, watersheds
3. **Direction-agnostic** — aggregate upstream or downstream with a param
4. **Attribute-agnostic** — `ranges` takes any column name; no signature changes when new attributes (temperature, conductivity, etc.) arrive
5. **Species-agnostic** — fish biology lives in parameter values, not function code
6. **Parameter-source-agnostic** — pg table, custom table, or local CSV through `frs_params()`
7. **Schema-flexible** — write to any schema; use separate schemas for A/B comparison
7. **Server-side by default** — SQL executes in pg, R orchestrates
8. **Composable** — `break → classify → aggregate` chains naturally; `frs_classify()` is pipeable for multi-step labelling

## Portability — What Lives Where

Three layers with different portability profiles:

```
┌─────────────────────────────────────────────────────────┐
│  Layer 3: Operations (fresh)                            │
│  frs_break(), frs_classify(), frs_aggregate()           │
│  Generates SQL. Mostly generic.                         │
├─────────────────────────────────────────────────────────┤
│  Layer 2: Data (fwapg load)                             │
│  FWA streams, watersheds, ltree codes, geometry         │
│  ETL scripts. Source → target db.                       │
├─────────────────────────────────────────────────────────┤
│  Layer 1: Network topology functions (fwapg functions)  │
│  fwa_upstream(), fwa_downstream(),                      │
│  fwa_watershedatmeasure(), fwa_indexpoint()              │
│  PL/pgSQL + ltree + PostGIS. pg-native.                 │
└─────────────────────────────────────────────────────────┘
```

### What's pg-native and why

| Capability | pg feature | Why it can't move easily |
|---|---|---|
| Upstream/downstream check | ltree `<@` operator + custom `fwa_upstream()` | Hierarchical path comparison with measure logic. No standard SQL equivalent — recursive CTEs are orders of magnitude slower on a 1M+ segment network |
| Snap point to stream | PostGIS `<->` KNN + `ST_LineLocatePoint` | Spatial index-driven nearest-neighbour. DuckDB spatial has `ST_Distance` but no KNN index operator |
| Watershed delineation | `fwa_watershedatmeasure()` | PL/pgSQL procedure assembling watershed polygon from pre-computed fundamental watersheds + partial area at the pour point. ~50 lines of spatial SQL |
| Geometry operations | PostGIS `ST_Transform`, `ST_Intersects`, `ST_MakeEnvelope` | DuckDB spatial covers some of these but not all, and no SRID transform |

### What's already portable

| Operation | pg-native parts | Generic SQL parts |
|---|---|---|
| `frs_classify(ranges = ...)` | None | `WHERE col BETWEEN a AND b`, `UPDATE SET label` |
| `frs_classify(breaks = ...)` | Network position check uses `fwa_upstream()` | The labelling itself is a join + update |
| `frs_classify(overrides = ...)` | None | Join + update |
| `frs_break(attribute + threshold)` | None | `WHERE gradient > 0.05` |
| `frs_break(evidence_table)` | `fwa_upstream()` for counting obs upstream | The break/keep decision is generic |
| `frs_aggregate()` | `fwa_upstream()`/`fwa_downstream()` for traversal | `SUM(length_m)`, `SUM(area_ha)` |
| `frs_params()` | None | Read a table or CSV, return a list |

**Pattern:** network traversal is the only hard pg dependency. Everything downstream of "which features are on this network" is standard SQL.

### Separation strategy

The portability question leads to a deeper one: **fwapg's traversal logic isn't FWA-specific.** ltree codes, upstream/downstream checks, snap-to-nearest, measure derivation — these work on any directed linear network. The FWA is just one network that happens to have the codes pre-computed.

A LiDAR-derived channel network has the same structure: connected line segments with direction (downhill), branching, and confluences. If you assign ltree codes to it, you get the same traversal speed. Then fresh's `frs_break()`, `frs_classify()`, `frs_aggregate()` work unchanged — they don't know or care where the network came from.

This suggests four packages, not three:

| Package | Role | What it needs |
|---|---|---|
| **spyda** | Network topology engine. Takes any linear network, builds ltree codes + topology, installs traversal functions (`spd_upstream()`, `spd_downstream()`, `spd_snap()`, `spd_watershed()`). Source-agnostic — FWA, LiDAR channels, any jurisdiction's hydro data | pg + ltree + PostGIS (for now). The functions ARE the pg extension. Future: could target duckdb if ltree-equivalent emerges |
| **fwapg** (becomes thin) | FWA-specific data loader. Downloads BC FWA from BCGW, calls spyda to build the topology. Knows about FWA schema, watershed group codes, BC Albers. No traversal functions of its own — delegates to spyda | pg for target. spyda for topology |
| **fresh** | Operations layer. `frs_break()`, `frs_classify()`, `frs_aggregate()`, `frs_params()`. Generates SQL, dispatches to a connection. Network-source-agnostic — works against any spyda-built network | conn (pg today, duckdb for portable ops later) |
| **bcfishpass** (becomes thin) | Fish-passage-specific params, species tables, crossing logic. Calls fresh with BC-specific parameter sets. No SQL of its own | fresh + fwapg-built network |

```
                    ┌──────────────┐
                    │  bcfishpass   │  species params, crossing logic
                    └──────┬───────┘
                           │ calls
                    ┌──────▼───────┐
                    │    fresh     │  break, classify, aggregate
                    └──────┬───────┘
                           │ generates SQL against
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼───┐  ┌────▼─────┐  ┌──▼──────────┐
       │  fwapg   │  │  LiDAR   │  │  other net  │  data loaders
       │  (FWA)   │  │  loader  │  │  loader     │
       └──────┬───┘  └────┬─────┘  └──┬──────────┘
              │            │           │
              └────────────┼───────────┘
                           │ all call
                    ┌──────▼───────┐
                    │    spyda    │  topology engine
                    │  ltree codes │
                    │  traversal   │
                    │  snap/locate │
                    └──────────────┘
```

### What spyda does

Given any set of connected linestrings with direction:

1. **Build topology** — identify confluences, headwaters, outlets. Determine parent-child relationships between branches
2. **Assign ltree codes** — compute `wscode_ltree` and `localcode_ltree` for every segment. This is the key step that makes traversal O(1) instead of recursive
3. **Compute measures** — `downstream_route_measure` and `upstream_route_measure` along each route. Enables point-level precision on the network
4. **Install functions** — `spd_upstream()`, `spd_downstream()`, `spd_snap()`, `spd_locate()`, `spd_watershed()` into the target database
5. **Build indexes** — GiST on geometry, ltree indexes on codes

```r
# === FWA network (existing workflow) ===
# fwapg handles the FWA-specific ETL, spyda handles topology
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "mydb")
fwapg::fwa_load(conn, source = "bcgw")  # download + load FWA tables
# topology already exists in FWA data — spyda verifies/indexes

# === LiDAR-derived network (new workflow) ===
# Extract channels from DEM, load into pg, spyda builds topology
channels <- whitebox::wbt_extract_streams(dem, threshold = 100)
spyda::spd_load(conn, network = channels, schema = "lidar_net")
spyda::spd_build_topology(conn, schema = "lidar_net")
# now spd_upstream(), spd_downstream() work on this network

# === fresh doesn't care which network ===
# Same operations, different network source
frs_break(conn, aoi = my_study_area, type = "segment",
          attribute = "gradient", threshold = 0.05,
          network_schema = "lidar_net",  # or "whse_basemapping" for FWA
          schema = "working")

frs_point_snap(conn, x = -126.5, y = 54.5,
               network_schema = "lidar_net")
```

### The ltree assignment problem

For FWA, ltree codes are pre-computed by the province — every stream segment already has `wscode_ltree` and `localcode_ltree`. spyda just loads and indexes them.

For a LiDAR network, spyda needs to **compute** the codes. This is the core algorithm:

1. Find the outlet(s) — segments with no downstream neighbour
2. Walk upstream from each outlet, assigning hierarchical codes
3. At each confluence, the mainstem continues (by drainage area, length, or user choice), and the tributary gets a new branch code
4. Measures accumulate upstream along each route

This is a one-time cost per network. Once codes exist, traversal is the same O(1) ltree check regardless of source.

The mainstem-vs-tributary decision at confluences is where domain knowledge enters. FWA uses a pre-determined hierarchy. For LiDAR channels, options:
- **Drainage area** (largest upstream area = mainstem) — most hydrologically defensible
- **Channel length** (longest path = mainstem) — Strahler-adjacent
- **User-specified** — provide a table of confluence decisions

### What this means for the ecosystem

```
Pipeline with FWA:
  fwapg (load FWA) → spyda (verify topology) → fresh (operations) → bcfishpass (fish params)

Pipeline with LiDAR:
  whitebox (extract channels) → spyda (build topology) → fresh (operations) → your params

Pipeline with other jurisdiction:
  custom loader → spyda (build topology) → fresh (operations) → your params
```

fresh becomes network-source-agnostic. spyda is the thing that makes any network traversable. fwapg is just one data loader among many.

### Snap fish observations to LiDAR network

This is the concrete use case. You have:
- LiDAR-derived channels (higher resolution than FWA in headwaters)
- Fish observation points (from field GPS or bcfishobs)
- Barriers identified in the field

```r
# Build LiDAR network topology
spyda::spd_load(conn, network = lidar_channels, schema = "lidar")
spyda::spd_build_topology(conn, schema = "lidar")

# Snap fish obs to the LiDAR network (not FWA)
snapped <- frs_point_snap(conn, points = fish_obs,
                          network_schema = "lidar")

# Break at field-identified barriers
frs_break(conn, aoi = study_area, type = "segment",
          points = field_barriers,
          network_schema = "lidar", schema = "working")

# Classify habitat using the same parameter sets
frs_classify(conn, table = "working.streams",
             breaks = "working.breaks",
             ranges = list(gradient = c(0, 0.025), channel_width = c(1, 10)),
             label = "spawning", schema = "working")

# How much habitat upstream of each barrier?
frs_aggregate(conn,
              points_table = "working.breaks",
              target_table = "working.streams",
              metrics = c("length_m"),
              direction = "upstream",
              network_schema = "lidar", schema = "working")
```

Same functions, same API, different network. The only new parameter is `network_schema` to tell fresh which spyda-built network to query against.

The key question: **should fresh generate SQL that's backend-aware?**

Option A — **pg only, keep it simple.** fresh generates pg SQL, full stop. The ltree + PostGIS dependency is a feature, not a bug — it's what makes network queries fast. Anyone who wants to use fresh needs pg with fwapg. This is the current reality and it works.

Option B — **Backend-aware dispatch.** fresh detects the connection type and generates appropriate SQL. Network traversal always goes to pg (because ltree). But `frs_classify(ranges = ...)` against a local parquet/duckdb? That's just `WHERE col BETWEEN a AND b` — no reason it needs pg. This enables:

```r
# Heavy network ops on pg
conn_pg <- frs_db_conn()
frs_break(conn_pg, aoi = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05,
          schema = "working")

# Pull results to local duckdb for fast classify/aggregate iteration
conn_duck <- DBI::dbConnect(duckdb::duckdb())
frs_classify(conn_duck, table = "streams",
             ranges = list(gradient = c(0, 0.025)),
             label = "spawning")
```

Option C — **Parquet as the interchange format.** Network traversal runs on pg, writes results to parquet. Everything after that — classify, aggregate, compare scenarios — runs locally against parquet via duckdb/arrow. No pg needed for the iteration loop:

```r
# One-time: extract network results from pg to parquet
frs_break(conn_pg, aoi = "BULK", ..., parquet = "breaks.parquet")
frs_network(conn_pg, ..., parquet = "network.parquet")

# Iterate locally — no pg connection needed
conn_duck <- DBI::dbConnect(duckdb::duckdb())
duckdb::duckdb_register(conn_duck, "streams", arrow::read_parquet("network.parquet"))

# Classify, re-classify, experiment — all local, fast
frs_classify(conn_duck, table = "streams",
             ranges = list(gradient = c(0, 0.025)),
             label = "spawning")
```

This is interesting for the scenario testing workflow — extract once, iterate many times without network round-trips.

### fwapg-load as its own package

The load scripts (`fwapg/load/`) are pure ETL — download BC FWA data, compute ltree codes, build indexes. They're independent of the functions and independent of any consuming application. A separate package makes sense:

```r
# Build a fresh fwapg database from scratch
fwapg.load::fwl_create(conn, source = "bcgw")  # or "geopackage", "parquet"

# Update specific tables
fwapg.load::fwl_update(conn, tables = c("streams", "watersheds"))

# Build on a different pg instance (empty db → fully loaded)
conn_local <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwa_dev")
fwapg.load::fwl_create(conn_local, source = "bcgw")
fwapg.load::fwl_install_functions(conn_local)  # install fwa_upstream() etc.
```

This would let anyone stand up their own fwapg instance — local docker, cloud pg, CI test db — without needing access to the shared instance. The functions travel with the db because they're installed into it.

### What this means for fresh

fresh stays as the R interface — it generates SQL and dispatches it. The question is whether `conn` is always pg, or whether fresh learns to talk to multiple backends for the operations that don't need ltree.

For now (v0.1.x): pg only. The design already separates concerns cleanly enough that adding duckdb dispatch later doesn't require API changes — `frs_classify(conn, ...)` works regardless of what `conn` is.

## Non-Goals

- Lateral/off-channel habitat (that's flooded)
- Raster processing
- Species-specific wrapper functions (parameter sets drive the pipeline, not code)

## Open Questions

- Do we need `frs_filter()` as distinct from `frs_classify()`? (subsurface flow removal is filtering, not classifying)
- Local dev db via docker-compose for testing without remote permission constraints?
- `frs_break(type = "waterbody")` cut geometry — perpendicular to lake long axis at entry point? Derived from shoreline angle? User-specified?
- fwapg as thin FWA loader — when? Blocks on having spyda's topology builder working first
- spyda's ltree assignment algorithm — mainstem selection at confluences (drainage area vs length vs user-specified)
- spyda scope: does it also handle waterbody topology (lakes on the network) or just linestrings?
- `network_schema` param on fresh functions — clean enough? Or does fresh hold a "network registry" so you can name them?
- Backend dispatch (duckdb for classify/aggregate) — design for it now (conn-agnostic signatures), build it later

Relates to NewGraphEnvironment/bcfishpass
