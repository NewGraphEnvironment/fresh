test_that("frs_db_query returns sf from spatial query", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  result <- frs_db_query(conn,
    "SELECT * FROM whse_basemapping.fwa_lakes_poly LIMIT 3"
  )
  expect_s3_class(result, "sf")
  expect_true(nrow(result) > 0)
})
