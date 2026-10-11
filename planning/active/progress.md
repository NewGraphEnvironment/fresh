# Progress — docker/load.sh calls fwapg's db/create.sh, which fwapg removed (#253)

## Session 2026-10-11

- Plan-mode exploration — phases approved by user (verification: scratch DB on M1)
- Created branch `253-docker-load-sh-calls-fwapg-s-db-create-s` off main
- Scaffolded PWF baseline from issue #253 with approved phases
- Next: start Phase 1
- Phase 1: load.sh stage 1 runs `db/schema.sql` and sets the database search_path; #68 workaround dropped; schema.sql layout guard; README row. `bash -n` clean.
