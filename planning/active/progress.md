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
- Filed follow-ups: #335 (move an existing local fwapg onto bookworm), #334 (bcfishobs stage 4, from #254's draft), NewGraphEnvironment/fwapg#60 (lut predicate), rtj#446 (Parquet re-export after fwapg#60). fwapg's load SQL has one spatial predicate, the lut's
