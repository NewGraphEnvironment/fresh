# Snapping points to the FWA stream network

**Verified:** 2026-10-31 (the sweep re-run at exact measures, fresh#289) · **Issues:** fresh#247, fresh#266, fresh#274, fresh#289 · **Produced by:** `data-raw/point_snap_parity_check.R`, `data-raw/point_snap_tie_sweep.R`

Source: measured 2026-10-07 on fwapg (`whse_basemapping`, 4,907,441 segments in `fwa_stream_networks_sp`), while working fresh#247. The parity run is `data-raw/point_snap_parity_check.R`, with logs in `data-raw/logs/point_snap_parity_247/`.

Revised 2026-10-27 for fresh#266 (the tie rule, and what NewGraphEnvironment/fwapg#41 changes on fresh). That sweep is `data-raw/point_snap_tie_sweep.R`, logs in `data-raw/logs/indexpoint_266/`, run on the local docker fwapg (`docker/`, 4,907,441 segments, `exbc` still in `fwa_watershedatmeasure`, no `fwapg.db_version`) with the migrations applied inside a rolled-back transaction. Migration files and their md5s, the fwapg commit, and the elapsed times are in the log's header; the counts are in its body, which a second run reproduces byte for byte.

Revised 2026-10-31 for fresh#274: `frs_point_locate()` and the network traversals' segment picks send the measure at 17 significant digits. Before, `frs_point_locate()` wrote 15 (`sprintf("%s", m)`), which can round a stream's top *up*, past its last segment's end, so the head case below was not reachable through it.

Revised 2026-10-31 for fresh#289: the sweep sent its measures through one `format()` call over the whole frame, which shares one decimal count across the vector: 11 decimals for the CSV measures, which moved 12,260 of the 23,540 by up to 5e-12 m, so its CSV counts were of those rounded measures. It now sends `.frs_sql_exact()` text, as fresh does, and each state checks in SQL that the text parses back to the stored double. The re-run is the one below. Only the CSV-measure counts moved; the snapped positions, all whole metres, reproduce byte for byte. The head case is now scripted into the sweep rather than an unrecorded query.

## Three snappers, three candidate rules

| | fwapg `fwa_indexpoint()` | `link::lnk_points_snap()` (0.50.0) | `fresh::frs_point_snap()` (0.40.0) |
|---|---|---|---|
| candidates | one per `blue_line_key` (`DISTINCT ON`, nearest segment of each stream; first 100 by KNN) | per segment | per segment |
| excluded | edge type 6010 only | `wscode_ltree = '999'`, NULL localcode, `edge_type` 1425 (default) | `wscode_ltree <@ '999'`, NULL localcode, `edge_type` 1425 (default) |
| measure | fractional | whole metre: `CEIL(GREATEST(ds, FLOOR(LEAST(us, m))))` | same as link |
| distance ties | higher `downstream_route_measure`, then `linear_feature_id` (fwapg#41; **arbitrary** before it) | arbitrary (link 0.50.0; link#383) | higher raw `downstream_route_measure`, then `linear_feature_id` (fresh 0.44.0; `linear_feature_id` alone before it) |

- **Per-stream vs per-segment.** Choosing between *streams* (e.g. by drainage area at a gauge, as wet does) needs one candidate per stream, which only `fwa_indexpoint()` gives. Scoring per segment (e.g. link's PSCIS name and width scores) needs per-segment candidates.
- **Placeholder codes.** No segment has the bare code `999`. Placeholder codes are `999.*`, on 208,189 segments; 37,416 of them have a non-NULL local code. A `= '999'` test therefore excludes nothing, and only `<@ '999'` removes them.
- **Edge type 6010.** These are connectors where a stream leaves and re-enters a watershed group: 250 segments, 137 of which pass fresh's other guards. `fwa_indexpoint()` never returns them; link and fresh can.
- **The measure formula.** 2,989,828 of the candidate segments start at a fractional measure. In a segment's first fractional metre the formula rounds *up* to `CEIL(ds)`. 246 candidate segments are shorter than a metre and contain no whole metre, so there the measure lands past `us`. A point equidistant from two segments at a vertex resolves 1 m apart depending on which segment wins the tie.
- **The tie rule (fresh#266, 2026-10-27).** An exact distance tie is a point whose nearest point on two segments is the vertex they share — common, since any point in the wedge outside a bend is one. It now goes to the segment with the **higher** `downstream_route_measure`: the one *starting* at that vertex, which is the one a measure there falls on, because measures resolve `[downstream, upstream)`. `linear_feature_id` breaks what is still tied. fwapg adopted this in NewGraphEnvironment/fwapg#41 (upstream smnorris/fwapg#201), so `fwa_indexpoint()` and `frs_point_snap()` now agree on which segment a tie belongs to, and therefore on its local code — which differs between the two segments whenever a tributary joins at the vertex.
  - fresh orders on the **raw** measure, not the whole-metre one it emits. Two segments sharing a vertex on a whole metre clamp to the same value, so ordering on the emitted measure would fall through to `linear_feature_id` and reinstate the old rule. The raw measure is carried out of the lateral as an internal `measure_raw` and ordered on at all three sites (the lateral's KNN `ORDER BY ... LIMIT`, the `candidate_rank` window, and the final `ORDER BY`); it is not in the outer `SELECT`, so no new column reaches the caller.
  - The GiST KNN index-ordered scan survives the extra key: `EXPLAIN` shows the tie key as an `Incremental Sort` with `Presorted Key: ((s.geom <-> ...))` over `Index Scan ... Order By: (geom <-> ...)`.
  - **Within one stream the rule is positional. Across streams it is not.** fwapg's `ORDER BY blue_line_key, distance_to_stream, downstream_route_measure DESC, linear_feature_id` partitions by stream before comparing measures, because `fwa_indexpoint()` takes one candidate per stream. fresh returns candidates per segment, nearest first, so it cannot lead on `blue_line_key` without breaking distance ordering; where a tie falls across two blue lines it compares measures belonging to different streams. Deterministic, but no more positional than the lowest-id rule was. Most ties measured in fresh's snap are of this kind, not the within-one-stream kind.
  - The two rules happen to **agree** whenever the upper segment is also the lower-numbered one, so a tie is not by itself a red/green test. The worked pin is 08KD006 on the Willow River (`tests/testthat/test-frs_point_snap.R`): 703862843 and 703862887 tie to the bit at 67.563693805068 m, clamped measures 14040 and 14041, local codes `100.594120.061391` and `100.594120.063640`.
  - A point placed exactly **on** the shared vertex is not a usable pin: it is a three-way tie there (the tributary's own segment touches the vertex and passes fresh's guards), and `ST_Distance` is not bit-equal, so the pre-#266 code already returns the new answer by floating-point accident.

## What fwapg#41 changes on fresh (fresh#266, measured 2026-10-27)

Measured by `data-raw/point_snap_tie_sweep.R`, logs in `data-raw/logs/indexpoint_266/`. The two
pending migrations were applied inside a transaction and **rolled back** (`frs_migration_trial()`),
on the local docker fwapg, in three states so each change is attributed rather than inferred: base,
`202610240132__indexpoint_tiebreak` alone, and both in filename order. **No database was
migrated.** 49,725 snapped positions (all 19,905 PSCIS assessments plus 5,000 fish observation
points, tolerance 150, `num_features = 5`), 23,540 measures from `crossings.csv` / `falls.csv` /
`wsg_outlet.csv`, 970 positions for the expensive calls, and 400 blue lines each sent at its own
top. Every measure is sent at 17 significant digits (fresh#289; the 2026-10-27 run rounded them to 11 decimals).

| state | `fwa_locatealong()` misses, 49,725 snapped positions | misses, 23,540 CSV measures | `fwa_watershedatmeasure()` misses, 970 | its errors |
|---|---|---|---|---|
| base | **0** | 36 | 85 | 294 |
| tiebreak only | **0** | 31 | 86 | 293 |
| both | **0** | 31 | 86 | 293 |

Rounded to 11 decimals the CSV column read 42 / 38 / 38. Shifts of at most 5e-12 m were enough to
move a net 6 measures across a segment boundary before the migration and 7 after, and they hid
one the migration fixes (below).

- **Nothing changes on fresh's own snap path.** All 49,725 positions resolve in every state. fresh
  clamps its measure to a whole metre, and **no** candidate segment has an integer
  `upstream_route_measure`, so a clamped measure never lands on a stream's top — the case the
  migration fixes is not reachable through `frs_point_snap()` → `frs_point_locate()`. It is
  reachable when a caller passes a segment's own `upstream_route_measure`, which is what link does.
- **The head case, and why it existed.** The pre-rework `fwa_locatealong()` compares bounds
  **rounded to 4 decimals**: `round(ds,4) <= round(m,4) AND round(us,4) > round(m,4)`. A measure at
  a stream's top can therefore never be placed — `round(us,4) > round(us,4)` is false by
  construction. Of 400 blue lines sampled by `ORDER BY md5(blue_line_key::text)`, each sent at its
  own top (`max(upstream_route_measure)` over every segment, since `fwa_locatealong()` has no
  guards) at 17 significant digits, **0** resolve before and **383** after. On 341 of them the top
  is a segment fresh would snap to, and there it is 0 → **327**. 17 (14) still miss after the
  migration. Per line in `sweep_tops.csv`. This replaces the unscripted "2 before, 218 after"
  from fresh#266, whose way of writing the tops was not recorded. Taking the same 400 lines'
  candidate-segment top instead gives 345 tops and 2 before, as #266 had: both (359014708,
  359017843) are lines whose candidate top sits below a later segment, so the measure is not
  a head case there.
- **5 CSV measures now resolve** that did not: `wsg_outlet.csv` 356363393 @ 322.567 and 360880826 @
  2100.018; `crossings.csv` 356355973 @ 4494.61997946051, 360862508 @ 10821.8246201562 and
  356312469 @ 957.70485427024903 (`sweep_changed.csv` carries each as the `%.17g` text sent; the
  crossings are bcfishpass's own fractional indexing, which fresh never emits). The last is the
  head case inside a stream. It lies 3.4e-13 m below the top of segment 702605415
  (957.70485427024937; the CSV holds that top written at 15 significant digits), which the old
  4-decimal comparison cannot place, and the next segment starts 0.5 mm higher, at
  957.705341846863. Rounded to 11 decimals it went out as `957.70485427025`, 6.3e-13 m *above*
  that top and so in the gap, missed in every state, and the 2026-10-27 run did not see it move.
- **One position stops erroring**: 359434058 @ 159, which raised
  `line_interpolate_point: 2nd arg isn't within [0,1]`. The error comes through
  `fwa_upstreambordercrossings`, which the tiebreak migration rewrites;
  `fwa_watershedatmeasure()`'s own segment pick (`downstream_route_measure <= v_measure ORDER BY
  desc LIMIT 1`) has **no top bound to close**, so the transition is error → no error, not a
  change of placement. Pinned in `tests/testthat/test-frs_fwapg_gate.R`.
- **Every change belongs to the tiebreak migration.** `202610131654__watershedatmeasure_drop_exbc`
  moves nothing on fresh's paths.
- **Ties, counted exhaustively on the base side:** 2,536 tied groups over the PSCIS positions, of
  which **301 are within one stream** and 2,235 across two; 927 over the observation sample, 139
  within and 788 across. So only about an eighth of ties are the kind the positional rule is
  about — the rest it resolves deterministically but arbitrarily, as the old rule did.

### What it does not fix

- **293 of 970 positions (30%) error in all three states** with `more than one row returned by a
  subquery used as an expression`, from `fwa_watershedatmeasure()`. A pre-existing fwapg defect,
  untouched by either migration, and worth reporting upstream.
- 85 → 86 watershed misses and 36 → 31 locatealong misses are the net; the sweep names each
  position that moved in `sweep_changed.csv`.
- `frs_cluster()`'s downstream trace starts are always a segment's own `downstream_route_measure`,
  inside its range under either rule, and a `CROSS JOIN LATERAL` drops a zero-row trace silently.
  Nothing to pin there; the sweep counts empty traces instead (2, unchanged across states).

## Parity (PSCIS, 150 m)

Measured against **fresh 0.40.0's lowest-`linear_feature_id` rule and link 0.50.0**. fresh#266
changed fresh's tie rule, so the tie rows below no longer describe current fresh; they are not
re-runnable as a comparison either, since link is in neither `Imports` nor `Suggests` and
`data-raw/point_snap_parity_check.R` hard-stops without it. link#383 carries the re-run.

All 19,905 crossings in `whse_fish.pscis_assessment_svw`, link vs fresh:

- 18,180 identical picks (same `blue_line_key` and measure).
- 22 equidistant ties: same stream, measures 1 m apart.
- 11 where link picked a `999.*` segment. Fresh leaves 8 of these unsnapped and snaps 3 to the nearest real stream.
- 1,692 that neither snapped.
- 0 other differences.

At `num_features = 5`, 18,108 candidate sets are identical. 86 differ only at a tied fifth candidate, and 19 contain a link `999.*` candidate. There are 0 measure mismatches on shared candidates.

The "22 equidistant ties: same stream, measures 1 m apart" line above is the population fresh#266
re-decides: under the new rule fresh takes the upper segment of each, and `fwa_indexpoint()` will
too once fwapg#41 lands.
