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


# --- Rules YAML tests ---

test_that("frs_params loads bundled rules YAML by default", {
  csv <- system.file("testdata", "test_params.csv", package = "fresh")
  params <- frs_params(csv = csv)
  # CO is in both the test CSV and the bundled rules YAML
  expect_false(is.null(params$CO$rules))
  expect_false(is.null(params$CO$rules$spawn))
  expect_false(is.null(params$CO$rules$rear))
})

test_that("frs_params with rules_yaml = NULL skips rules", {
  csv <- system.file("testdata", "test_params.csv", package = "fresh")
  params <- frs_params(csv = csv, rules_yaml = NULL)
  # No species should have $rules
  expect_null(params$CO$rules)
  expect_null(params$BT$rules)
})

test_that("frs_params bundled rules has expected species blocks", {
  csv <- system.file("testdata", "test_params.csv", package = "fresh")
  params <- frs_params(csv = csv)
  # CO has 2 spawn rules (stream/canal + R polygon) and 4 rear rules
  expect_length(params$CO$rules$spawn, 2)
  expect_length(params$CO$rules$rear, 4)
  # CO rule 3 has thresholds: false (wetland-flow carve-out)
  expect_false(params$CO$rules$rear[[3]]$thresholds)
  expect_equal(params$CO$rules$rear[[3]]$edge_types_explicit, c(1050L, 1150L))
})

test_that(".frs_load_rules errors on missing file", {
  expect_error(.frs_load_rules("/nonexistent/path.yaml"),
               "rules_yaml file not found")
})

test_that(".frs_load_rules errors on mad predicate (Phase 2)", {
  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  writeLines(c(
    "BT:",
    "  spawn:",
    "    - mad: [0.5, 9999]"), tmp)
  expect_error(.frs_load_rules(tmp), "fresh#114")
})

test_that(".frs_load_rules errors on unknown predicate", {
  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  writeLines(c(
    "BT:",
    "  spawn:",
    "    - bogus_field: 42"), tmp)
  expect_error(.frs_load_rules(tmp), "unknown predicates")
})

test_that(".frs_load_rules errors on lake_ha_min without waterbody_type L", {
  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  writeLines(c(
    "SK:",
    "  rear:",
    "    - lake_ha_min: 200"), tmp)
  expect_error(.frs_load_rules(tmp), "lake_ha_min without waterbody_type")
})

test_that(".frs_load_rules errors on bad waterbody_type", {
  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  writeLines(c(
    "SK:",
    "  rear:",
    "    - waterbody_type: lake"), tmp)
  expect_error(.frs_load_rules(tmp), "must be one of L, R, W")
})

test_that(".frs_load_rules errors on bad habitat block", {
  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  writeLines(c(
    "SK:",
    "  spawning:",
    "    - waterbody_type: L"), tmp)
  expect_error(.frs_load_rules(tmp), "unknown habitat block")
})

test_that(".frs_load_rules accepts empty rear list", {
  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  writeLines(c(
    "PK:",
    "  rear: []"), tmp)
  expect_silent(rules <- .frs_load_rules(tmp))
  expect_length(rules$PK$rear, 0)
})

test_that(".frs_load_rules accepts empty file", {
  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  writeLines("", tmp)
  expect_silent(rules <- .frs_load_rules(tmp))
  expect_length(rules, 0)
})


# --- Rule evaluator tests ---

test_that(".frs_rule_to_sql edge_types translates via frs_edge_types", {
  rule <- list(edge_types = c("stream", "canal"))
  sql <- .frs_rule_to_sql(rule)
  expect_match(sql, "^\\(s\\.edge_type IN")
  # Should contain at least one stream code from frs_edge_types
  expect_match(sql, "1000|1100|1325")
})

test_that(".frs_rule_to_sql edge_types_explicit uses raw codes", {
  rule <- list(edge_types_explicit = c(1050L, 1150L))
  sql <- .frs_rule_to_sql(rule)
  expect_equal(sql, "(s.edge_type IN (1050, 1150))")
})

test_that(".frs_rule_to_sql waterbody_type L uses fwa_lakes_poly", {
  rule <- list(waterbody_type = "L")
  sql <- .frs_rule_to_sql(rule)
  expect_match(sql, "fwa_lakes_poly")
  expect_match(sql, "waterbody_key IN")
})

test_that(".frs_rule_to_sql waterbody_type R uses fwa_rivers_poly", {
  rule <- list(waterbody_type = "R")
  sql <- .frs_rule_to_sql(rule)
  expect_match(sql, "fwa_rivers_poly")
})

test_that(".frs_rule_to_sql waterbody_type W uses fwa_wetlands_poly", {
  rule <- list(waterbody_type = "W")
  sql <- .frs_rule_to_sql(rule)
  expect_match(sql, "fwa_wetlands_poly")
})

test_that(".frs_rule_to_sql lake_ha_min adds area_ha filter", {
  rule <- list(waterbody_type = "L", lake_ha_min = 200)
  sql <- .frs_rule_to_sql(rule)
  expect_match(sql, "fwa_lakes_poly WHERE area_ha >= 200")
})

test_that(".frs_rule_to_sql inherits CSV thresholds by default", {
  rule <- list(edge_types_explicit = c(1000L))
  csv_thresholds <- list(
    gradient = c(0, 0.0549),
    channel_width = c(2, 9999))
  sql <- .frs_rule_to_sql(rule, csv_thresholds)
  expect_match(sql, "s\\.gradient BETWEEN 0 AND 0\\.0549")
  expect_match(sql, "s\\.channel_width BETWEEN 2 AND 9999")
})

test_that(".frs_rule_to_sql skips CSV thresholds when thresholds=FALSE", {
  rule <- list(
    edge_types_explicit = c(1050L, 1150L),
    thresholds = FALSE)
  csv_thresholds <- list(
    gradient = c(0, 0.0549),
    channel_width = c(2, 9999))
  sql <- .frs_rule_to_sql(rule, csv_thresholds)
  # No threshold conditions should be added
  expect_false(grepl("gradient", sql))
  expect_false(grepl("channel_width", sql))
  # But the explicit edge_type predicate should be there
  expect_match(sql, "s\\.edge_type IN \\(1050, 1150\\)")
})

test_that(".frs_rule_to_sql empty rule returns (TRUE)", {
  expect_equal(.frs_rule_to_sql(list()), "(TRUE)")
})

test_that(".frs_rules_to_sql empty list returns FALSE", {
  expect_equal(.frs_rules_to_sql(list()), "FALSE")
  expect_equal(.frs_rules_to_sql(NULL), "FALSE")
})

test_that(".frs_rules_to_sql joins multiple rules with OR", {
  rules <- list(
    list(edge_types_explicit = c(1000L)),
    list(edge_types_explicit = c(2000L)))
  sql <- .frs_rules_to_sql(rules)
  expect_match(sql, "OR")
  expect_match(sql, "1000")
  expect_match(sql, "2000")
})

test_that(".frs_rules_to_sql CO rear pattern: 4 rules with carve-out", {
  rules <- list(
    list(edge_types_explicit = c(1000L)),                             # rule 1: with thresholds
    list(waterbody_type = "R"),                                       # rule 2: with thresholds
    list(edge_types_explicit = c(1050L, 1150L), thresholds = FALSE),  # rule 3: NO thresholds
    list(waterbody_type = "L"))                                       # rule 4: with thresholds
  csv_thresholds <- list(
    gradient = c(0, 0.0549),
    channel_width = c(1.5, 9999))
  sql <- .frs_rules_to_sql(rules, csv_thresholds)

  # Should have 3 OR separators (4 rules)
  expect_equal(length(gregexpr(" OR ", sql, fixed = TRUE)[[1]]), 3)
  # Rule 3 (1050,1150) should NOT have gradient/channel_width
  # We can't easily verify this without parsing, but we can check
  # the explicit edge codes appear without nearby threshold text
  expect_match(sql, "1050, 1150")
  # All three other rules should have thresholds
  expect_equal(length(gregexpr("gradient BETWEEN", sql)[[1]]), 3)
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
