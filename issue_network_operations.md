## Problem

bcfishpass builds access and habitat models via ~45 SQL scripts that are hardcoded to species-specific tables and the `bcfishpass` schema. The underlying operations are generic network manipulations — splitting, classifying, validating, summarizing — that apply far beyond fish passage.

fresh already wraps fwapg network traversal (`fwa_upstream`, `fwa_downstream`, `fwa_indexpoint`). These new functions extend fresh from querying the network to manipulating it.

## Core Operations

Distilling the bcfishpass `01_access` and `02_habitat_linear` SQL scripts down to their essence:

| What bcfishpass does | What it actually is |
|---|---|
| `barriers_gradient.sql` | Break segments where attribute exceeds threshold |
| `barriers_falls.sql` | Break segments at features from a point table |
| `barriers_anthropogenic.sql` | Break segments at features from a point table |
| `barriers_subsurfaceflow.sql` | Filter/remove segments by attribute value |
| `model_access_*.sql` | Validate break points — drop breaks with upstream evidence |
| `load_streams_access.sql` | Label features by relationship to breaks (which side) |
| `load_habitat_linear_*.sql` | Classify segments by multi-attribute thresholds |
| `load_habitat_known.sql` | Override classification with manual/known values |
| `add_length_upstream.sql` | Summarize upstream of points (length, area, count) |
| `load_crossings_upstream_*.sql` | Summarize upstream of points (length, area, count) |

~45 scripts collapse to **5 abstract operations**.

## Proposed Functions

### `frs_break()`

Break geometry on the network where conditions are met.

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

# Break lake polygon where a tributary enters
frs_break(conn, wsg = "BULK", type = "waterbody",
          blk = 360873822, measure = 1000,
          schema = "working")

# Break watershed at a pour point (absorbs existing frs_watershed_split)
frs_break(conn, wsg = "BULK", type = "watershed",
          blk = 360873822, measure = 1000,
          schema = "working")
```

**Essence:** given criteria and a geometry type, produce break points or split geometries. `type` determines what gets broken — segments, waterbodies, or watersheds.

| type | bcfishpass scripts replaced |
|---|---|
| `"segment"` | `barriers_gradient.sql`, `barriers_falls.sql`, `barriers_subsurfaceflow.sql`, `barriers_anthropogenic.sql`, `barriers_dams.sql`, `barriers_dams_hydro.sql`, `barriers_pscis.sql`, `barriers_user_definite.sql`, `remediations_barriers.sql` |
| `"waterbody"` | (new — e.g. split lake at tributary entry for nutrient modelling) |
| `"watershed"` | absorbs existing `frs_watershed_split()` |

### `frs_break_validate()`

Filter break points against upstream/downstream evidence. Remove breaks where enough upstream features exist to invalidate them.

```r
# Drop breaks with > 5 salmon observations upstream since 1990
frs_break_validate(conn,
                   breaks_table = "working.breaks",
                   evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
                   where = "species_code IN ('CH','CO','PK','SK','CM')
                            AND observation_date >= '1990-01-01'",
                   count_threshold = 5,
                   schema = "working")

# Drop breaks with any water license upstream
frs_break_validate(conn,
                   breaks_table = "working.breaks",
                   evidence_table = "water_licenses",
                   count_threshold = 1,
                   schema = "working")
```

**Essence:** given break points and an evidence table, remove breaks where count of upstream evidence exceeding threshold proves they're not real. The `where` clause filters the evidence table — works for any evidence type.

| bcfishpass scripts replaced |
|---|
| `model_access_bt.sql`, `model_access_ch_cm_co_pk_sk.sql`, `model_access_ct_dv_rb.sql`, `model_access_st.sql`, `model_access_wct.sql` |

### `frs_tag()`

Label features by their spatial relationship to breaks. Given breaks and features, tag each feature by which side of the break it's on.

```r
# Tag stream segments as reachable/unreachable given barriers
frs_tag(conn,
        features = "working.streams",
        by = "working.breaks_validated",
        label = "reachable",
        schema = "working")

# Tag lake pieces after splitting — upstream vs downstream of trib entry
frs_tag(conn,
        features = "working.lake_pieces",
        by = "working.breaks",
        label = "nutrient_zone",
        schema = "working")

# Tag segments by sub-basin after watershed break
frs_tag(conn,
        features = "working.streams",
        by = "working.watershed_breaks",
        label = "subbasin_id",
        schema = "working")
```

**Essence:** the glue between breaking and classifying. Breaks create split points; `frs_tag()` propagates those splits into labels on features. Same operation whether it's barrier reachability, lake nutrient zones, or sub-basin assignment.

| bcfishpass scripts replaced |
|---|
| `load_streams_access.sql`, `streams_model_access.sql` |

### `frs_segment_classify()`

Tag stream segments where multiple attributes fall within specified ranges. Optionally override with known/manual values.

```r
# Classify by gradient + channel width + discharge (spawning thresholds)
frs_segment_classify(conn, wsg = "BULK",
                     ranges = list(
                       gradient = c(0, 0.025),
                       channel_width = c(2, 20),
                       mad_m3s = c(0.5, 100)
                     ),
                     schema = "working")

# Different thresholds for rearing — add temperature when available
frs_segment_classify(conn, wsg = "BULK",
                     ranges = list(
                       gradient = c(0, 0.05),
                       channel_width = c(0.5, 999),
                       temperature = c(8, 16)
                     ),
                     schema = "working")

# With manual overrides — known values win over modelled
frs_segment_classify(conn, wsg = "BULK",
                     ranges = list(
                       gradient = c(0, 0.025),
                       channel_width = c(2, 20)
                     ),
                     overrides = "working.known_habitat",
                     schema = "working")
```

**Essence:** given a named list of attribute ranges, tag segments that fall within all ranges (AND filter). Any column in the source table is a valid attribute — no function signature change when new attributes arrive. `overrides` left-joins manual classifications; manual wins.

| bcfishpass scripts replaced |
|---|
| `load_habitat_linear_bt.sql`, `load_habitat_linear_ch.sql`, `load_habitat_linear_cm.sql`, `load_habitat_linear_co.sql`, `load_habitat_linear_pk.sql`, `load_habitat_linear_sk.sql`, `load_habitat_linear_st.sql`, `load_habitat_linear_wct.sql`, `load_streams_mapping_code.sql`, `horsefly_sk.sql`, `load_habitat_known.sql`, `user_habitat_classification_endpoints.sql` |

### `frs_upstream_sum()`

At given points, compute upstream summaries.

```r
# Length of classified habitat upstream of each crossing
frs_upstream_sum(conn,
                 points_table = "bcfishpass.crossings",
                 target_table = "working.habitat_classified",
                 metrics = c("length_m", "area_ha"),
                 schema = "working")
```

**Essence:** for each point in a table, aggregate attributes from an upstream target table. Generic rollup.

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

## Example Workflow: Lake Nutrient Modelling

Tributary brings P and N into a lake, but the portion of the lake upstream of where the trib enters doesn't receive that load. Need to model lake portions differently.

```r
# 1. Where does the trib enter the lake?
entry <- frs_point_snap(conn, x = -126.5, y = 54.5,
                        blue_line_key = lake_blk)

# 2. Break the lake at that point
frs_break(conn, type = "waterbody",
          blk = entry$blue_line_key,
          measure = entry$downstream_route_measure,
          schema = "working")

# 3. Tag each piece — upstream vs downstream of entry
frs_tag(conn,
        features = "working.lake_pieces",
        by = "working.breaks",
        label = "nutrient_zone",
        schema = "working")
```

## Example Workflow: Fish Habitat Model (bcfishpass replacement)

```r
# 1. Break network at gradient barriers
frs_break(conn, wsg = "BULK", type = "segment",
          attribute = "gradient", threshold = 0.05,
          schema = "working")

# 2. Validate — remove breaks with salmon observations upstream
frs_break_validate(conn,
                   breaks_table = "working.breaks",
                   evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
                   where = "species_code IN ('CH','CO') AND observation_date >= '1990-01-01'",
                   count_threshold = 5,
                   schema = "working")

# 3. Tag segments as reachable/unreachable
frs_tag(conn,
        features = "working.streams",
        by = "working.breaks_validated",
        label = "accessible",
        schema = "working")

# 4. Classify reachable segments by habitat thresholds
frs_segment_classify(conn, wsg = "BULK",
                     ranges = list(
                       gradient = c(0, 0.025),
                       channel_width = c(2, 20),
                       mad_m3s = c(0.5, 100)
                     ),
                     schema = "working")

# 5. Summarize habitat upstream of each crossing
frs_upstream_sum(conn,
                 points_table = "bcfishpass.crossings",
                 target_table = "working.habitat_classified",
                 metrics = c("length_m", "area_ha"),
                 schema = "working")
```

## Summary

| Function | Essence | Scripts replaced |
|---|---|---|
| `frs_break()` | Break geometry at thresholds, features, or points | 9 |
| `frs_break_validate()` | Remove breaks with upstream evidence | 5 |
| `frs_tag()` | Label features by relationship to breaks (which side) | 2 |
| `frs_segment_classify()` | Tag segments by attribute ranges + overrides | 12 |
| `frs_upstream_sum()` | Aggregate upstream of points | 6 |
| **Total** | **5 functions** | **34 scripts** |

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

1. **Species-agnostic** — fish biology lives in parameter values, not function code
2. **CSV-optional** — functions take vectors; CSV loading is a convenience wrapper
3. **Schema-flexible** — write to any schema; default from `options(fresh.schema)`
4. **Server-side by default** — SQL executes in pg, R orchestrates
5. **Composable** — `break → validate → tag → classify → summarize` chains naturally but each step is independently useful
6. **Attribute-agnostic** — `ranges` takes any column name; no signature changes when new attributes (temperature, conductivity, etc.) arrive

## Non-Goals

- Lateral/off-channel habitat (that's flooded)
- Raster processing
- Species-specific wrapper functions (parameter sets can ship as data, not code)

## Open Questions

- Do we need `frs_segment_filter()` as distinct from `frs_segment_classify()`? (subsurface flow removal is filtering, not classifying)
- Should parameter sets (gradient thresholds per species, channel width ranges) ship as package data (`inst/parameters/`) or stay external?
- Local dev db via docker-compose for testing without remote permission constraints?
- `frs_break(type = "waterbody")` cut geometry — perpendicular to lake long axis at entry point? Derived from shoreline angle? User-specified?

Relates to NewGraphEnvironment/bcfishpass
