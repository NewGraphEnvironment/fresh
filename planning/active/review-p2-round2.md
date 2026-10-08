# Review: #247 Phase 2, round 2

Scope: the staged diff (`R/frs_point_snap.R`, `R/frs_watershed_split.R`
and the tests), with the round 1 fixes checked closely. Changed test files
pass against local fwapg.

## Findings

- **[severity: fragile]** R/frs_point_snap.R:282-293. Fix #2 covers only
  `srid == 4326`. Other geographic SRIDs still fail the whole batch on one
  bad latitude. Probed on local fwapg:
  - `frs_point_snap(conn, df, srid = 4617)` with one row at lat 95 errors
    with `transform: latitude or longitude exceeded limits (-14)`.
  - `ST_Transform(ST_SetSRID(ST_MakePoint(-126, 95), 4269), 3005)` fails
    the same way.

  This applies to a data frame given `srid = 4269 / 4617 / 4267`, and to an
  `sf` in NAD83 (the SRID is taken from `st_crs()$epsg`, so the 4326-only
  test never matches). `frs_watershed_split()` always uses 4326, so this is
  not a regression there. It is the same per-point failure mode, one CRS
  over, on the new `sf` and data frame inputs.

  A related point: out-of-range longitude does not actually fail PostGIS.
  `(-500, 54)` in 4326 transforms without error by wrapping. Only latitude
  above 90 fails. Dropping a bad longitude is still reasonable, but the
  failure to guard against is latitude.

  Suggested fix: decide "geographic" from the CRS, not the code, e.g.
  `isTRUE(sf::st_crs(srid)$IsGeographic)`, and run the same range drop.

- **[severity: fragile, low]** R/frs_point_snap.R:143-149, 198-199. This is
  fix #1 one axis over. The network table is also an input to the
  `CREATE TABLE ... AS`, but `to` is only compared against `points`.
  Passing `to = .frs_opt("tbl_network")` (or a custom network table set via
  options) runs `DROP TABLE` on the network before the snap reads it.
  - On stock fwapg the dependent view `fiss_fish_obsrvtn_events_vw` makes
    that DROP fail (no CASCADE), so the default table is protected by
    accident.
  - A custom network table with no dependent views would be lost.

  Cheap guard: also refuse `tolower(to) == tolower(.frs_opt("tbl_network"))`.

## Verified fine (round 2 probes)

- **NaN / Inf coordinates:**
  - NaN x is dropped quietly (no error).
  - Inf x in 4326 is dropped with the message.
  - Inf or 1e12 coordinates in 26909 do not fail the batch.
  - lat ±90 in 4326 transforms fine to 3005.
- **integer64 scalar args:** `num_features`, `stream_order_min`, `srid`,
  `exclude_edge_types`, a `col_blk` hint and x/y all reach the SQL
  correctly (`LIMIT 2`, `stream_order >= 3`, `NOT IN (1425)`). The hint
  constrains as intended.
- **`tolerance = Inf`:** renders as `'Infinity'::double precision` and works.
- **`num_features = Inf`:** errors loudly (`LIMIT NA`); it does not fail
  silently.
- **Pick ordering:** the tiebreak on `linear_feature_id` is unique in the
  network, so `candidate_rank` and the `LIMIT` pick are deterministic.
- **`frs_watershed_split()`:**
  - `id_point` maps back to row order.
  - Skipped-point messages fire for both no-candidate rows and
    out-of-range rows.
  - The mocks match the real call's arguments.
- **Test files:** `test-frs_point_snap.R`, `test-frs_watershed_split.R`,
  `test-frs_point_locate.R` and `test-frs_network_{prune,upstream,downstream}.R`
  all pass against local fwapg.
