test_that("frs_fish_obs returns sf with species filter", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  obs <- frs_fish_obs(species_code = "CH", watershed_group_code = "BULK", limit = 5)
  expect_s3_class(obs, "sf")
  expect_true(nrow(obs) > 0)
  expect_true("species_code" %in% names(obs))
  expect_true(all(obs$species_code == "CH"))
})

test_that("frs_fish_obs returns all species when unfiltered", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  obs <- frs_fish_obs(watershed_group_code = "BULK", limit = 10)
  expect_s3_class(obs, "sf")
  expect_true(nrow(obs) > 0)
})
