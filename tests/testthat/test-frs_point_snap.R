test_that("frs_point_snap returns sf with network position", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  # Point near the Bulkley River
  snapped <- frs_point_snap(x = -126.5, y = 54.5)
  expect_s3_class(snapped, "sf")
  expect_true(nrow(snapped) == 1)
  expect_true("blue_line_key" %in% names(snapped))
  expect_true("downstream_route_measure" %in% names(snapped))
  expect_true("distance_to_stream" %in% names(snapped))
})

test_that("frs_point_snap returns multiple candidates", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  snapped <- frs_point_snap(x = -126.5, y = 54.5, num_features = 3)
  expect_true(nrow(snapped) <= 3)
})
