test_that("frs_stream_fetch returns sf with watershed_group_code filter", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  streams <- frs_stream_fetch(watershed_group_code = "BULK", limit = 5)
  expect_s3_class(streams, "sf")
  expect_true(nrow(streams) > 0)
  expect_true("blue_line_key" %in% names(streams))
  expect_true(all(streams$watershed_group_code == "BULK"))
})

test_that("frs_stream_fetch filters by stream_order_min", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  streams <- frs_stream_fetch(
    watershed_group_code = "BULK",
    stream_order_min = 5,
    limit = 10
  )
  expect_true(all(streams$stream_order >= 5))
})
