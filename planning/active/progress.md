# Progress — Backlog move 7: docker image and loader rebuild (#324)

## Session 2026-11-24

- Plan-mode exploration — phases approved by user
- Created branch `324-backlog-move-7-docker-image-and-loader-r` off origin/main
- Claimed #324 (in-flight) for the branch
- Scaffolded PWF baseline from issue #324 with approved phases
- Next: start Phase 1
- Phase 1: merged PR #254's branch (98b4dd0); load.sh stage 1 now sets search_path, then runs db/migrate.sh, and prints fwapg.db_version; README stage-1 row updated; `bash -n` clean
- Phase 2: image probe committed as `data-raw/docker_image_probe.sh` (log `data-raw/logs/docker_rebuild_324/image_probe.txt`). #304's boundary case is false on all five PostGIS/GEOS stacks, so the image does not fix it (plan correction). GEOS 3.9.0's vertical-line EMPTY and #306's repeat-varying simplify are fixed on every newer image. Pinned `17-3.5.3-bookworm`; compose takes FRESH_DB_CONTAINER / FRESH_DB_PORT / FRESH_DB_DATA / FRESH_LOADER_CONTAINER; .gitignore, tuning.md and README host-neutral (PR #252 folded; closed once this PR opens)
