test_that("frs_wetland_fetch returns sf with watershed_group_code filter", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  wetlands <- frs_wetland_fetch(conn, watershed_group_code = "BULK", limit = 5)
  expect_s3_class(wetlands, "sf")
  expect_true(nrow(wetlands) > 0)
  expect_true("waterbody_key" %in% names(wetlands))
  expect_true(all(wetlands$watershed_group_code == "BULK"))
})

test_that("frs_wetland_fetch filters by area_ha_min", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  wetlands <- frs_wetland_fetch(conn,
    watershed_group_code = "BULK",
    area_ha_min = 5,
    limit = 10
  )
  expect_true(all(wetlands$area_ha >= 5))
})
