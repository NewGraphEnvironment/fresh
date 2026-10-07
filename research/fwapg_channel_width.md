# fwapg channel width: where the NULLs come from and how MODELLED is computed

Source: measured 2026-10-07 on fwapg (`whse_basemapping`), while working fresh#234 (#29, #28). Details and queries in `planning/archive/2026-10-issue-234-channel-width-every-segment/findings.md`.

## Why first-order streams have no width

`whse_basemapping.fwa_stream_networks_channel_width` sources, province-wide:

| source | rows |
|---|---|
| FIELD_MEASURMENT | 75,736 |
| FWA_RIVERS_POLY | 185,172 |
| MODELLED | 1,937,793 |
| NULL | 2,708,728 |

In the Bulkley group, order 1 has 18,257 segments and only 1,139 widths (measured or mapped); orders 2-8 all have one.

- The regression is not order-limited: `fwapg.channel_width_modelled` is computed for every `wscode_ltree` / `localcode_ltree` pair.
- The NULLs come from one filter, `WHERE s.stream_order > 1`, in the `cwmodel` CTE of `fwapg/extras/channel_width/sql/channel_width.sql`.

## How MODELLED is computed

`round(exp(0.30713 + 0.4577882 * (ln(A) + ln(coalesce(P, 0) + 1) - ln(100) - ln(1000))), 2)` (Thorley & Irvine 2021b).

- `P` is `map_upstream` (mm).
- `A` is `max(coalesce(upstream_area_ha, 0)) + 1` over all of the code pair's watershed polygons.
- So the value is constant per code pair, and every segment on a reach gets the width at its downstream end.

Parity of the same formula against stored MODELLED (Bulkley, 11,334 rows):

| area input | exact (±0.01 m) | within 5% |
|---|---|---|
| each segment's own watershed poly | 141 | 1,164 |
| largest area per code pair (fwapg's way) | 3,445 | 10,640 (94%) |

On fwapg's own inputs the formula is exact on every row. The remaining gap to the stored values is drift between the input snapshot that built the table and the current one. `frs_channel_width()` documents the group-max `frs_col_join()` recipe for parity.

## Segments with no inputs

FWA placeholder (`999…` wscode) and unmapped (NULL localcode) segments get no upstream area. That is 366,377 of 4,907,441 segments (7.5%).

- `fwapg/load/fwa_streams_watersheds_lut.sql` excludes them on purpose; its spatial-midpoint fallback runs only for real-network segments.
- In the Bulkley group, 15,830 of the 15,831 real-network order-1 segments have both inputs.
- The rest are mostly construction lines inside waterbodies, plus 219 secondary-flow side channels (75 km).
- Deriving an area for them is half reachable: fresh#246.

## VCA (Hall 2007) vs Thorley & Irvine

`hall2007` (`0.196 * (A/100)^0.280 * (P/10)^0.355`, km² and cm/yr) runs below poisson2021 except on small catchments. The crossover depends on precipitation: about 189 ha at 12 mm, 65 ha at 100 mm, 16 ha at 1,000 mm and 5 ha at 4,000 mm. There is a second crossing below about 0.5 ha.
