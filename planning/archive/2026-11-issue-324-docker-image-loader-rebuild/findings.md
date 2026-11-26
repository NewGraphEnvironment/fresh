# Findings — Backlog move 7: docker image and loader rebuild (#324)

## Issue context

**If we do it:** a local fwapg can be rebuilt against current fwapg, on a GEOS that answers point-on-boundary correctly. **If we never do:** no new local database can be built, and derived tables keep GEOS 3.9.0's wrong answers.

This is move 7 of `planning/backlog.md` (#315). Run `/planning-init <this issue>`: its batches are the scope, one phase per batch, one PR.

When the plan finds that a batch, or one of its members, is more than one PR's work, it carries the first piece and files each other piece as its own issue naming move 7, and leaves it out of `planning/backlog.md`: the next `/backlog-sweep` reads an issue the file does not name as unplaced, and folds it into a move other than this one.

## Batch 7: Docker image and loader rebuild

**Why here:** One full rebuild on a new image verifies all five: the loader fix (open PR #254, which closes #253 and #68), the GEOS move (#304), the simplify repeat probe (#306) and the re-derived test counts (#302). The open PR #252 also edits `docker/tuning.md`.

**Touches:** `docker/`, `research/fwa_fetch_determinism.md`, `research/fwapg_channel_width.md`, `research/fwa_downstream_walk.md`, `R/frs_lake_fetch.R`, `R/frs_wetland_fetch.R`, `R/frs_watershed_at_measure.R`, `tests/testthat/test-frs_network_features-local.R`

**To decide at the gate:**

- Move the image to a bookworm variant (an ops change).
- Refresh PR #254 against current fwapg, and refresh or close PR #252.
- If #306 takes the client-side simplify option, it leaves `.frs_geom_select()` in `R/utils.R` as it is (its polygon branch included): `R/utils.R` belongs to moves 1 and 2, which run beside this one, so removing that branch is a later issue.
- The image move also makes a GEOS 3.9.0 comment in `tests/testthat/test-frs_near_river.R` stale: leave it to move 1, which edits that file.

| issue | title |
|---|---|
| #253 | docker/load.sh calls fwapg's db/create.sh, which fwapg removed |
| #68 | Remove fwapg function workaround when `smnorris/fwapg#189` is fixed |
| #304 | docker image's GEOS 3.9.0 answers ST_Intersects false for a point on a polygon boundary |
| #306 | simplify_m on polygons can differ between calls on one database (PostGIS ST_SimplifyPreserveTopology, GEOS 3.9.0) |
| #302 | test-frs_network_features-local.R: the header's answer-pair counts do not reproduce |






## Exploration at the plan gate (2026-11-24)

- Live fresh-db: imresamu/postgis:17-3.5-bullseye, PostgreSQL 17.5, PostGIS 3.5.2, GEOS 3.9.0-CAPI-1.16.2, PROJ 7.2.1; 246 watershed groups; 305 GB; no fwapg.db_version table.
- Largest schemas in live: pcic 70 GB, discharge 45 GB, whse_basemapping 40 GB, fresh 27 GB, fresh_default 21 GB, fresh_default_minimal 19 GB.
- Disk 225 GB free of 3.7 TB; Docker VM 110 GiB, live fresh-db using 44 GiB; compose v2.15.1 (no `!override`).
- PR #254's run (October): fwapg load alone 40 GB peak, 5 h 52 min, network-bound.
- imresamu/postgis tags with amd64+arm64: 17-3.5.3-bookworm (2025-09-01), 17-3.6.1-trixie (2026-02-09).
- Upstream fwapg db image: postgis/postgis:16-3.5. CI test-migration.yml runs schema.sql then `cd db && ./migrate.sh`.
- The lut Parquet on fresh-bc was published on 2026-11-04 by another repo's cloud-env, not by fresh.

## Image probe (Phase 2, 2026-11-24) — `data-raw/logs/docker_rebuild_324/image_probe.txt`

Script: `data-raw/docker_image_probe.sh` (geometries copied as EWKB from the live fresh-db).

| image | PostGIS | GEOS | #304 boundary `ST_Intersects` | vertical line in box | simplify 100 m ×20 |
|---|---|---|---|---|---|
| live 17-3.5-bullseye | 3.5.2 | 3.9.0 | f, f, f | EMPTY (x = 1000 and 1500) | 556 ×3, 557 ×17 |
| 17-3.5.3-bookworm | 3.5.3 | 3.11.1 | f, f, f | the line | 556 ×20 |
| 17-3.6.1-trixie | 3.6.1 | 3.13.1 | f, f, f | the line | 514 ×20 |
| 16-3.4.3-bookworm | 3.4.3 | 3.11.1 | f, f, f | the line | 556 ×20 |
| 16-3.4-alpine3.20 | 3.4.3 | 3.12.2 | f, f, f | the line | 514 ×20 |

- **#304's diagnosis does not hold.** On these geometries `ST_Intersects`, `ST_Covers` and `ST_Contains` say false on every combination of PostGIS 3.4 to 3.6 and GEOS 3.9 to 3.13. `ST_Relate` gives `F0FFFF212` (the point's interior meets the boundary) and `ST_DWithin(p, geom, 0)` true on all of them. So the deciding code is not a GEOS version. #304's control (PostGIS 3.4.2, GEOS 3.12.1, "matches all 18") must have had different geometry, likely another FWA load: that database's tunnel was closed, so this is unmeasured. The image move does not recover the 18 lut rows. The fix belongs in fwapg's `load/fwa_streams_watersheds_lut.sql` (a predicate that agrees with `ST_Relate`, e.g. `ST_DWithin(p, geom, 0)` or `ST_Intersects(p, ST_Boundary(geom)) OR ST_Intersects(p, geom)`), as a fwapg fork issue. #304 stays open with its body corrected (plan correction, reported in the PR).
- **GEOS 3.9.0 defects the move does fix:** the line-box intersection returns `LINESTRING EMPTY` for a contained vertical line (at x = 1500 too, on this probe, unlike the near_river note's x = 1000 only); polygon simplification differs between calls in one session (#306). Every newer image answers both correctly and repeatably.
- **The simplifier's output changed between GEOS 3.11 and 3.12** (556 to 514 points on Tahtsa Reach at 100 m). Within one version it repeats.
- **Image chosen: `imresamu/postgis:17-3.5.3-bookworm`** by the gate rule (no probe fails on bookworm that passes on trixie). Digest `sha256:35fe7dceda62bfe7d2965b0ba78d915ff9f901b5e0466d633ecc58421b5b5210`. It matches upstream fwapg's `postgis/postgis:16-3.5` on PostGIS minor and GEOS.

## #302 answer pairs (2026-11-24) — `data-raw/logs/docker_rebuild_324/answer_pairs_5432.tsv`

`data-raw/network_features_answer_pairs.R` evaluates the test's own `nf_local_features()` (parsed from the test file) on the live full-province DB (246 groups, 4,907,441 segments):

| population | include_equivalents | pairs | ancestor only |
|---|---|---|---|
| every 25th (header's) | FALSE | 40,495 | 22 |
| every 25th | TRUE | 40,769 | 22 |
| whole fixture | FALSE | 50,417 | 22 |
| whole fixture | TRUE | 51,698 | 22 |

The header is right for its stated population. #302's probe numbers (50,417 / 51,698) are exactly the whole fixture's: the probe counted the NULL-coded SKGT copies too, and the six-group database was not the cause. Header now gives both populations and the producer.

## #304: the lut fix is a predicate in fwapg, measured on live (2026-11-24)

fwapg `load/fwa_streams_watersheds_lut.sql:45` (newgraph 137fd69) falls back to `ST_Intersects(ST_LineInterpolatePoint(s.geom, .5), w.geom)` for streams with no code match. On the live DB, replacing it with `ST_DWithin(..., w.geom, 0)` (same filters, no lut row yet):

- BULK 9, ADMS 9: exactly #304's 18 (40,486 + 18 = 40,504, its expected total); `ST_Intersects` adds 0 of them.
- Province-wide: 2,835 streams in 239 groups (2.9 s).

Where the midpoint sits on a shared edge `ST_DWithin` matches both polygons; the existing `ORDER BY ... ST_Distance(midpoint, ST_Centroid(w.geom))` already picks one, as it does for any multi-match.

## #304 is an architecture effect, and upstream's image is bullseye (2026-11-24, after the plan review)

`data-raw/logs/docker_rebuild_324/image_probe_amd64.txt`: upstream fwapg's own db base `postgis/postgis:16-3.5` is **amd64-only, Debian 11 bullseye, PostGIS 3.5.2, GEOS 3.9.0**: the same stack as the old local image. Run under emulation on the same EWKB:

- boundary: `ST_Intersects` **t**, `ST_Covers` **t** (arm64: f, f on every stack); `ST_Contains` f and `ST_Relate` `F0FFFF212` on both.
- vertical line: EMPTY (a GEOS 3.9.0 defect, both architectures).
- simplify 100 m ×20: 557 ×20 (arm64 GEOS 3.9.0: 556/557 mixed; arm64 GEOS 3.11+: repeats).
- the interpolated midpoints are bit-identical on arm64 and amd64 (EWKB hex compared), so the difference is in PostGIS's point-in-polygon test, not the point.

Consequences:
- #304's 18 missing lut rows (2,835 province-wide) are an artefact of building on arm64; an amd64 build has them. fwapg#60's `ST_DWithin(..., 0)` makes the lut the same on both. #304's control "PostgreSQL 16.15, PostGIS 3.4.2, GEOS 3.12.1" was presumably amd64.
- **The gate premise "upstream builds on bookworm / GEOS 3.11" was wrong** (I read `postgis/postgis:16-3.5` as bookworm without checking). Upstream matches the old image, on amd64. Taken back to the owner.
- #306's repeat-varying simplify was seen on arm64 GEOS 3.9.0; amd64 GEOS 3.9.0 repeated 20/20 here (one probe).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Rebuild attempt 1: `Connection refused` at stage 1 on an empty volume | compose healthcheck over TCP (`pg_isready -h 127.0.0.1`) + `start_period: 15m`; the socket check passed during the image's socket-only init |
| `docker_image_probe.sh` on an amd64 image: `the database system is shutting down` | wait for TCP and the extension, not the extension alone (init restarts after creating it) |
| `df -g` invalid (GNU df on this Mac) | `df -Pk` and divide |

## The trixie rebuild (attempt 3, 2026-11-26) — `data-raw/logs/docker_rebuild_324/`

Loader 00:08:37Z to 02:50:24Z (2 h 42 min), exit 0, done marker newer than the launch stamp, no ERROR lines, disk 218 to 159 GB free. fwapg 137fd69, `imresamu/postgis:17-3.6.1-trixie` (PostgreSQL 17.7, PostGIS 3.6.1, GEOS 3.13.1, PROJ 9.6.0, glibc collation 2.41).

`postconditions.txt` against live:
- Row counts equal on every table but `fwa_stream_networks_channel_width` (+12) and `fwa_stream_networks_order_parent` (-1), the two #254 also saw (fwapg's channel-width and order-parent outputs changed since live was loaded). `working.falls` 3,294, `working.crossings` 533,291 (live's fwapg database has neither; they were loaded elsewhere there).
- `fwapg.db_version` holds 0, 202610131654, 202610240132, 202611131236; `fwa_watershedatmeasure` no longer mentions `exbc` (live: does). `fwa_indexpoint` has the three-argument signature on both.
- `fwa_named_streams` 11,681 on both: the rebuild's comes from `load/fwa_named_streams.sql`, not the migration (review G1, NewGraphEnvironment/fwapg#61).
- Extensions: the rebuild lacks `dblink`, `pgcrypto`, `postgis_raster`, which live gained after its load; no test needed them (suite below).
- Functions: `fwa_watershedatmeasure` 231,944.7 ha (both schemas), lake branch 11.5, `fwa_downstreamtrace` 1,567 / 590,498 m, unqualified `fwa_upstream` 8,876: identical to live.
- #304 lut coverage: BULK + ADMS 40,486 of 40,504 (18 missing), province 4,538,224 of 4,541,064 (2,840 missing): identical to live, as the architecture finding predicts. fwapg#60's `ST_DWithin(..., 0)` recovered 2,835 of those 2,840 on live.

Gate test (`FRESH_FWAPG_CURRENT=true`, FRESH_PG* at 5433): FAIL 4, PASS 2. `fwa_locatealong()` at blue line 360447231's head returns 0 rows (the head case is present: its skip did not fire), so fwapg#41's measure rework is genuinely absent from newgraph, not just its `include_disconnected` signature. `fwa_watershedatmeasure()` at 359434058 / 159 no longer errors (its red side fails because the committed function is fixed). #336 rewritten with this. Without CURRENT: all three skip.

Full suite (`suite_run.R`, PG* and FRESH_PG* set inside R): live and rebuild both `FAIL 0 | WARN 18 | SKIP 7 | PASS 2938`; 897 tests each, 0 whose counts differ. Raw logs uncommitted (a skip reason names a local port); `suite_summary.txt` is the scrubbed record.

#306 (`simplify_repeat.R`, one connection, 20 calls): rebuild 514 ×20 one EWKB, `frs_lake_fetch(aoi =, simplify_m = 100)` one layer ×20; live (arm64 GEOS 3.9.0) 556 ×4 / 557 ×16, two layers (14 / 6). First try reported a 556- and a 557-point row with one md5: the planner inlined the subquery and evaluated the simplify twice; `OFFSET 0` fixed the probe.

#302 on the rebuild (`answer_pairs_5433.tsv`): identical to live.
