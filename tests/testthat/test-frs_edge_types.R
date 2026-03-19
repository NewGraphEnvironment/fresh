test_that("frs_edge_types returns full table", {
  d <- frs_edge_types()
  expect_s3_class(d, "data.frame")
  expect_named(d, c("edge_type", "description", "category"))
  expect_true(nrow(d) > 30)
  expect_true(1000 %in% d$edge_type)  # main flow
  expect_true(1500 %in% d$edge_type)  # lake shoreline
})

test_that("frs_edge_types filters by category", {
  lake <- frs_edge_types(category = "lake")
  expect_true(all(c(1500, 1525) %in% lake$edge_type))
  expect_match(lake$description[1], "Lake shoreline")

  stream <- frs_edge_types(category = "stream")
  expect_true(all(stream$category == "stream"))
  expect_true(1000 %in% stream$edge_type)  # main flow
  expect_true(1100 %in% stream$edge_type)  # secondary flow
})

test_that("frs_edge_types rejects invalid category", {
  expect_error(frs_edge_types(category = "bogus"), "category must be one of")
})

test_that("frs_edge_types subsurface codes match snap guards", {
  sub <- frs_edge_types(category = "subsurface")
  expect_true(1425 %in% sub$edge_type)
  expect_match(sub$description[1], "subsurface", ignore.case = TRUE)
})
