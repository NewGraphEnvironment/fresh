# Progress: frs_db_conn() sets no timeout (#305)

## Session 2026-11-20

- Plan-mode exploration; phases approved by user
- Created branch `305-frs-db-conn-sets-no-timeout-so-a-silent` off origin/main
- Scaffolded PWF baseline from issue #305 with approved phases
- Next: start Phase 1
- Phase 1: tests for connect_timeout resolution, validation, idle bounds and `...`, the dbConnect args under all three variable groups (mockery stub), `.frs_conn_params()`, and a silent local listener through `skip_if_no_conn()`. Red as expected
