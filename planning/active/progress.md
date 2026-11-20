# Progress: frs_db_conn() sets no timeout (#305)

## Session 2026-11-20

- Plan-mode exploration; phases approved by user
- Created branch `305-frs-db-conn-sets-no-timeout-so-a-silent` off origin/main
- Scaffolded PWF baseline from issue #305 with approved phases
- Next: start Phase 1
- Phase 1: tests for connect_timeout resolution, validation, idle bounds and `...`, the dbConnect args under all three variable groups (mockery stub), `.frs_conn_params()`, and a silent local listener through `skip_if_no_conn()`. Red as expected
- Plan review back (spawned 15:46Z): 9 findings, `review-305.md`. Finding 2 reproduced live (`invalid integer value "3e+05"`) and fixed
- Phase 2: `.frs_conn_bounds()`, `frs_db_conn(connect_timeout, ...)`, `.frs_conn_params()` carries bounds, Timeouts docs. `test(filter = "frs_db_conn")`: 63 pass, 0 fail
- Phase 3: `bcfp_conn()` and `frs_fwapg_conn()` carry the bounds; CLAUDE.md says a silent host skips, with the measured cost (199 gate calls, about 35 min at the default)
