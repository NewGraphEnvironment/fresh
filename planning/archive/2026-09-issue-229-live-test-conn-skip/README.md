## Outcome
`test-frs_network_features-live.R` gated on `PG_PASS_SHARE` being set, a stand-in for "the tunnel is reachable". With the credential set but the tunnel down, all three tests errored instead of skipping. Added a shared `skip_if_no_conn(connect = frs_db_conn)` to `tests/testthat/helper-db.R`. It tries a real connect plus `SELECT 1` and skips with the error text on any failure. The live file now calls it at top level with its own `bcfp_conn`, after `skip_on_cran()` and `skip_on_ci()`. Accepted tradeoff: any connection error skips, including bad credentials or a broken connector. The helper comment and CLAUDE.md say so. A sweep of `tests/testthat/` found no other test that connects outside a skip gate.

## Measurement
Live file with `PG_PASS_SHARE` set and the tunnel down (`NOT_CRAN=true`): main gave `FAIL 3`, the branch gives `SKIP 1` with reason "Connection refused". Full suite on the branch: `FAIL 0 | WARN 0 | SKIP 3 | PASS 1148`. The tunnel-up path was not exercised because the tunnel was down on the dev host.

Closed by: commit 7e37d66 / PR (see branch 229-live-integration-tests-error-when-the-da)
