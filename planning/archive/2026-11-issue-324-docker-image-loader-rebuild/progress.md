# Progress — Backlog move 7: docker image and loader rebuild (#324)

## Session 2026-11-24

- Plan-mode exploration — phases approved by user
- Created branch `324-backlog-move-7-docker-image-and-loader-r` off origin/main
- Claimed #324 (in-flight) for the branch
- Scaffolded PWF baseline from issue #324 with approved phases
- Next: start Phase 1
- Phase 1: merged PR #254's branch (98b4dd0); load.sh stage 1 now sets search_path, then runs db/migrate.sh, and prints fwapg.db_version; README stage-1 row updated; `bash -n` clean
- Phase 2: image probe committed as `data-raw/docker_image_probe.sh` (log `data-raw/logs/docker_rebuild_324/image_probe.txt`). #304's boundary case is false on all five PostGIS/GEOS stacks, so the image does not fix it (plan correction). GEOS 3.9.0's vertical-line EMPTY and #306's repeat-varying simplify are fixed on every newer image. Pinned `17-3.5.3-bookworm`; compose takes FRESH_DB_CONTAINER / FRESH_DB_PORT / FRESH_DB_DATA / FRESH_LOADER_CONTAINER; .gitignore, tuning.md and README host-neutral (PR #252 folded; closed once this PR opens)
- Stage 1 of the rebuild had a cold-start race (attempt 1, kept under `attempt1_coldstart/`): the compose healthcheck now checks over TCP with a 15 min start_period (06ca284). Attempt 2 launched 18:18Z; schema.sql + three migrations applied, db_version 202611131236
- #302 resolved on live: the header's counts are right for every-25th; #302's probe counted the whole fixture
- #304: measured on live that ST_DWithin(0) in fwapg's lut fallback recovers exactly the 18 (2,835 province-wide); filed NewGraphEnvironment/fwapg#60. BULK's one order-1 segment without channel-width inputs (research/fwapg_channel_width.md) is one of them
- Filed follow-ups: #335 (move an existing local fwapg onto bookworm), #334 (bcfishobs stage 4, from #254's draft), NewGraphEnvironment/fwapg#60 (lut predicate), an issue with the Parquet publisher, in its own private repo (re-export after fwapg#60). fwapg's load SQL has one spatial predicate, the lut's

## Session 2026-11-24 (continued) and 2026-11-25

- Plan review returned (review-plan.md): 2 blockers (watchdog no-op, gate test cannot pass on newgraph's migrations), gaps G1-G4; all reproduced
- amd64 probe (`image_probe_amd64.txt`): upstream's `postgis/postgis:16-3.5` is bullseye / GEOS 3.9.0; #304's boundary case is true there and false on arm64, same libraries, bit-identical midpoints. #304 is architecture, not image
- Owner switched the image to trixie; bookworm load (attempt 2) stopped at ~18:40Z and kept as `attempt2_bookworm_stopped/`
- Compose now `${FRESH_DB_IMAGE:-imresamu/postgis:17-3.6.1-trixie}`, `.env` gitignored; README second-instance (COMPOSE_PROJECT_NAME, run --name, FWAPG_DIR) and Image sections rewritten; run.sh watchdog fixed; home paths scrubbed from stamps
- Next: relaunch the trixie load (first box under "Corrections"), then Phase 3 post-conditions and tests on 5433

## Session 2026-11-25 (resumed 00:08Z, 2026-11-26 UTC)

- Merged origin/main (CLAUDE.md sync); RESUME-OK at 0ef9c98
- Trixie load (attempt 3) launched 2026-11-26T00:08:37Z: `run.sh ~/Projects/repo/fwapg-324`, fwapg 137fd69, image `17-3.6.1-trixie`; healthcheck passed, data stage running
- Filed #336 (fwapg gate keys on `include_disconnected`, which newgraph's migrations lack: review B2) and NewGraphEnvironment/fwapg#61 (`fwa_named_streams` stays on the pre-migration SQL after a fresh load: review G1, upstream-draft)
- Edited #335 for trixie: glibc 2.31 to 2.41 (measured in both images), PostGIS 3.5.2 to 3.6.1, remove the `FRESH_DB_IMAGE` hold, re-run the #306 probe after the move, #304 as architecture
- #306 doc note in `frs_lake_fetch()`, `frs_wetland_fetch()`, `frs_watershed_at_measure()`; `research/fwa_fetch_determinism.md` gains "Repeating within one database" from the image probes. The rebuild's own 20x probe is still owed (Phase 4)
- Link check: parse-compare of `R/` (each file's `parse(keep.source = FALSE)` deparsed) main vs branch: 0 of 46 files differ; a one-line control is detected. No R/ code, DESCRIPTION, NAMESPACE or inst/ change on the branch
- Baseline suite on live (00:16Z): FAIL 0 | SKIP 7 | PASS 2938
- Load done 02:50:24Z, exit 0. Post-conditions match live (differences explained in findings); gate test fails as expected and showed the head-case measure is truly absent on newgraph (#336 rewritten); suite on 5433 identical to live test by test; #306 repeats on the rebuild and not on live (#306 body updated, closes by the outcome rule); #302 counts identical on the rebuild
- Next: `/code-check branch`, close PR #252, archive, PR
- `/code-check branch`: 4 rounds (03:01Z to 03:36Z). R1 10 findings (second-instance recipe and image pin reach, research counts, GEOS ranges, probe platform); R2 3 (two inside R1's fixes: an unnamed override file, "either architecture"); R3 5 with enumerations of 25 docker invocations and 40 claims (second-instance shell vs the first's literal commands; claims wider than the sample); R4 re-walked 27 + 55, 4 above source, fixed. Verdict: enumeration
- Scrubbed a private repo's issue number from planning text; older archives on main still name it and a host (pre-existing, reported)
