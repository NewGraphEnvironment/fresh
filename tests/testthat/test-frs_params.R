# Unit tests — CSV parsing, no DB needed

test_that("frs_params reads CSV and returns named list", {
  csv <- system.file("testdata", "test_params.csv", package = "fresh")
  params <- frs_params(csv = csv)
  expect_type(params, "list")
  expect_named(params, c("BT", "CH", "CO"))
})

test_that("frs_params species have correct threshold values", {
  csv <- system.file("testdata", "test_params.csv", package = "fresh")
  params <- frs_params(csv = csv)

  expect_equal(params$CO$spawn_gradient_max, 0.0549)
  expect_equal(params$CO$spawn_channel_width_min, 2)
  expect_equal(params$CH$spawn_mad_min, 0.46)
})

test_that("frs_params builds spawn ranges", {
  csv <- system.file("testdata", "test_params.csv", package = "fresh")
  params <- frs_params(csv = csv)

  expect_equal(params$CO$ranges$spawn$gradient, c(0, 0.0549))
  expect_equal(params$CO$ranges$spawn$channel_width, c(2, 9999))
  expect_equal(params$CO$ranges$spawn$mad_m3s, c(0.164, 9999))
})

test_that("frs_params builds rear ranges", {
  csv <- system.file("testdata", "test_params.csv", package = "fresh")
  params <- frs_params(csv = csv)

  expect_equal(params$CO$ranges$rear$gradient, c(0, 0.0549))
  expect_equal(params$CO$ranges$rear$channel_width, c(1.5, 9999))
  expect_equal(params$CO$ranges$rear$mad_m3s, c(0.03, 40))
})

test_that("frs_params handles NULL thresholds", {
  csv <- system.file("testdata", "test_params.csv", package = "fresh")
  params <- frs_params(csv = csv)

  # BT has no spawn MAD thresholds
  expect_null(params$BT$ranges$spawn$mad_m3s)
  # BT has no rear gradient or MAD, but does have channel_width
  expect_null(params$BT$ranges$rear$gradient)
  expect_null(params$BT$ranges$rear$mad_m3s)
  expect_equal(params$BT$ranges$rear$channel_width, c(1.5, 9999))
})

test_that("frs_params errors without conn or csv", {
  expect_error(frs_params(), "conn is required")
})

test_that("frs_params errors on empty CSV", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines("species_code,spawn_gradient_max", tmp)
  expect_error(frs_params(csv = tmp), "No parameter rows")
})

test_that("frs_params errors on missing species_code column", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c("code,gradient", "CO,0.05"), tmp)
  expect_error(frs_params(csv = tmp), "species_code")
})


# Integration tests — require DB connection

test_that("frs_params reads bcfishpass parameter table", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  params <- frs_params(conn)
  expect_type(params, "list")
  expect_true("CO" %in% names(params))
  expect_true("CH" %in% names(params))
  expect_equal(params$CO$spawn_gradient_max, 0.0549)
  expect_true(length(params) >= 10)
})

test_that("frs_params ranges match DB values", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  params <- frs_params(conn)
  expect_equal(params$CO$ranges$spawn$gradient, c(0, 0.0549))
  expect_equal(params$CO$ranges$spawn$channel_width, c(2, 9999))
})
