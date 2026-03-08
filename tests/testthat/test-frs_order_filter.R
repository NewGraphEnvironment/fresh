test_that("frs_order_filter keeps only streams >= min_order", {
  streams <- sf::st_as_sf(
    data.frame(
      stream_order = c(1, 2, 3, 4, 5),
      x = c(1, 2, 3, 4, 5),
      y = c(1, 2, 3, 4, 5)
    ),
    coords = c("x", "y")
  )

  result <- frs_order_filter(streams, min_order = 3)
  expect_true(all(result$stream_order >= 3))
  expect_equal(nrow(result), 3)
})

test_that("frs_order_filter errors without stream_order column", {
  df <- data.frame(x = 1:3)
  expect_error(frs_order_filter(df, min_order = 2))
})
