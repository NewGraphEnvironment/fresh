test_that("frs_network_prune filters upstream by stream order", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  snapped <- frs_point_snap(x = -126.5, y = 54.5)

  pruned <- frs_network_prune(
    blue_line_key = snapped$blue_line_key,
    downstream_route_measure = snapped$downstream_route_measure,
    stream_order_min = 3
  )
  expect_s3_class(pruned, "sf")
  if (nrow(pruned) > 0) {
    expect_true(all(pruned$stream_order >= 3))
  }
})

test_that("frs_network_prune filters by gradient", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  snapped <- frs_point_snap(x = -126.5, y = 54.5)

  pruned <- frs_network_prune(
    blue_line_key = snapped$blue_line_key,
    downstream_route_measure = snapped$downstream_route_measure,
    gradient_max = 0.03
  )
  expect_s3_class(pruned, "sf")
  if (nrow(pruned) > 0) {
    expect_true(all(pruned$gradient <= 0.03))
  }
})
