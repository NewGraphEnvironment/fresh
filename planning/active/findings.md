# Vignette Findings

## Lake rearing gap (bcfishpass#7)

In BULK watershed group:
- Lake segments: 1140 total, **0 rearing**, 29 spawning
- Wetland segments: 4481 total, 2605 rearing, 232 spawning
- Stream segments (in waterbodies): 2143 total, 1709 rearing, 1783 spawning

bcfishpass coho model scores lake-connected stream segments as `rearing = 0`. Wetland-connected segments DO get scored. This is a known gap — coho use lakes for rearing ecologically.

Fresh can fix this by classifying lake-connected segments independently using channel_width and gradient thresholds, ignoring bcfishpass's rearing score.

## Data sources

- `whse_basemapping.fwa_streams_vw` — has channel_width + mad_m3s (from fwapg regression), uses `wscode`/`localcode` (no `_ltree` suffix)
- `whse_basemapping.fwa_stream_networks_sp` — base table with ltree GiST indexes, used for traversal
- `bcfishpass.streams_co_vw` — has spawning/rearing scores but these have the lake gap
- Set `options(fresh.wscode_col = "wscode", fresh.localcode_col = "localcode")` for fwa_streams_vw

## Skeena region specifics

- Channel width is the primary habitat predictor (MAD model not applied)
- `params$CO$ranges$spawn[c("gradient", "channel_width")]` — drop mad_m3s
- mad_m3s is NULL on many Skeena streams

## Byman-Ailport test area

- BLK 360873822, drm_byman = 208877, drm_ailport = 233564
- Bundled data in inst/extdata/byman_ailport.rds
- ~2167 FWA segments, 89 lakes, 323 wetlands (before filtering)
- After CO habitat filter: 0 lakes (gap), 69 wetlands

## Scenario testing

- Baseline: spawn_gradient_min = 0 (bcfishpass default)
- Scenario A: spawn_gradient_min = 0.005 (0.5%)
- Scenario B: spawn_gradient_min = 0.01 (1%)
- Compare via frs_aggregate: habitat km upstream of crossings
