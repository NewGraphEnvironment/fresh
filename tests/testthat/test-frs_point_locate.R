test_that("frs_point_locate returns sf point geometry", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  # First snap to get a valid blue_line_key and measure
  snapped <- frs_point_snap(x = -126.5, y = 54.5)
  blk <- snapped$blue_line_key
  measure <- snapped$downstream_route_measure

  pt <- frs_point_locate(
    blue_line_key = blk,
    downstream_route_measure = measure
  )
  expect_s3_class(pt, "sf")
  expect_true(nrow(pt) >= 1)
})
