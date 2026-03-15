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

~45 scripts collapse to **3 abstract operations**.

## Proposed Functions

### `frs_break()`

Break geometry on the network where conditions are met. Optionally validate breaks against evidence in one step.

```r
# Break segments where gradient > 5% (attribute threshold)
frs_break(conn, wsg = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05,
          schema = "working")

# Break segments at features from a point/line table (falls, dams, crossings)
frs_break(conn, wsg = "BULK", type = "segment",
          table = "whse_basemapping.fwa_obstructions_sp",
          schema = "working")

# Break segments at user-defined points (sf or data.frame with blk + measure)
frs_break(conn, wsg = "BULK", type = "segment",
          points = my_points,
          schema = "working")

# Break with evidence — validate inline, drop breaks with > 5 obs upstream
frs_break(conn, wsg = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05,
          evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
          where = "species_code IN ('CH','CO','PK','SK','CM')
                   AND observation_date >= '1990-01-01'",
          count_threshold = 5,
          schema = "working")

# Break lake polygon where a tributary enters
frs_break(conn, wsg = "BULK", type = "waterbody",
          blk = 360873822, measure = 1000,
          schema = "working")

# Break watershed at a pour point (absorbs existing frs_watershed_split)
frs_break(conn, wsg = "BULK", type = "watershed",
          blk = 360873822, measure = 1000,
          schema = "working")
```

**Essence:** given criteria and a geometry type, produce break points or split geometries. `type` determines what gets broken — segments, waterbodies, or watersheds. When `evidence_table` is provided, breaks are validated inline: breaks with upstream evidence exceeding `count_threshold` are removed.

| type | bcfishpass scripts replaced |
|---|---|
| `"segment"` | `barriers_gradient.sql`, `barriers_falls.sql`, `barriers_subsurfaceflow.sql`, `barriers_anthropogenic.sql`, `barriers_dams.sql`, `barriers_dams_hydro.sql`, `barriers_pscis.sql`, `barriers_user_definite.sql`, `remediations_barriers.sql` |
| `"segment"` + evidence | `model_access_bt.sql`, `model_access_ch_cm_co_pk_sk.sql`, `model_access_ct_dv_rb.sql`, `model_access_st.sql`, `model_access_wct.sql` |
| `"waterbody"` | (new — e.g. split lake at tributary entry for nutrient modelling) |
| `"watershed"` | absorbs existing `frs_watershed_split()` |

### `frs_classify()`

Label features by any combination of: attribute ranges, spatial relationship to breaks, and manual overrides. All three inputs are optional but at least one is required. When combined they compose as AND conditions. Pipeable — call multiple times for readable multi-step labelling.

```r
# --- Attribute ranges only ---

# Classify stream segments by gradient + channel width + discharge
frs_classify(conn, wsg = "BULK",
             table = "working.streams",
             ranges = list(
               gradient = c(0, 0.025),
               channel_width = c(2, 20),
               mad_m3s = c(0.5, 100)
             ),
             label = "spawning",
             schema = "working")

# Classify with temperature when available
frs_classify(conn, wsg = "BULK",
             table = "working.streams",
             ranges = list(
               gradient = c(0, 0.05),
               channel_width = c(0.5, 999),
               temperature = c(8, 16)
             ),
             label = "rearing",
             schema = "working")

# Classify lake pieces by area + depth
frs_classify(conn, wsg = "BULK",
             table = "working.lake_pieces",
             ranges = list(
               area_ha = c(1, 1000),
               mean_depth_m = c(2, 50)
             ),
             schema = "working")

# --- Breaks only (reachability tagging) ---

# Label segments by which side of barriers they're on
frs_classify(conn,
             table = "working.streams",
             breaks = "working.breaks",
             label = "accessible",
             schema = "working")

# Label lake pieces after splitting
frs_classify(conn,
             table = "working.lake_pieces",
             breaks = "working.breaks",
             label = "nutrient_zone",
             schema = "working")

# --- Combined ---

# Reachable AND meets habitat thresholds in one call
frs_classify(conn, wsg = "BULK",
             table = "working.streams",
             ranges = list(
               gradient = c(0, 0.025),
               channel_width = c(2, 20)
             ),
             breaks = "working.breaks",
             overrides = "working.known_habitat",
             schema = "working")

# --- Piped for readability ---

conn |>
  frs_classify(table = "working.streams",
               breaks = "working.breaks",
               label = "accessible") |>
  frs_classify(ranges = list(
                 gradient = c(0, 0.025),
                 channel_width = c(2, 20),
                 mad_m3s = c(0.5, 100)),
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
# Habitat length upstream of each crossing (bcfishpass use case)
frs_aggregate(conn,
              points_table = "bcfishpass.crossings",
              target_table = "working.habitat_classified",
              metrics = c("length_m", "area_ha"),
              direction = "upstream",
              schema = "working")

# Distance to ocean — what's between this point and the mouth?
frs_aggregate(conn,
              points_table = "working.my_sites",
              target_table = "working.streams",
              metrics = c("length_m"),
              direction = "downstream",
              schema = "working")

# Lake area upstream of a point
frs_aggregate(conn,
              points_table = "working.my_sites",
              target_table = "working.lakes",
              metrics = c("area_ha"),
              direction = "upstream",
              schema = "working")
```

**Essence:** for each point in a table, traverse the network in the specified direction, find features on that network, and aggregate their attributes. Hides the CTE joining points → network traversal → target table → aggregation. Direction-agnostic, geometry-agnostic. Uses existing `frs_network_upstream()` / `frs_network_downstream()` under the hood.

| bcfishpass scripts replaced |
|---|
| `add_length_upstream.sql`, `load_crossings_upstream_access_01.sql`, `load_crossings_upstream_access_02.sql`, `load_crossings_upstream_habitat_01.sql`, `load_crossings_upstream_habitat_02.sql`, `load_crossings_upstream_habitat_wcrp.sql` |

## Existing fresh functions covering remaining scripts

| fresh function | bcfishpass scripts |
|---|---|
| `frs_fish_obs()` | `load_observations.sql`, `load_qa_observations_naturalbarriers.sql` |
| `frs_stream_fetch()` | `load_streams.sql` |
| `frs_network()` | `load_crossings.sql`, `load_crossings_dnstr_observations.sql`, `load_crossings_upstr_observations.sql`, `load_streams_dnstr_species.sql`, `load_streams_upstr_observations.sql` |
| `frs_dam_fetch()` (new, small) | `load_dams.sql`, `load_falls.sql` |

## Parameter Sets

Parameter sets (gradient thresholds per species, channel width ranges, etc.) ship as package data built from CSV source files.

- **Source:** `data-raw/parameters_habitat_thresholds.csv` — human-readable, editable
- **Build:** script in `data-raw/` reads CSV and saves as package data via `usethis::use_data()`
- **Access:** `fresh::habitat_thresholds$ch_spawning` returns a named list ready for `ranges`
- **Optional:** users can build their own `ranges` lists — no dependency on shipped params

```r
# Use shipped defaults
frs_classify(conn, wsg = "BULK",
             table = "working.streams",
             ranges = fresh::habitat_thresholds$ch_spawning)

# Or build your own
frs_classify(conn, wsg = "BULK",
             table = "working.streams",
             ranges = list(gradient = c(0, 0.03), temperature = c(8, 16)))
```

## Example Workflow: Lake Nutrient Modelling

Tributary brings P and N into a lake, but the portion of the lake upstream of where the trib enters doesn't receive that load. Need to model lake portions differently.

```r
# 1. Where does the trib enter the lake?
entry <- frs_point_snap(conn, x = -126.5, y = 54.5,
                        blue_line_key = lake_blk)

# 2. Break the lake at that point
conn |>
  frs_break(type = "waterbody",
            blk = entry$blue_line_key,
            measure = entry$downstream_route_measure,
            schema = "working") |>

# 3. Classify pieces by relationship to break
  frs_classify(table = "working.lake_pieces",
               breaks = "working.breaks",
               label = "nutrient_zone",
               schema = "working")
```

## Example Workflow: Fish Habitat Model (bcfishpass replacement)

```r
conn |>
  # 1. Break network at gradient barriers, validate against observations
  frs_break(wsg = "BULK", type = "segment",
            attribute = "gradient", threshold = 0.05,
            evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
            where = "species_code IN ('CH','CO') AND observation_date >= '1990-01-01'",
            count_threshold = 5,
            schema = "working") |>

  # 2. Classify: reachable + meets habitat thresholds
  frs_classify(table = "working.streams",
               breaks = "working.breaks",
               label = "accessible") |>
  frs_classify(ranges = fresh::habitat_thresholds$ch_spawning,
               label = "spawning") |>
  frs_classify(overrides = "working.known_habitat",
               label = "spawning_confirmed")

# 3. Summarize habitat upstream of each crossing
frs_aggregate(conn,
              points_table = "bcfishpass.crossings",
              target_table = "working.habitat_classified",
              metrics = c("length_m", "area_ha"),
              direction = "upstream",
              schema = "working")
```

## Summary

| Function | Essence | Geometry | Direction | Scripts replaced |
|---|---|---|---|---|
| `frs_break()` | Break geometry + optional evidence validation | segment, waterbody, watershed | — | 14 |
| `frs_classify()` | Label features by ranges, breaks, overrides (any combo, pipeable) | any | — | 14 |
| `frs_aggregate()` | Summarize along network from points | any | upstream/downstream | 6 |
| **Total** | **3 functions** | | | **34 scripts** |

Remaining scripts covered by existing fresh functions or thin fetch wrappers.

## Output Strategy

All functions write results server-side to `{schema}.{table}` — no data crosses the wire by default.

```r
# Default: write to pg (zero R memory)
frs_break(conn, wsg = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05, schema = "working")

# Return sf object for inspection (small queries)
result <- frs_break(conn, wsg = "BULK", type = "segment",
                    attribute = "gradient", threshold = 0.05, collect = TRUE)

# Export to parquet after server-side compute
frs_break(conn, wsg = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05, schema = "working",
          parquet = "breaks_gradient_BULK.parquet")
```

Default schema set once per session:

```r
options(fresh.schema = "working")
```

## Design Principles

1. **Geometry-agnostic** — functions work on segments, lakes, wetlands, watersheds
2. **Direction-agnostic** — aggregate upstream or downstream with a param
3. **Attribute-agnostic** — `ranges` takes any column name; no signature changes when new attributes (temperature, conductivity, etc.) arrive
4. **Species-agnostic** — fish biology lives in parameter values, not function code
5. **CSV-optional** — functions take vectors; CSV loading is a convenience wrapper
6. **Schema-flexible** — write to any schema; default from `options(fresh.schema)`
7. **Server-side by default** — SQL executes in pg, R orchestrates
8. **Composable** — `break → classify → aggregate` chains naturally; `frs_classify()` is pipeable for multi-step labelling

## Non-Goals

- Lateral/off-channel habitat (that's flooded)
- Raster processing
- Species-specific wrapper functions (parameter sets ship as data, not code)

## Open Questions

- Do we need `frs_filter()` as distinct from `frs_classify()`? (subsurface flow removal is filtering, not classifying)
- Local dev db via docker-compose for testing without remote permission constraints?
- `frs_break(type = "waterbody")` cut geometry — perpendicular to lake long axis at entry point? Derived from shoreline angle? User-specified?

Relates to NewGraphEnvironment/bcfishpass
