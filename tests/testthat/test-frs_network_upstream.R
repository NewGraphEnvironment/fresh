test_that("frs_network_upstream returns sf of upstream segments", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  # Snap a point first to get valid network position
  snapped <- frs_point_snap(x = -126.5, y = 54.5)

  upstream <- frs_network_upstream(
    blue_line_key = snapped$blue_line_key,
    downstream_route_measure = snapped$downstream_route_measure
  )
  expect_s3_class(upstream, "sf")
  expect_true(nrow(upstream) > 0)
  expect_true("stream_order" %in% names(upstream))
})
