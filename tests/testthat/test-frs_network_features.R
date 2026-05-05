# Validation-layer tests for frs_network_features().
# Phase 1 of #201: confirms the function rejects malformed input
# before reaching SQL composition. SQL-composition tests + live
# parity tests land in Phase 2 + Phase 3.

test_that("`direction` is required (no default)", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id"
    ),
    regexp = "`direction` is required"
  )
})

test_that("`direction` must be one of downstream/upstream", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "sideways"
    ),
    regexp = "should be one of|'arg' should be one of"
  )
})

test_that("`feature_id_col` is required (no default)", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      direction = "downstream"
    ),
    regexp = "`feature_id_col` is required"
  )
})

test_that("identifiers reject characters outside [A-Za-z_][A-Za-z0-9_.]*", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams; DROP TABLE x",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream"
    ),
    regexp = "invalid characters"
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id with spaces",
      direction = "downstream"
    ),
    regexp = "invalid characters"
  )
})

test_that("`aoi` must be a WSG code matching [A-Z]{3,5}", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = "lowercase"
    ),
    regexp = "watershed group code"
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = "AB"
    ),
    regexp = "watershed group code"
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = ""
    ),
    regexp = "non-empty"
  )
})

test_that("`include_equivalents` must be a single non-NA logical", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      include_equivalents = NA
    )
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      include_equivalents = c(TRUE, FALSE)
    )
  )
})

test_that("validation passing reaches the Phase-2 stub error", {
  # Confirms validation succeeds + we reach the not-implemented stop().
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = "ADMS"
    ),
    regexp = "Phase 2 of #201"
  )
})
