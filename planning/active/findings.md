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

## Re-measuring the issue's three gauge points through fresh's own snap (O2, 2026-10-27, m4)

The issue's three points were measured through `fwa_indexpoint()`, which returns one candidate
per `blue_line_key`. `frs_point_snap()` returns candidates **per segment** and applies its own
guards, so the ids had to be re-measured before they could be written as assertions. Measured on
the local docker fwapg with `main`'s SQL.

| gauge | result through fresh's snap at tolerance 150 |
|---|---|
| **08KD006** | the issue's tie is real and **exact**: 703862843 and 703862887 are both `67.563693805068` m away, bit-identical, and nothing else is at that distance. But two segments of blue line **356302336** are nearer (9.4 m, 22.3 m), so the tie surfaces at `candidate_rank` 3 and 4 with `num_features = 5`, or at rank 1 with a `col_blk` hint of 356360570. |
| **07EA001** | does not reproduce. Blue line 359014591's nearest segment is **670.9 m** from the gauge — far outside any snapping tolerance. (Its own tie is real there: 207086967 and 207086752 are both 670.921 m away. But 207086752 is both the lower id **and** the segment starting at the shared vertex, so the old rule and the new rule agree on it — it cannot be a red/green pin either way.) |
| **07FA007** | a head case (O1), moved to Phase 4. Its ranks 2 and 3 are an exact tie at `16.327150173041` m, but **across two blue lines** (223047489 on 359001991, 223047586 on 359570983), not two segments of one. |

So the Phase 2 pin is **08KD006**, and only 08KD006.

- `703862843`: ds 13543.88, us 14040.00493, localcode `100.594120.061391`, length 496.13 m
- `703862887`: ds 14040.01, us 14162.33033, localcode `100.594120.063640`, length 122.32 m
- clamped measures at the tie: **14040** on the lower segment, **14041** on the upper — the 1 m
  the research note describes, and the localcodes differ because a tributary joins at that vertex.
- `main`'s rule (lowest `linear_feature_id`) picks **703862843** / 14040 / `…061391`.
- the new rule (higher raw `downstream_route_measure`) picks **703862887** / 14041 / `…063640`.

### A point placed *on* the shared vertex is not a deterministic pin

The vertex is at `POINT(-122.37407465666284 54.0456823671828)`. Constructing the pin there looked
stronger — distance 0 to both segments, so no hint and no `num_features > 1` needed — and it is
wrong twice over:

1. It is a **three-way** tie. The tributary's own segment 703862850 (blue line 356302336,
   ds 0, edge type 1450) also touches that vertex, and it is not excluded by `.frs_snap_guards()`.
2. `ST_Distance` is not bit-equal there. `frs_point_snap()` reports `1.197678e-09`, and `main`'s
   SQL already returns **703862887** for that point — the right answer for the wrong reason,
   decided by floating-point noise rather than by the tie rule.

An exact tie is one measured off the segments, not one constructed at the vertex.

### fresh's rule is positional only within one blue line

fwapg's `ORDER BY blue_line_key, distance_to_stream, downstream_route_measure DESC,
linear_feature_id` partitions by `blue_line_key` before it compares measures, because
`fwa_indexpoint()` takes one candidate per stream. fresh orders candidates per segment, nearest
first, so it cannot lead on `blue_line_key` without breaking distance ordering. Where a tie falls
across two different blue lines (07FA007's ranks 2 and 3), fresh compares measures that belong to
different streams: deterministic, but no more positional than the lowest-id rule was. Record it in
the research note rather than pretending the two rules coincide.

## The head case, constructed by query (O1, measured 2026-10-27, m4)

The sweep could not be relied on to find one, and it cannot: `whole_metre_top = 0` — **no**
candidate segment has an integer `upstream_route_measure`, so fresh's own clamped measure never
lands exactly on a stream's top. The pin has to be constructed.

**First attempt, wrong.** 246 candidate segments are shorter than a metre and contain no whole
metre, so `CEIL(GREATEST(ds, …))` lands past their own upstream end; **6** of those are also the
top segment of their blue line, so the measure is past the whole stream's head. `fwa_locatealong()`
resolves none of the six — and the migration does not fix them either (measured: 0 before, 0
after). Closing the range at the top only helps a measure *at* the top, not one *past* it.

**The pin: a measure exactly equal to a blue line's maximum `upstream_route_measure`.**
`ds <= m < us` cannot hold it; `ds <= m <= us` can. Measured on five blue lines sampled by
`ORDER BY md5(blue_line_key::text)`:

| call | before | after both migrations | rolled back |
|---|---|---|---|
| `fwa_locatealong` | 0 rows on all five | **3 of 5 resolve** (356194098 @ 2378.0308, 356225614 @ 517.2700, 359044951 @ 320.3324) | 0 rows again |
| `fwa_watershedatmeasure` | **errors**: `line_interpolate_point: 2nd arg isn't within [0,1]`, raised from `fwa_upstreambordercrossings` | no error, 0 rows | — |

The second row is B1's replacement pin, confirmed: the transition is **error → no error**, not a
placement, and it comes through `fwa_upstreambordercrossings`, which the tiebreak migration
rewrites — not through `fwa_watershedatmeasure`'s own segment pick, which has no top bound to
close.

Two of the five do not flip (356129923, 360447231), so a Phase 4 test must not assume any given
blue line exhibits the case: it guards on the before state being 0 and asserts the after state
resolves.

## What the smoke sweep measured (small samples, 2026-10-27)

A capped run (300 PSCIS, 200 observations, 500 crossings measures, 10 sampled expensive
positions → 1,010 snapped positions, 4,040 CSV measures, 153 expensive positions):

| state | csv locatealong misses | watershed misses | watershed errors |
|---|---|---|---|
| base | 34 | 9 | 50 |
| tiebreak only | 32 | 10 | 49 |
| both | 32 | 10 | 49 |

So the migration is measurable on fresh's inputs even at this size: two CSV measures that
`fwa_locatealong()` missed now resolve, and one position that **errored** now does not. Ties in
the snap at this sample: 45 tied groups over 300 PSCIS and 27 over 200 observations — and most are
**across** streams (39 of 45, 23 of 27), not within one, so the positional tie is the minority
case. The full run replaces these numbers.

## Why a measure at a stream's head could never be placed (measured 2026-10-27)

The installed `fwa_locatealong()` compares bounds **rounded to 4 decimals**:

```sql
AND round(s.downstream_route_measure::numeric, 4) <= round(v_measure::numeric, 4)
AND round(s.upstream_route_measure::numeric, 4)  >  round(v_measure::numeric, 4)
```

So a measure at a stream's top can never be placed — `round(us, 4) > round(us, 4)` is false by
construction, whatever the range's openness. That is a crisper statement of the case than "the
range is half-open", and it is checkable on any database with the same query whichever version of
the function is installed, which is what the Phase 4 guard uses.

**How common:** of 400 blue lines sampled by `ORDER BY md5(blue_line_key::text)`, their own top
measure resolves on **2** before the migration and **218** after — 216 flip. The head case is the
common case, not a rarity.

**A precision limit in fresh, worth knowing.** `frs_point_locate()` and
`frs_watershed_at_measure()` interpolate the measure with `sprintf("%s", m)`, which is
`as.character()` and carries 15 significant digits. For **185 of those 400** streams that rounds
the top measure *up*, outside even the closed range, so fresh cannot express that boundary exactly
and does not benefit from the migration there. Not changed here — it is a separate decision
(`%.17g` would round-trip) and `whole_metre_top = 0` means fresh's own clamped measures never land
on a top anyway. The Phase 4 pin names a stream whose top survives the rounding.

## The full sweep (2026-10-27, m4 local docker, ~47 min)

49,725 snapped positions (all 19,905 PSCIS + 5,000 observation points at tolerance 150,
`num_features = 5`), 23,540 CSV measures, 970 expensive positions.

| state | locatealong misses (49,725 positions) | CSV locatealong misses (23,540) | watershed misses (970) | watershed errors |
|---|---|---|---|---|
| base | **0** | 42 | 85 | 294 |
| tiebreak only | **0** | 38 | 86 | 293 |
| both | **0** | 38 | 86 | 293 |

- **Zero** of fresh's own 49,725 snapped positions fail to resolve, in any state. fresh's clamped
  measure never lands on a stream's top (`whole_metre_top = 0`), so the head case the migration
  fixes is not reachable through `frs_point_snap()` → `frs_point_locate()`. It is reachable when a
  caller passes a segment's own upstream measure, which is what the Phase 4 pin does.
- **4 CSV measures now resolve** that did not: 2 from `wsg_outlet.csv` (356363393 @ 322.567,
  360880826 @ 2100.018) and 2 from `crossings.csv` (356355973 @ 4494.620, 360862508 @ 10821.825).
- **1 position stops erroring**: 359434058 @ 159 — the `line_interpolate_point: 2nd arg isn't
  within [0,1]` transition, which is the Phase 4 pin.
- **Every change belongs to `202610240132__indexpoint_tiebreak`.** The `drop_exbc` migration moves
  nothing on these paths.
- **A pre-existing fwapg bug the migration does not fix:** 293 of 970 positions (30%) error with
  `more than one row returned by a subquery used as an expression` in **all three** states. Worth
  reporting upstream; it is also why the expensive calls are slow, since a failed chunk falls back
  to running its positions one at a time.
- **Ties, exhaustive on the base side:** 2,536 tied groups over the PSCIS positions (301 within one
  stream, 2,235 across streams) and 927 over the observation sample (139 within, 788 across). So
  only about **12%** of ties are the within-one-stream kind the positional rule is about.
