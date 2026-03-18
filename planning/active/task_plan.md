# Vignette: Coho Habitat Pipeline (Byman-Ailport)

## Goal

Build a vignette that runs the full habitat model pipeline on the Byman-Ailport subbasin. Proves the workflow at small scale before expanding to full Neexdzii study area in the restoration report repo.

## Pipeline

```r
conn <- frs_db_conn()
params <- frs_params(csv = system.file("testdata", "test_params.csv", package = "fresh"))
aoi <- d$aoi  # Byman-Ailport from bundled data

# Extract from fwapg (has channel_width, not bcfishpass-dependent)
options(fresh.wscode_col = "wscode", fresh.localcode_col = "localcode")

conn |>
  frs_extract("whse_basemapping.fwa_streams_vw", "working.byman_streams",
    cols = c("linear_feature_id", "blue_line_key", "gnis_name",
             "stream_order", "downstream_route_measure",
             "upstream_route_measure", "wscode", "localcode",
             "gradient", "channel_width", "mad_m3s",
             "waterbody_key", "geom"),
    aoi = aoi, overwrite = TRUE) |>
  frs_col_generate("working.byman_streams") |>
  frs_break("working.byman_streams",
    attribute = "gradient", threshold = params$CO$spawn_gradient_max) |>
  frs_classify("working.byman_streams", label = "accessible",
    breaks = "working.breaks") |>
  frs_classify("working.byman_streams", label = "co_spawning",
    ranges = params$CO$ranges$spawn[c("gradient", "channel_width")]) |>
  frs_classify("working.byman_streams", label = "co_rearing",
    ranges = params$CO$ranges$rear[c("gradient", "channel_width")])

# Waterbodies on coho habitat
frs_network(conn, blk, drm, upstream_measure = drm_up,
  tables = list(
    lakes = list(table = "whse_basemapping.fwa_lakes_poly",
                 from = "working.byman_streams",
                 extra_where = "co_rearing IS TRUE"),
    wetlands = list(table = "whse_basemapping.fwa_wetlands_poly",
                    from = "working.byman_streams",
                    extra_where = "co_rearing IS TRUE")
  ))

# Aggregate: habitat upstream of crossings
frs_aggregate(conn,
  points = "bcfishpass.crossings",
  features = "working.byman_streams",
  metrics = c(
    total_km = "ROUND(SUM(ST_Length(f.geom))::numeric/1000, 1)",
    spawning_km = "...",
    rearing_km = "..."),
  direction = "upstream")
```

## Vignette sections

1. **Setup** — load params from CSV, connect, set options
2. **Extract** — stage Byman-Ailport streams from fwa_streams_vw
3. **Break** — gradient barriers at CO spawn threshold (5.49%)
4. **Classify** — accessible, co_spawning, co_rearing
5. **Lake rearing gap** — show bcfishpass scores lake segments as rearing=0, our pipeline can fix this by classifying lake-connected segments independently
6. **Waterbodies** — filter lakes/wetlands to coho habitat network using from + extra_where
7. **Aggregate** — habitat lengths upstream of key points
8. **Scenario comparison** — tweak spawn_gradient_min to 0.5% and 1%, compare with frs_aggregate
9. **Plots** — before/after, accessible vs blocked, spawning/rearing, waterbodies

## Key points to demonstrate

- frs_params loads from CSV — edit locally, no DB changes for scenarios
- frs_col_generate makes gradient auto-recompute after breaks
- frs_classify is pipeable — multiple labels in sequence
- Lake rearing: bcfishpass gap, fresh fixes it
- Scenario testing: same pipeline, different params, compare outputs
- This exact pipeline scales to full Neexdzii by swapping the AOI

## Vignette pattern

- `vignettes/habitat-pipeline.Rmd.orig` = source with live DB queries
- `vignettes/habitat-pipeline.Rmd` = pre-knitted cached version
- `params$update_gis` controls live vs cached
- Cache results to `inst/extdata/` for offline rendering

## Depends on

- v0.3.1 (tagged, all functions working)
- Byman-Ailport bundled data in inst/extdata/
- test_params.csv in inst/testdata/
- SSH tunnel to remote DB for live queries

## Downstream

After vignette proves the pipeline:
- Neexdzii restoration report runs same pipeline at full study area scale
- Feeds into flooded (floodplain delineation) → drift (land cover change)
