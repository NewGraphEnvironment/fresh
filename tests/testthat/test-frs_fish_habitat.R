test_that("frs_fish_habitat returns sf with bcfishpass columns", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  habitat <- frs_fish_habitat(conn, watershed_group_code = "BULK", limit = 5)
  expect_s3_class(habitat, "sf")
  expect_true(nrow(habitat) > 0)
  expect_true("gradient" %in% names(habitat))
  expect_true("channel_width" %in% names(habitat))
})
