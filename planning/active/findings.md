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

## Errors Encountered

| Error | Resolution |
|-------|------------|
