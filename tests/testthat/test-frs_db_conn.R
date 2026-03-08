test_that("frs_db_conn returns a DBI connection", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  conn <- frs_db_conn()
  expect_s4_class(conn, "PqConnection")
  DBI::dbDisconnect(conn)
})
