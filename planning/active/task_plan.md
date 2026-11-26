# Task: Backlog move 7: docker image and loader rebuild (#324)

**If we do it:** a local fwapg can be rebuilt against current fwapg, on a GEOS that answers point-on-boundary correctly. **If we never do:** no new local database can be built, and derived tables keep GEOS 3.9.0's wrong answers.

Members: #253, #68, #304, #306, #302. Open PRs folded: #254 (merged into this branch), #252 (closed, folded host-neutral).

## Context

`docker/` can no longer build a local fwapg. `load.sh` calls fwapg's removed `db/create.sh` (#253, with #68's workaround). The image `imresamu/postgis:17-3.5-bullseye` ships GEOS 3.9.0, which says a point on a polygon's boundary does not intersect it (#304). That drops 18 streams from `fwa_streams_watersheds_lut` in BULK and ADMS, and it may also make polygon simplification differ between calls (#306). The header counts in `tests/testthat/test-frs_network_features-local.R` were never reproduced (#302). One full rebuild on a new image verifies all five. Open PR #254 has the loader fix, but it is stale: fwapg now ships three migrations newer than `schema.sql`, so `migrate.sh` must run. Open PR #252 adds host names to `docker/tuning.md` in this public repo.

What exploration found:
- Upstream fwapg builds on `postgis/postgis:16-3.5` (bookworm, GEOS 3.11). Its CI runs `schema.sql` then `db/migrate.sh`. Migrations on fwapg `newgraph`: `202610131654` (drop exbc), `202610240132` (indexpoint tiebreak), `202611131236` (named streams). `schema.sql` dates from 2026-04-17.
- The fork's `newgraph` `load.sh` adds PCIC, which PR #254 loaded and compared. The local `~/Projects/repo/fwapg` checkout is 55 commits behind `origin/newgraph`, so the build runs from a detached worktree.
- The live `fresh-db` holds 305 GB: link's outputs, `pcic` and `discharge` on top of the ~40 GB fwapg load. It cannot be replaced by a rebuild. 225 GB of disk is free, enough for a second ~40–60 GB instance.
- `container_name: fresh-db`, port 5432 and `./postgres-data` are fixed in compose, and compose 2.15.1 has no `!override`, so an override file cannot move the port. A second instance needs env defaults in the base file.
- The lut Parquet on fresh-bc is published by another repo's cloud-env, not by fresh.
- Moves 1 and 2 have merged (#327, #331). The backlog's "leave `R/utils.R` and the `test-frs_near_river.R` comment to moves 1 and 2" no longer applies.

## Decided at the gate

Owner, 2026-11-24, by AskUserQuestion at the plan gate (the image after a follow-up: the owner asked why not trixie; answered that upstream fwapg builds on PostGIS 3.5 / GEOS 3.11, then chose to probe both).

1. **Live fresh-db stays on bullseye.** A filed follow-up issue swaps it. This PR proves the image with a full rebuild in a second container.
2. **Image: trixie (`17-3.6.1-trixie`), revised 2026-11-24.** First decided "probe both, bookworm unless it fails", on my claim that upstream fwapg builds on bookworm / GEOS 3.11. The amd64 probe showed upstream's `postgis/postgis:16-3.5` is bullseye / PostGIS 3.5.2 / GEOS 3.9.0; told, the owner chose trixie and a restarted load. Original wording: Run the #304, #306 and vertical-line probes on `17-3.5.3-bookworm` and `17-3.6.1-trixie` before the load. Pin bookworm, which matches upstream's tested stack, unless a probe fails on bookworm and passes on trixie.
3. **Close PR #252, fold it in host-neutral.** Take its `.gitignore` line, and rewrite the override paragraph without hosts or private repos. Also scrub the existing host names and tunnel port in `tuning.md` and `docker/README.md`.
4. **Merge PR #254's branch into this branch**, keeping its commits, logs and archive. `migrate.sh` goes on top. This PR carries Fixes #253, #68.

Mechanism decided in the plan:
- Compose takes `FRESH_DB_CONTAINER`, `FRESH_DB_PORT`, `FRESH_DB_DATA` and `FRESH_LOADER_CONTAINER`, with defaults equal to today's values. The second instance runs under `-p fresh-rebuild` with a memory-sized `command:` override kept in the scratchpad.
- The image is pinned to an exact tag, never a floating one.
- #306's outcome rule: if polygon simplification repeats on the pinned GEOS, a doc note naming both versions closes #306. If it does not, the doc note lands and #306 stays open, its body updated with the measurement, for the next sweep.
- The link check is mechanical: the parsed, non-comment R code is identical between main and branch. `docker/` and roxygen text change no link output.

## Phase 1: Loader fix (#253, #68) on current fwapg
- [x] `git merge origin/253-docker-load-sh-calls-fwapg-s-db-create-s` into this branch
- [x] `docker/load.sh` stage 1: after `schema.sql`, run `db/migrate.sh` from the copy (`DATABASE_URL` set), replacing the "no migrations yet" comment; stop on failure
- [x] `docker/README.md` stage-1 row: schema.sql, migrations, search_path
- [x] `bash -n docker/load.sh`

## Phase 2: Image probes and a second instance beside the first (#304)
- [x] Pull both candidate images. On each, record `postgis_full_version()` and run: #304's three boundary pairs (geometries copied as WKB from live), #306's Tahtsa Reach `ST_SimplifyPreserveTopology(geom, 100)` 20× in one session, and the vertical x = 1000 line-box intersection. Log the results to `data-raw/logs/docker_rebuild_324/image_probe.txt` — **done, and it disproved #304's premise:** the boundary case is false on every PostGIS 3.4–3.6 × GEOS 3.9–3.13 tried (findings.md, "Image probe"). Bookworm chosen by the gate rule. Correction: #304 is not fixed by the image; it stays open, body corrected, fix filed as a fwapg fork issue (Phase 5)
- [x] Pin the chosen exact tag in `docker/docker-compose.yml`. Add the env defaults above, and a header note: recreating an existing bullseye data dir on this image changes GEOS answers and the glibc collation version, see the follow-up issue
- [x] `docker/.gitignore`: `postgres-data*/`, `docker-compose.override.yml*`
- [ ] `docker/tuning.md` and `docker/README.md`: host-neutral override paragraph, a section on a second instance, drop host names and the tunnel port; close PR #252 with a comment pointing here

## Phase 3: Full rebuild on an empty volume
- [x] Detached worktree of fwapg at `origin/newgraph`; record its sha — 137fd69 (`stamp.txt`)
- [x] `-p fresh-rebuild`, port 5433, empty `docker/postgres-data-rebuild/`; loader in the background with its log, launch stamp and done marker under `data-raw/logs/docker_rebuild_324/`, and a disk watchdog that stops it at 30 GB free
- [x] Post-conditions against live (adapting #254's `postconditions.sh`): key table counts, `search_path`, `fwapg.db_version` = `202611131236`, `fwa_downstreamtrace`, `fwa_upstream()`, `fwa_watershedatmeasure()` at a non-lake point
- [x] `FRESH_PG*` at 5433: `FRESH_FWAPG_CURRENT=true` `test-frs_fwapg_gate.R` passes; full `devtools::test()` with `PG*` at 5433 — corrected below: the gate fails as expected; the full suite matches live test by test

## Phase 4: Measurements and the member fixes
- [x] (superseded by the correction below) #304: the 18 named streams have lut rows; BULK+ADMS count recorded. Grep fwapg `load/*.sql` for boundary-sensitive predicates and list the tables for the follow-up issue
- [x] #306: the repeat probe on the rebuild (20× SQL, 20× `frs_lake_fetch(aoi =, simplify_m = 100)` on one connection). Doc note per the outcome rule in `R/frs_lake_fetch.R`, `R/frs_wetland_fetch.R`, `R/frs_watershed_at_measure.R`; revise `research/fwa_fetch_determinism.md`
- [x] #302: re-derive both pair counts with the test's own fixture and query on the full-province rebuild (`data-raw/network_features_answer_pairs.R`, log beside it). Correct the header and `research/fwa_downstream_walk.md` (line 46) — header right for its population; #302's numbers are the whole fixture's (findings). Re-run on the rebuild in Phase 3 post-conditions
- [x] Vertical-line probe result into the `test-frs_near_river.R` comment and `research/fwa_downstream_walk.md` "GEOS"
- [x] `research/fwapg_channel_width.md`: re-check its BULK counts that depend on the lut
- [x] `devtools::document()`, `lintr` per file against main — 2026-11-25: main 1,703, branch 1,706; the 3 new were indentation in `data-raw/network_features_answer_pairs.R`, fixed (output reproduced on live, header lines aside)

## Phase 5: Follow-ups and close-out
- [x] File: move the live local fwapg onto the new image (recreate over its data dir, refresh the collation version and reindex, rebuild the lut and the listed tables, measure link's outputs before and after), naming move 7 — #335
- [x] File the lut Parquet re-export with its publisher (private repo), and the `--bcfishobs` stage-4 issue from #254's draft, each naming move 7 — rtj#446 (re-export, after fwapg#60), #334 (bcfishobs stage 4), plus NewGraphEnvironment/fwapg#60 (the lut predicate, #304's real fix)
- [x] Link check: parse-compare `R/` between main and branch — 2026-11-25: 46 files each side, 0 whose parsed code differs, positive control detected (re-run in `/code-check branch` if `R/` moves again)
- [x] Edit #302, #304, #306 bodies with what was measured

## Corrections after the plan review and the probes (2026-11-24)

The review is `planning/active/review-plan.md`; these replace the plan text they name.
- [x] Relaunch the full load on trixie (attempt 3: 2026-11-26 00:08:37Z to 02:50:24Z, exit 0): `bash data-raw/logs/docker_rebuild_324/run.sh ~/Projects/repo/fwapg-324` from the repo root, in the background (needs the commit of the trixie compose first). run.sh now names the loader (`run --name fresh-loader-rebuild`) so its watchdog can stop it (review B1), and records the fwapg dir by basename (privacy). Attempts 1 (cold-start race) and 2 (bookworm, stopped for the switch) are kept under `data-raw/logs/docker_rebuild_324/attempt*`
- [x] Phase 3 gate test: with `FRESH_FWAPG_CURRENT=true` it FAILS on this rebuild, as expected (review B2): fwapg newgraph's `202610240132__indexpoint_tiebreak.sql` is upstream's 3-argument version, and fresh's gate keys on `include_disconnected` from fwapg#41's rework, never merged. Run the gate test without CURRENT and record it; file a fresh issue to re-key the gate and CLAUDE.md's `FRESH_FWAPG_TRIAL` example
- [x] Post-conditions: say that `fwapg.db_version` 202611131236 does not mean `fwa_named_streams` is current: migration 3 is a data migration run before `load.sh`, which rebuilds the table with the old SQL (review G1). fresh does not read the table. File a fwapg fork issue
- [x] Tests against 5433: `~/.Renviron` sets `PG*` to another host, so `Sys.setenv()` all five inside R before `load_all()`, prove the target with `SELECT tag FROM fwapg.db_version` (live has no such table), and compare against a run on live rather than reading a plain pass (review G4)
- [x] #304 (replaces Phase 4's "the 18 named streams have lut rows"): the rebuild's lut still misses them, because the deciding test is architecture-dependent (arm64 false, amd64 true, same PostGIS/GEOS), not the image. Record the rebuild's BULK+ADMS count; fix is NewGraphEnvironment/fwapg#60. #304 body already corrected (2026-11-24)
- [x] #306 doc note: repeat-variation was seen on arm64 GEOS 3.9.0 (amd64 3.9.0 repeated); GEOS 3.11 gives 556 points, 3.12+ 514, each repeating, so a simplified layer repeats within one GEOS version only (review S2). Edit #335 to re-run the #306 probe after its swap
- [x] Edit #335 for trixie: a PostGIS minor upgrade (`ALTER EXTENSION postgis UPDATE`) and the `FRESH_DB_IMAGE` hold in `docker/.env`
- [ ] Close PR #252 without quoting its title (it names hosts and a private repo)

## Owed at the end (reported, done after merge)
- [ ] Remove the `fresh-rebuild` instance, `docker/postgres-data-rebuild/` and the fwapg worktree, unless the live-swap issue wants them kept
- [ ] Confirm PR #254 shows merged and PR #252 is closed
- [ ] Before anyone runs `docker compose up -d db` in the main fresh checkout after the merge: write `docker/.env` there with `FRESH_DB_IMAGE=imresamu/postgis:17-3.5-bullseye`, so the live database is not moved onto trixie by accident (review G3; undone by #335)

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (`/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification (corrected 2026-11-24: #304's case is architecture-dependent, so no image answers it true on arm64): the image probe log shows the pinned image fixing GEOS 3.9.0's vertical-line case and repeating the simplify. The loader exits 0 on an empty volume, with its done marker newer than the launch stamp. Post-conditions match live, with differences explained (FWA snapshot drift, migrations live lacks). The gate test's expected failure under `FRESH_FWAPG_CURRENT=true` is recorded, and the full suite on the rebuild is compared with a run on live. The #302 counts come from a committed script that a second run reproduces. The R parse-compare shows no executable change.

