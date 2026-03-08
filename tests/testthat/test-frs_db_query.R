test_that("frs_db_query returns sf from spatial query", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  result <- frs_db_query(
    "SELECT * FROM whse_basemapping.fwa_lakes_poly LIMIT 3"
  )
  expect_s3_class(result, "sf")
  expect_true(nrow(result) > 0)
})
