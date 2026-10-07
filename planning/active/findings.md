# Findings — Channel width for every segment (#234)

## Issue context

**If we do it:** every segment, including first-order streams, has a channel width, and there is an independent bankfull estimate to fill or check it against. **If we never do:** consumers that buffer by channel width silently skip the smallest streams.

#28 depends on #29: the regression is what fills the missing widths.

## Sub-issues

- [ ] #29 — estimate channel width from a bankfull regression
- [ ] #28 — fill NA channel width for small-order streams


## How to close

`/planning-init` on this issue, one phase per sub-issue. Each phase commit carries `Fixes #N` for the sub-issue it completes; the PR carries `Fixes` for this umbrella and each sub-issue.


### #29 — Estimate channel width from bankfull regression

## Problem

bcfishpass `channel_width` is modelled by Poisson Consulting (2021b) using a single-exponent discharge proxy:

```
channel_width = exp(0.307) * (area_ha * precip_mm / 100000) ^ 0.458
```

This differs from the original USDA VCA bankfull regression (Hall 2007) that flooded uses internally for flood depth:

```
bankfull_width = (area_ha ^ 0.280) * 0.196 * (precip_mm ^ 0.355)
```

Users working with flooded need a way to estimate or validate channel width independently — especially for order 1 streams where bcfishpass returns NA (#28), and for cases where the two regressions diverge significantly.

## Proposed Solution

Add a helper (e.g., `frs_channel_width()`) that:
- Fills NA widths for order 1 streams (supersedes #28)
- Lets users choose which regression to apply (Poisson 2021b, VCA/Hall 2007, or custom)
- Provides an independent estimate to compare against bcfishpass predictions

Could also accept a user-supplied regression or lookup table for regional calibration.

## References

- Poisson Consulting 2021b: `fwapg/extras/channel_width/sql/channel_width_modelled.sql`
- VCA source: Hall 2007, documented in `bcfishpass/model/03_habitat_lateral/valley_confinement.md`
- bcfishpass docs: `docs/03_model_habitat_linear.md`

Relates to #28
Relates to NewGraphEnvironment/flooded#21


### #28 — Fill NA channel_width for small order streams

## Problem

`bcfishpass.streams_co_vw` has `NULL` channel_width for all order 1 streams (45 of 135 segments in the flooded test area). The bankfull regression model doesn't predict for the smallest streams.

Downstream consumers like `flooded::fl_valley_confine()` use `channel_width` to buffer streams into the valley output (DEM correction for sub-pixel channels). Streams with NA width get skipped entirely — losing order 1 coverage.

## Proposed Solution

Helper function (e.g. `frs_channel_width_fill()`) that fills NA channel_width values using one of:

- Bankfull regression from `upstream_area_ha` and `map_upstream` (same model flooded uses internally)
- Stream order lookup table (rough defaults: order 1 ≈ 1m, order 2 ≈ 2m)
- User-supplied minimum value

Could also be a parameter on `frs_network()` to auto-fill on fetch.

Discovered while building flooded test data with all co orders (not just 4+). Order 4+ streams all have width; order 1 have none.


## Exploration (2026-10-07, local fwapg)

### Where order-1 NULLs come from
- `whse_basemapping.fwa_stream_networks_channel_width` sources: FIELD_MEASURMENT 75,736; FWA_RIVERS_POLY 185,172; MODELLED 1,937,793; NULL 2,708,728.
- BULK: order 1 = 18,257 segments, 1,139 with width (measured/mapped only); orders 2-8 all have width.
- Cause: `fwapg/extras/channel_width/sql/channel_width.sql` builds the `cwmodel` CTE with `WHERE s.stream_order > 1`. The underlying `fwapg.channel_width_modelled` is computed for every wscode/localcode pair, so the regression itself is not order-limited.

### Regression forms (one power law, two presets)
`width = k * ((A + off) / a_div)^a * ((P + off) / p_div)^b`, A = upstream_area_ha, P = map_upstream (mm).

- **poisson2021** (Thorley & Irvine 2021b, `channel_width_modelled.sql`):
  `round(exp(0.3071300 + 0.4577882 * (ln(A) + ln(coalesce(P,0) + 1) - ln(100) - ln(1000))), 2)`, where fwapg's A is `max(coalesce(ua,0)) + 1` over the wscode/localcode group. Preset: k = exp(0.30713), a = b = 0.4577882, a_div = 100, p_div = 1000, off = 1. fwapg takes the max area per code pair and fresh uses the segment's own area, so expect small differences where a pair spans several watershed polys.
- **hall2007** (VCA; flooded `fl_flood_surface()`): `0.196 * (A/100)^0.280 * (P/10)^0.355`, with km² and cm/yr. Preset: k = 0.196, a = 0.280, b = 0.355, a_div = 100, p_div = 10, off = 0. flooded notes Hall widths run well below bcfishpass (5.7 m vs 31.3 m, Bulkley).

### Input coverage (BULK)
| order | n | upstream_area_ha | map_upstream |
|---|---|---|---|
| 1 | 18,257 | 15,830 | 15,831 |
| 2 | 6,460 | 6,459 | 6,460 |
| 3+ | ~7,755 | ~all | all |

- The streams→watersheds lut (`fwa_streams_watersheds_lut`, 4,538,224 rows) misses 2,427 order-1 BULK segments: 1,513 are placeholder (`999` wscode) and unmapped, 913 are unmapped (NULL localcode) only, and 1 is real-network.
- So 15,830 of the 15,831 real-network order-1 segments have both inputs.
- Edge types of the misses: 1400 in a waterbody (1,511), 1450 in a waterbody (486), 1100 secondary flow, not in a waterbody (219; every midpoint intersects a fundamental watershed poly), 1350 (177), others small.
- fwapg's lut build (`fwapg/load/fwa_streams_watersheds_lut.sql`) matches on codes, then falls back to a spatial midpoint. It explicitly excludes `999%` and NULL `local_watershed_code`, which is why these are missing.
- These are the same segments `.frs_stream_guards()` excludes from traversal. WSG-level `frs_extract()` does not guard, so they do appear in working tables.

### Test patterns
- SQL-string unit tests mock `.frs_db_execute` + `DBI::dbGetQuery` (`tests/testthat/test-frs_col_join.R`).
- Live tests gate on `skip_if_no_conn()` (`tests/testthat/helper-db.R`).

### fwapg parity of poisson2021 (BULK, MODELLED rows, n = 11,334)
- Per-segment upstream area (each segment's own watershed poly): 141 exact (±0.01), 1,164 within 5%. Poor.
- Group max area per wscode/localcode pair (+1), as `channel_width_modelled.sql` does: 3,445 exact, 10,640 (94%) within 5%, median est/fwapg ratio 0.993.
- So fwapg's MODELLED is constant per code pair, set by the most downstream poly. The formula matches; the area aggregation drives parity. The function takes whatever area column the caller joined. Docs give the group-max `frs_col_join()` subquery for parity. The residual is likely snapshot differences in area/precip inputs.

## Plan-agent review (2026-10-07)
- Blocker fixed: the fill-NULL guard moved into Phase 1. Otherwise the `Fixes #29` commit's default call would overwrite measured/mapped widths.
- Adopted: `exp(0.30713)` emitted in SQL (avoids rounding-boundary flips from R-side k); `digits` per preset; separate `a_off` / `p_off`; type checks on existing `to` / `col_source`; collision errors; `overwrite = TRUE` clears to NULL then refills (consistent with `value`); Byman-Ailport AOI + `skip_if_no_conn()`; assert n compared > 0.
- Dropped: `_pkgdown.yml` item (no reference index). NEWS/version handled by `/gh-pr-merge` release commit (repo history: every "Release vX" commit carries NEWS + DESCRIPTION).
