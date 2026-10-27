# Findings — frs_point_snap(): fwapg's tie rule, and a sweep and live tests for the reworked fwapg functions (#266)

## Issue context

`frs_point_snap()` breaks an exact distance tie on the lowest `linear_feature_id` (`R/frs_point_snap.R:419`, `:463`; `research/fwa_point_snap.md`, "distance ties"). fwapg's `fwa_indexpoint()` is moving to a different rule (NewGraphEnvironment/fwapg#39): the segment that **starts** at the vertex.

A tie is a point whose nearest point on two adjacent segments of one stream is the vertex they share. That is common: any point in the wedge outside a bend is one. On a loaded fwapg, 9 of 242 random BC points and 57 of 1,000 points near segment ends hit one, and in about half the two segments' localcodes differ (a tributary joins at the vertex).

fwapg resolves a measure as `[downstream, upstream)` (`FWA_LocateAlong`, `FWA_WatershedAtMeasure`), so a measure on the vertex belongs to the upper segment. Lowest id is not related to position, and it picks the lower segment whenever that one has the smaller id. Then:

- after fwapg#39, fresh and `fwa_indexpoint()` can disagree on segment and localcode for the same point;
- with fresh's whole-metre measure (`CEIL(GREATEST(ds, FLOOR(LEAST(us, m))))`), the research note already records that the two segments resolve 1 m apart.

Proposed: order ties as `distance_to_stream, downstream_route_measure DESC, linear_feature_id` at both places, and record the rule in `research/fwa_point_snap.md`. `link::lnk_points_snap()` breaks ties arbitrarily (same note) and may want the same rule.


## From wet#127 (measured 2026-10-27)

wet did this issue's work for `wet_station_snap()` (NewGraphEnvironment/wet#127, PR NewGraphEnvironment/wet#132; `research/station_snap.md`). What carries over:

**The rolled-back trial.** wet's internal `wet_pg_trial()` (`R/wet_pg_trial.R`) does step 1's recipe. Three review rounds found that the step 1 grep misses ways a migration can still commit:
- a transaction command split by a line break or a comment (`COMMIT\n;`, `COMMIT -- c\nWORK;`, `/* c */ COMMIT;`);
- an unterminated last statement (`COMMIT` at the end of the file);
- a long run of comments, which sent PCRE past its match limit. `gregexpr()` only warns and reports no match, so the COMMIT went through.

A rollback also does not undo work done on another connection (`dblink` is installed on fwapg) or through `COPY ... PROGRAM`, nor `setval()`.

wet's version:
- refuses all of the above;
- records `pg_current_xact_id()` at `BEGIN` and refuses if the session holds a different one after the migration;
- defers the rollback to the caller's frame.

The statements that can end a transaction block are ABORT, COMMIT, END, ROLLBACK and PREPARE TRANSACTION; COMMIT inside DO or CALL raises an error instead. Before copying the function into fresh and link, decide where one copy should live.

**Running the sweep.**
- Run before and after on separate connections, each in its own transaction.
- Put every call under its own `SAVEPOINT`. An error outside one aborts the transaction, and every later call then "errors" for that reason.
- Set `SET LOCAL statement_timeout`: `fwa_watershedatmeasure()` took about 2 s a point and 11 s for the largest basins, so 490 gauges took 38 min a sweep. Large inputs such as PSCIS and fish observations will need a sample.
- The before run must reproduce the package's stored output, so the migration's effect is not mixed up with changes to the database since. A second full run gave a byte-identical report.

**The gate (item 3), two ways it can fail toward pass.**
- The test that fails under the environment variable must connect directly, not through the helper that skips on CI or on no connection. Otherwise an unreachable database passes.
- It must read the database's committed state on its own connection, never a trial's, which would satisfy it.

wet's variables are `WET_FWAPG_CURRENT=true` (fail rather than skip) and `WET_FWAPG_TRIAL=<migration file>` (run the gated tests against a trial). The trial path must be absolute, because testthat runs from `tests/testthat`.

**What the sweep found on 490 HYDAT gauges.**
- **Ties:** 76 streams at 64 gauges (13 %) were tied. 36 of the 76 return the other segment after the migration, so before it the choice was the query plan's.
- **`fwa_locatealong()` misses:** 114 of 2,304 candidate measures before, 0 after. 110 of them are on the top segment of a stream (a head), where the measure ran up to 1.1 mm past the top; 4 are ties.

Those misses come from `fwa_indexpoint()`'s fractional measure. Fresh's measure (`CEIL(GREATEST(ds, FLOOR(LEAST(us, m))))`) stays below a head's top except in two cases:
- **The top is a whole metre:** the measure then equals it. The old open-top rule rejects that and the new closed top accepts it.
- **The segment is shorter than a metre:** `CEIL` of its start can pass the top. At a head, neither rule places that point.

So expect few head differences in `frs_point_locate()`, `frs_watershed_at_measure()` and `frs_cluster()`, and count both cases in the sweep.

**Points to reuse in live tests** (lon, lat; WGS84):
- **08KD006** (-122.373062133789, 54.0455589294434), a tie on Willow River (blue line 356360570) between 703862843 and 703862887. The old `fwa_indexpoint()` returned the lower one, where `fwa_locatealong()` and `fwa_watershedatmeasure()` find nothing; the new one returns 703862887, whose watershed is 2,861.2 km².
- **07EA001** (-125.626388549805, 57.4208297729492), an exact tie on blue line 359014591. The new rule gives 207086752; the old gave 207086967, where `fwa_locatealong()` finds nothing.
- **07FA007** (-122.624717712402, 56.8233299255371). Its candidates on blue lines 359001991 and 359001990 sit on stream heads.

**The base the sweep ran on.** A fwapg without migration `202610131654` (the `exbc` branch is still in `fwa_watershedatmeasure()`). There, `FWA_UpstreamBorderCrossings` raised `line_interpolate_point: 2nd arg isn't within [0,1]` at 2 of 490 picked points, and the migration fixes that. Record the base, since `exbc` adds area for points with an upstream border crossing.

## What else reaches fresh

The rule above is fresh's own SQL. fresh also calls fwapg functions that the same fwapg change alters:

- `frs_point_locate()` calls `fwa_locatealong()` (`R/frs_point_locate.R:29`).
- `frs_watershed_at_measure()` and a helper in `R/utils.R:857` call `fwa_watershedatmeasure()` (`R/frs_watershed_at_measure.R:82, 95`).
- `frs_cluster()` calls `fwa_downstreamtrace()` (`R/frs_cluster.R:330`).

fresh's whole-metre measure is clamped to the segment, so it rarely hits the mm-scale problems below. A measure at a stream's head is the exception: those functions now accept it.

## What changes in fwapg

NewGraphEnvironment/fwapg#41 (PR NewGraphEnvironment/fwapg#43, offered upstream as smnorris/fwapg#201) reworks one migration. None of it reaches this package until the database it connects to is migrated.

- `fwa_indexpoint()`:
  - An exact distance tie between two segments of one stream goes to the segment **starting** at the shared vertex, then `linear_feature_id`. Before, the plan picked.
  - The measure is the stream geometry's m, not `downstream_route_measure + fraction * length_metre` (up to ~5 mm apart).
  - `geom` is PointZM.
  - Optional `include_disconnected` / `include_null_localcodes` filters run before the per-stream pick.
  - A point on a watershed-group boundary no longer errors.
- `FWA_LocateAlong`, `FWA_UpstreamTrace`, `FWA_DownstreamTrace`, `FWA_WatershedHex` and `FWA_WatershedStream` take the highest segment whose measure range, closed at the top, holds the measure. A measure at a stream's head now works. `FWA_UpstreamBorderCrossings` and `FWA_SliceWatershedAtPoint` no longer error near a segment's top.

Measured on a loaded fwapg:
- `FWA_WatershedAtMeasure` failed to place 156 of 1,190 random-point snaps (5 streams each); after the change, none.
- `FWA_LocateAlong` misses fell from 1,627 to 34 of 11,182 indexed measures.
- Nothing that returned rows before changed.

## Work here

1. **Sweep, before and after.** Run this package's own path over its real inputs (listed below) and count three things: snapped positions where `FWA_LocateAlong` or `FWA_WatershedAtMeasure` returns nothing; points tied on two segments of one stream; calls that error. Run once against the current database, then against the migration applied inside a transaction that is rolled back (`BEGIN`, the migration body without its own `BEGIN`/`COMMIT`, the sweep, `ROLLBACK`). That gives both numbers without migrating a shared database. Record them in `research/`.
   **This issue does not migrate the database.** The migration file carries its own `BEGIN;` and `COMMIT;`, and left in place that `COMMIT;` commits the outer transaction, migrating the shared database for everyone. Strip both. The `grep -nE '^(BEGIN|COMMIT|ROLLBACK);' <body file>` check is necessary but not sufficient; see "From wet#127" above for what else to refuse and check. Migrating for real waits on the upstream review (NewGraphEnvironment/fwapg#41).
2. **Pin what the sweep finds as live-database tests**, skipped without a connection, as the package's other live tests are. Each one is shown to fail before the change and pass after.
3. **Gate on the database, without hiding a stale one.** Tests that need the new behaviour check the database has it: `pg_get_function_arguments('whse_basemapping.fwa_indexpoint'::regproc)` names `include_disconnected`. Where it doesn't, they skip and say which migration is missing. One test *fails* instead of skipping when an environment variable says the database should be current, so a stale database cannot turn the suite green.

Inputs for the sweep: the points `frs_point_snap()` is run on (PSCIS crossings, fish observations), the measures passed to `frs_point_locate()` and `frs_watershed_at_measure()`, and the starts given to `frs_cluster()`'s downstream trace. Change this together with `link::lnk_points_snap()` (NewGraphEnvironment/link#383), which fresh's snap mirrors and which carries the same lowest-id tie.




## Measured at the gate (2026-10-27, m4)

### The fwapg change, verbatim

`db/migrations/202610240132__indexpoint_tiebreak.sql` on
`NewGraphEnvironment/fwapg` branch `41-fwa-indexpoint-one-tie-rule-and-measure` (PR fwapg#43,
tip `b088b43`). `fwa_indexpoint`'s per-stream pick:

```sql
-- a point nearest the vertex two segments share is equally near both: take
-- the one starting there, the segment its measure falls on
ORDER BY blue_line_key, distance_to_stream, downstream_route_measure DESC, linear_feature_id
```

and its outer order is `ORDER BY b.distance_to_stream asc, linear_feature_id` on the *unrounded*
distance (the emitted column is rounded to 3 decimals). The measure becomes
`ST_M(ST_LineInterpolatePoint(stream_geom, ST_LineLocatePoint(stream_geom, ST_ClosestPoint(...))))`.
The migration creates/replaces `fwa_indexpoint` (both schemas), `fwa_locatealong`,
`fwa_upstreamtrace`, `fwa_downstreamtrace`, `fwa_watershedhex`, `fwa_watershedstream`,
`fwa_upstreambordercrossings`, `fwa_slicewatershedatpoint`. It does **not** touch
`fwa_watershedatmeasure` — that is the other pending migration,
`202610131654__watershedatmeasure_drop_exbc` (895 lines, upstream smnorris/fwapg#200, merged).

### Database state (both the shared m1 instance and m4's local docker)

| | m1 `100.101.213.2:5432/fwapg` | m4 `localhost:5432/fwapg` (docker `fresh-db`) |
|---|---|---|
| `fwa_indexpoint` args | `point geometry, tolerance double precision DEFAULT 5000, num_features integer DEFAULT 1` | same |
| `exbc` in `fwa_watershedatmeasure` | present | present |
| `fwapg.db_version` | does not exist | does not exist |
| `fwa_stream_networks_sp` | — | 4,907,441 segments |
| extensions | includes `dblink` | — |

So both are behind both migrations, and m4's local copy is a faithful stand-in. `.Renviron` points
`PG*` at m1, so the sweep must set `PGHOST=localhost` explicitly (R's user `.Renviron` overrides
shell env — use `Sys.setenv()` inside R or `Rscript --no-environ`).

### Call costs, m4 local docker

| call | warm | cold |
|---|---|---|
| `fwa_locatealong(356360570, 14041)` | 70 ms | — |
| `fwa_downstreamtrace(356360570, 14041)` | 1.54 s | — |
| `fwa_watershedatmeasure(356360570, 14041)` | 2.51 s | 6.30 s |

`frs_watershed_at_measure()` makes two `fwa_watershedatmeasure()` calls per position.

### Sweep input sizes, m4 local docker

`whse_fish.pscis_assessment_svw` 19,905 · `whse_fish.fiss_fish_obsrvtn_pnt_sp` 378,971 ·
`bcfishobs.fiss_fish_obsrvtn_events` 0 rows on this host (so fish observations come from
`whse_fish`, not the bcfishobs events table).

### The KNN plan survives the new tie key

`EXPLAIN (COSTS OFF)` of the lateral with
`ORDER BY s.geom <-> p.geom, s.downstream_route_measure DESC, s.linear_feature_id`, 100 m, LIMIT 5:

```
Limit -> Result -> Incremental Sort
      Sort Key: ((s_1.geom <-> '…'::geometry)), s_1.downstream_route_measure DESC, s_1.linear_feature_id
      Presorted Key: ((s_1.geom <-> '…'::geometry))
  -> Index Scan using fwa_streamnetworks_geom_idx on fwa_stream_networks_sp s_1
        Order By: (geom <-> '…'::geometry)
```

The index-ordered nearest-neighbour scan that `R/frs_point_snap.R:381-382` protects is intact; the
secondary keys resolve inside each presorted distance group.

### Why the clamped measure cannot be the ordering key

`c.downstream_route_measure` is `CEIL(GREATEST(ds, FLOOR(LEAST(us, m))))`. For two segments sharing
a vertex at raw measure `m`: the lower gives `FLOOR(m)`, the upper gives `CEIL(ds_upper) = CEIL(m)`
— 1 m apart when `m` is fractional, **equal** when the vertex sits on a whole metre, where the
order would fall through to `linear_feature_id` and reinstate the old rule. Hence the raw
`downstream_route_measure` is carried out of the lateral under an internal alias.

### wet#127 is the template

Branch `origin/127-wet-station-snap-measure-the-effect-of-f` (PR wet#132, open):
`R/wet_pg_trial.R`, `scripts/station_snap_sweep.R`, `research/station_snap.md`,
`tests/testthat/helper-fwapg.R`, `tests/testthat/test-wet_pg_trial.R`,
`tests/testthat/test-wet_station_snap.R`. Load-bearing details to carry over:

- The rollback is `withr::defer(DBI::dbRollback(conn), envir = env)` — callers wrapping the helper
  must pass `env = env`, or the rollback fires before the test body (a recorded wet bug).
- `pg_current_xact_id()` before the body (forces assignment) and
  `pg_current_xact_id_if_assigned()` after (reports without forcing).
- `gregexpr()` only *warns* and returns `-1` past PCRE's backtracking limit, which reads as "no
  transaction control" — so a warning is a refusal, and the comment grammar is possessive/atomic
  with a recursive DEFINE for nested `/* */`.
- `\z`, not `$`, under `(?im)`, so a plpgsql bare `BEGIN` line is not refused while an unterminated
  last statement is.
- Non-undoable calls refused: `\b(dblink\w*|pg_background\w*|program|setval|lo_export|pg_file_write)\b`.
- Only `ABORT`, `COMMIT`, `END`, `ROLLBACK` and `PREPARE TRANSACTION` actually end a transaction
  block (checked against PostgreSQL 17's `TransactionStmt` grammar); `COMMIT` inside `DO`/`CALL`
  raises instead.
- Known, documented gaps: `nextval()`, non-transactional server-side effects, and a migration that
  commits without a transaction statement.
- There is **no** note in wet about where one shared copy should live — that decision is this
  issue's, and it was taken at the gate (exported from fresh as `frs_migration_trial()`).
