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
- Guard proof (throwaway worktree at 4b33a7e): with `connect_timeout` removed from `.frs_conn_bounds()`'s output, the silent-host test hung until GNU `timeout` killed it at 60 s (15:51:54 to 15:52:54Z, no result printed). Restored: passes in 5 s
- lintr, per file / linter / source line against a worktree of origin/main: one new `indentation_linter` hit, on the multi-line unnamed-`...` condition in `.frs_conn_bounds()`; fixed by naming the condition. The remaining `frs_db_conn.R` lint (`dbname = NULL,` indentation) is on main already
- Full suite on 4b33a7e (15:51 to 16:06Z): 854 tests, 0 failed, 0 errors, 6 skipped (fwapg migration trial unset, no bcfishpass schema, tunnel on 63333 refused). The tunnel test skipped at once, as a refusing host should
- Code-check round 1 (spawned 15:55Z): 1 finding, accepted. `tcp_user_timeout` default dropped (libpq < 12 refuses the keyword); docs say pass it through `...` on Linux. `test(filter = "frs_db_conn")`: 63 pass
- Code-check round 2 (spawned 16:07Z): 1 finding, accepted, not inside round 1 fix: `connect_timeout` above `.Machine$integer.max` passed the check and became NA; now refused, test added. 64 pass. `R CMD check --no-tests`: 0/0/0
