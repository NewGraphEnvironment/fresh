# Progress — Backlog move 7: docker image and loader rebuild (#324)

## Session 2026-11-24

- Plan-mode exploration — phases approved by user
- Created branch `324-backlog-move-7-docker-image-and-loader-r` off origin/main
- Claimed #324 (in-flight) for the branch
- Scaffolded PWF baseline from issue #324 with approved phases
- Next: start Phase 1
- Phase 1: merged PR #254's branch (98b4dd0); load.sh stage 1 now sets search_path, then runs db/migrate.sh, and prints fwapg.db_version; README stage-1 row updated; `bash -n` clean
