# Drop whatever this run left under its table prefix in `working` (#279), and
# say which tables those were: each one is a test that skipped its teardown.
withr::defer({
  conn <- tryCatch(frs_db_conn(), error = function(e) NULL)
  if (!is.null(conn)) {
    left <- tryCatch(frs_test_sweep(conn), error = function(e) {
      message("per-run table sweep failed: ", conditionMessage(e))
      character()
    })
    DBI::dbDisconnect(conn)
    if (length(left)) {
      message("tests left ", length(left), " table(s) under ", frs_test_run_id,
              "_ in working, now dropped: ", paste(left, collapse = ", "))
    }
  }
}, testthat::teardown_env())
