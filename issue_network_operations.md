## Problem

bcfishpass builds access and habitat models via ~45 SQL scripts that are hardcoded to species-specific tables and the `bcfishpass` schema. The underlying operations are generic network manipulations — splitting, classifying, validating, summarizing — that apply far beyond fish passage.

fresh already wraps fwapg network traversal (`fwa_upstream`, `fwa_downstream`, `fwa_indexpoint`). These new functions extend fresh from querying the network to manipulating it.

## Core Operations

Distilling the bcfishpass `01_access` and `02_habitat_linear` SQL scripts down to their essence:

| What bcfishpass does | What it actually is |
|---|---|
| `barriers_gradient.sql` | Split network where segment attribute exceeds threshold |
| `barriers_falls.sql` | Split network at features from a point table |
| `barriers_anthropogenic.sql` | Split network at features from a point table |
| `barriers_subsurfaceflow.sql` | Filter/remove segments by attribute value |
| `model_access_*.sql` | Validate break points — drop breaks with upstream evidence |
| `load_streams_access.sql` | Tag segments as reachable/unreachable given break points |
| `load_habitat_linear_*.sql` | Classify segments by multi-attribute thresholds |
| `load_habitat_known.sql` | Override classification with manual/known values |
| `add_length_upstream.sql` | Summarize upstream of points (length, area, count) |
| `load_crossings_upstream_*.sql` | Summarize upstream of points (length, area, count) |

~45 scripts collapse to **5-6 abstract operations**.

## Proposed Functions

### `frs_network_break()`

Place break points on the network where conditions are met.

```r
# Split where gradient > 5% (attribute threshold on stream segments)
frs_network_break(conn, wsg = "BULK",
                  attribute = "gradient", threshold = 0.05,
                  schema = "working")

# Split at features from a point/line table (falls, dams, crossings)
frs_network_break(conn, wsg = "BULK",
                  table = "whse_basemapping.fwa_obstructions_sp",
                  schema = "working")

# Split at user-defined points (sf or data.frame with blk + measure)
frs_network_break(conn, wsg = "BULK", points = my_points,
                  schema = "working")
```

**Essence:** given criteria, produce a table of break points (blk, measure, break_type) and write to pg.

### `frs_break_validate()`

Filter break points against upstream/downstream evidence. Remove breaks that don't matter.

```r
# Drop breaks with > 5 observations upstream since 1990
frs_break_validate(conn, wsg = "BULK",
                   breaks_table = "working.breaks",
                   evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
                   evidence_col = "species_code",
                   evidence_values = c("CH", "CO", "PK", "SK", "CM"),
                   obs_year_min = 1990,
                   obs_count_threshold = 5,
                   schema = "working")
```

**Essence:** given break points and an evidence table, remove breaks where evidence upstream proves they're not real barriers. Returns validated breaks.

### `frs_segment_classify()`

Tag stream segments meeting multi-attribute threshold criteria.

```r
# Classify by gradient + channel width ranges (spawning habitat thresholds)
frs_segment_classify(conn, wsg = "BULK",
                     gradient_max = 0.025,
                     channel_width = c(2, 20),  # min, max
                     mad_m3s = c(0.5, 100),     # min, max
                     schema = "working")

# Different thresholds for rearing
frs_segment_classify(conn, wsg = "BULK",
                     gradient_max = 0.05,
                     channel_width = c(0.5, 999),
                     schema = "working")
```

**Essence:** given attribute ranges, tag segments that fall within all ranges. Multi-attribute AND filter → classified segments table.

### `frs_network_reach()`

Given break points, determine which segments are reachable from reference points (e.g. river mouth).

```r
# What's reachable upstream from the mouth, given these breaks?
frs_network_reach(conn, wsg = "BULK",
                  breaks_table = "working.breaks_validated",
                  schema = "working")

# Reachable from a specific point
frs_network_reach(conn, wsg = "BULK",
                  breaks_table = "working.breaks_validated",
                  from_blk = 360873822, from_measure = 0,
                  schema = "working")
```

**Essence:** flood-fill the network from a starting point, stopping at break points. Tag each segment as reachable or not.

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

### `frs_classify_override()`

Override automated classification with known/manual values.

```r
# Apply manual habitat classifications
frs_classify_override(conn, wsg = "BULK",
                      classified_table = "working.habitat_classified",
                      overrides = my_known_habitat,  # sf or table name
                      schema = "working")
```

**Essence:** left-join manual overrides onto classified segments, manual wins.

## Output Strategy

All functions write results server-side to `{schema}.{table}` — no data crosses the wire by default.

```r
# Default: write to pg (zero R memory)
frs_network_break(conn, wsg = "BULK", attribute = "gradient",
                  threshold = 0.05, schema = "working")

# Return sf object for inspection (small queries)
result <- frs_network_break(conn, wsg = "BULK", attribute = "gradient",
                            threshold = 0.05, collect = TRUE)

# Export to parquet after server-side compute
frs_network_break(conn, wsg = "BULK", attribute = "gradient",
                  threshold = 0.05, schema = "working",
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
5. **Composable** — `break → validate → reach → classify → summarize` chains naturally but each step is independently useful

## Future Attributes

`frs_segment_classify()` is attribute-agnostic by design. Current bcfishpass thresholds use gradient, channel width, and mean annual discharge. Temperature is a planned addition — same pattern, just another range parameter. The function doesn't care what the attribute represents.

## Non-Goals

- Lateral/off-channel habitat (that's flooded)
- Raster processing
- Species-specific wrapper functions (parameter sets can ship as data, not code)

## Open Questions

- Do we need `frs_segment_filter()` as distinct from `frs_segment_classify()`? (subsurface flow removal is filtering, not classifying)
- Should parameter sets (gradient thresholds per species, channel width ranges) ship as package data (`inst/parameters/`) or stay external?
- Local dev db via docker-compose for testing without remote permission constraints?

Relates to NewGraphEnvironment/bcfishpass
