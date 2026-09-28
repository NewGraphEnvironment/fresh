test_that("skip_if_no_conn skips when the connection fails", {
  refused <- function() stop("could not connect to server")
  expect_condition(skip_if_no_conn(refused), class = "skip")
  expect_condition(skip_if_no_conn(refused),
                   "could not connect to server", class = "skip")
})

test_that("skip_if_no_conn does not skip when the connection works", {
  skip_if_not(.frs_db_available(), "DB not available")
  expect_no_condition(skip_if_no_conn(), class = "skip")
})
