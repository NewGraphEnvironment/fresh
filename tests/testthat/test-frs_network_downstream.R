test_that("frs_network_downstream returns sf of downstream segments", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  # Snap a point first to get valid network position
  snapped <- frs_point_snap(x = -126.5, y = 54.5)

  downstream <- frs_network_downstream(
    blue_line_key = snapped$blue_line_key,
    downstream_route_measure = snapped$downstream_route_measure
  )
  expect_s3_class(downstream, "sf")
  expect_true(nrow(downstream) > 0)
  expect_true("stream_order" %in% names(downstream))
})
