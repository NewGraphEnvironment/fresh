test_that("frs_point_locate returns sf point geometry", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  # First snap to get a valid blue_line_key and measure
  snapped <- frs_point_snap(conn, data.frame(x = -126.5, y = 54.5),
    tolerance = 500)
  blk <- snapped$blue_line_key
  measure <- snapped$downstream_route_measure

  pt <- frs_point_locate(conn,
    blue_line_key = blk,
    downstream_route_measure = measure
  )
  expect_s3_class(pt, "sf")
  expect_true(nrow(pt) >= 1)
})

test_that("frs_point_locate writes the key as an integer and the measure in full", {
  # sprintf("%s", m) keeps 15 significant digits, and for a stream's top that
  # can parse above the segment's end, outside every segment's range (#274).
  # This value needs all 17 digits.
  m <- 1234567.8912345678
  expect_false(as.numeric(sprintf("%.15g", m)) == m)
  sql <- NULL
  local_mocked_bindings(frs_db_query = function(conn, sql_in, ...) {
    sql <<- sql_in
    NULL
  })
  frs_point_locate("mock", blue_line_key = 356000000,
                   downstream_route_measure = m)
  expect_match(sql, "fwa_locatealong(356000000, 1234567.8912345679)",
               fixed = TRUE)
  expect_no_match(sql, "e+", fixed = TRUE)
})

test_that("frs_point_locate refuses a measure that is not one finite number", {
  local_mocked_bindings(frs_db_query = function(...) {
    stop("reached the database")
  })
  for (bad in list(NA_real_, Inf, c(1, 2))) {
    expect_error(
      frs_point_locate("mock", blue_line_key = 356000000,
                       downstream_route_measure = bad),
      "downstream_route_measure must be a single finite number")
  }
})
