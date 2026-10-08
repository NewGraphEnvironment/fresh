# Snapping points to the FWA stream network

Source: measured 2026-10-07 on fwapg (`whse_basemapping`, 4,907,441 segments in `fwa_stream_networks_sp`), while working fresh#247. The parity run is `data-raw/point_snap_parity_check.R`, with logs in `data-raw/logs/point_snap_parity_247/`.

## Three snappers, three candidate rules

| | fwapg `fwa_indexpoint()` | `link::lnk_points_snap()` (0.50.0) | `fresh::frs_point_snap()` (0.40.0) |
|---|---|---|---|
| candidates | one per `blue_line_key` (`DISTINCT ON`, nearest segment of each stream; first 100 by KNN) | per segment | per segment |
| excluded | edge type 6010 only | `wscode_ltree = '999'`, NULL localcode, `edge_type` 1425 (default) | `wscode_ltree <@ '999'`, NULL localcode, `edge_type` 1425 (default) |
| measure | fractional | whole metre: `CEIL(GREATEST(ds, FLOOR(LEAST(us, m))))` | same as link |
| distance ties | arbitrary | arbitrary | `linear_feature_id` |

- **Per-stream vs per-segment.** Choosing between *streams* (e.g. by drainage area at a gauge, as wet does) needs one candidate per stream, which only `fwa_indexpoint()` gives. Scoring per segment (e.g. link's PSCIS name and width scores) needs per-segment candidates.
- **Placeholder codes.** No segment has the bare code `999`. Placeholder codes are `999.*`, on 208,189 segments; 37,416 of them have a non-NULL local code. A `= '999'` test therefore excludes nothing, and only `<@ '999'` removes them.
- **Edge type 6010.** These are connectors where a stream leaves and re-enters a watershed group: 250 segments, 137 of which pass fresh's other guards. `fwa_indexpoint()` never returns them; link and fresh can.
- **The measure formula.** 2,989,828 of the candidate segments start at a fractional measure. In a segment's first fractional metre the formula rounds *up* to `CEIL(ds)`. 246 candidate segments are shorter than a metre and contain no whole metre, so there the measure lands past `us`. A point equidistant from two segments at a vertex resolves 1 m apart depending on which segment wins the tie.

## Parity (PSCIS, 150 m)

All 19,905 crossings in `whse_fish.pscis_assessment_svw`, link vs fresh:

- 18,180 identical picks (same `blue_line_key` and measure).
- 22 equidistant ties: same stream, measures 1 m apart.
- 11 where link picked a `999.*` segment. Fresh leaves 8 of these unsnapped and snaps 3 to the nearest real stream.
- 1,692 that neither snapped.
- 0 other differences.

At `num_features = 5`, 18,108 candidate sets are identical. 86 differ only at a tied fifth candidate, and 19 contain a link `999.*` candidate. There are 0 measure mismatches on shared candidates.
