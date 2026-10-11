# Progress — docker/load.sh calls fwapg's db/create.sh, which fwapg removed (#253)

## Session 2026-10-11

- Plan-mode exploration — phases approved by user (verification: scratch DB on M1)
- Created branch `253-docker-load-sh-calls-fwapg-s-db-create-s` off main
- Scaffolded PWF baseline from issue #253 with approved phases
- Next: start Phase 1
- Phase 1: load.sh stage 1 runs `db/schema.sql` and sets the database search_path; #68 workaround dropped; schema.sql layout guard; README row. `bash -n` clean.
- Plan review (Plan agent) folded in (`80d964f`); search_path comment corrected (`92cb8e3`)
- Phase 2 attempt 1 (fwapg `f9718cb`, stale): stage 1 passed, stopped by hand 2026-10-11T23:34Z; archived under `data-raw/logs/docker_load_253/attempt1_f9718cb/`
- Phase 2 attempt 2 (fwapg worktree at `origin/newgraph` `b010209`) launched 2026-10-11T23:35Z into `fwapg_253`; stage 1 passed. Object-store download ~0.38 MB/s measured from the host too, so stage 2 is network-bound (hours)
- `/code-check branch` round 1 Clean; rounds 2 and 3 spawned 23:40Z (no fixes between rounds, so run side by side)
- `data-raw/logs/docker_load_253/postconditions.sh` written and dry-run on live `fwapg` (5 s)
