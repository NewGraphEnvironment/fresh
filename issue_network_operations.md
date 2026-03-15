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

## Non-Goals

- Lateral/off-channel habitat (that's flooded)
- Raster processing
- Species-specific wrapper functions (parameter sets drive the pipeline, not code)

## Open Questions

- Do we need `frs_filter()` as distinct from `frs_classify()`? (subsurface flow removal is filtering, not classifying)
- Local dev db via docker-compose for testing without remote permission constraints?
- `frs_break(type = "waterbody")` cut geometry — perpendicular to lake long axis at entry point? Derived from shoreline angle? User-specified?

Relates to NewGraphEnvironment/bcfishpass
