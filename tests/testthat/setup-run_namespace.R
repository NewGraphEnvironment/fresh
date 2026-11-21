# Drop whatever this run left under its table prefix in `working` (#279), and
# say which tables those were: each one is a test that skipped its teardown.
# Through frs_db_conn() only: no test on the FRESH_PG* local_fwapg()
# connection writes to `working`. One that does would need sweeping there too.
#
# A run that is killed (a timeout, Ctrl-C, a stopped mutation sweep) never
# reaches this, and its names are never reused, so its tables stay. The
# CLAUDE.md testing section has the query that finds them.
withr::defer({
  conn <- tryCatch(frs_db_conn(), error = function(e) NULL)
  if (!is.null(conn)) {
    left <- tryCatch(frs_test_sweep(conn), error = function(e) {
      message("per-run table sweep failed: ", conditionMessage(e))
      character()
    })
    DBI::dbDisconnect(conn)
    if (length(left)) {
      message("tests left ", length(left), " table(s) named for run ",
              frs_test_run_id, " in the working schema and they were dropped: ",
              paste(left, collapse = ", "))
    }
  }
}, testthat::teardown_env())
