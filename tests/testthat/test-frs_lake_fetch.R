test_that("frs_lake_fetch returns sf with watershed_group_code filter", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  lakes <- frs_lake_fetch(watershed_group_code = "BULK", limit = 5)
  expect_s3_class(lakes, "sf")
  expect_true(nrow(lakes) > 0)
  expect_true("waterbody_key" %in% names(lakes))
  expect_true(all(lakes$watershed_group_code == "BULK"))
})

test_that("frs_lake_fetch filters by area_ha_min", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  lakes <- frs_lake_fetch(
    watershed_group_code = "BULK",
    area_ha_min = 100,
    limit = 10
  )
  expect_true(all(lakes$area_ha >= 100))
})
