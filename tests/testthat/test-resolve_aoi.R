# Unit tests — no DB needed

test_that("NULL aoi returns empty string", {
  expect_equal(.frs_resolve_aoi(NULL), "")
})

test_that("character aoi produces partition table predicate", {
  result <- .frs_resolve_aoi("BULK")
  expect_match(result, "watershed_group_code IN")
  expect_match(result, "'BULK'")
  expect_match(result, "ST_Union")
})

test_that("character vector aoi handles multiple codes", {
  result <- .frs_resolve_aoi(c("BULK", "MORR"))
  expect_match(result, "'BULK', 'MORR'")
})

test_that("character aoi respects options", {
  withr::with_options(
    list(
      fresh.partition_table = "my_schema.my_partitions",
      fresh.partition_col = "basin_id"
    ),
    {
      result <- .frs_resolve_aoi("ABC")
      expect_match(result, "my_schema.my_partitions")
      expect_match(result, "basin_id IN")
    }
  )
})

test_that("sf aoi produces ST_Intersects predicate", {
  poly <- sf::st_sf(
    geometry = sf::st_sfc(
      sf::st_polygon(list(rbind(
        c(-126, 54), c(-125, 54), c(-125, 55), c(-126, 55), c(-126, 54)
      ))),
      crs = 4326
    )
  )
  result <- .frs_resolve_aoi(poly)
  expect_match(result, "ST_Intersects")
  expect_match(result, "ST_GeomFromText")
  expect_match(result, "3005")
})

test_that("sf aoi transforms to 3005", {
  # WGS84 input should be transformed
  poly <- sf::st_sf(
    geometry = sf::st_sfc(
      sf::st_polygon(list(rbind(
        c(-126, 54), c(-125, 54), c(-125, 55), c(-126, 55), c(-126, 54)
      ))),
      crs = 4326
    )
  )
  result <- .frs_resolve_aoi(poly)
  # The WKT should contain BC Albers-scale coordinates, not lat/lon
  expect_false(grepl("-126", result))
})

test_that("blk+measure list produces watershed delineation predicate", {
  result <- .frs_resolve_aoi(list(blk = 360873822, measure = 208877))
  expect_match(result, "fwa_watershedatmeasure")
  expect_match(result, "360873822")
  expect_match(result, "208877")
})

test_that("table+id list produces lookup predicate", {
  result <- .frs_resolve_aoi(list(
    table = "whse_basemapping.fwa_assessment_watersheds_poly",
    id_col = "watershed_feature_id",
    id = 1387
  ))
  expect_match(result, "fwa_assessment_watersheds_poly")
  expect_match(result, "watershed_feature_id = 1387")
})

test_that("table+id with string id gets quoted", {
  result <- .frs_resolve_aoi(list(
    table = "my_schema.my_areas",
    id_col = "area_name",
    id = "North Basin"
  ))
  expect_match(result, "'North Basin'")
})

test_that("table+id defaults id_col to 'id'", {
  result <- .frs_resolve_aoi(list(table = "my_schema.areas", id = 42))
  expect_match(result, "id = 42")
})

test_that("alias prepends to geom column", {
  result <- .frs_resolve_aoi("BULK", alias = "s")
  expect_match(result, "s\\.geom")
})

test_that("custom geom_col is used", {
  result <- .frs_resolve_aoi("BULK", geom_col = "wkb_geometry")
  expect_match(result, "wkb_geometry")
})

test_that("invalid aoi type errors", {
  expect_error(.frs_resolve_aoi(42), "must be NULL, character, sf, or list")
})

test_that("list without required keys errors", {
  expect_error(.frs_resolve_aoi(list(foo = "bar")), "must have")
})

test_that("SQL injection in character aoi is escaped", {
  result <- .frs_resolve_aoi("'; DROP TABLE users; --")
  # Single quotes are doubled — the value is safely inside a SQL string literal
  expect_match(result, "''", fixed = TRUE)
})

test_that("SQL injection in table+id string is escaped", {
  result <- .frs_resolve_aoi(list(
    table = "my_schema.areas",
    id_col = "name",
    id = "'; DROP TABLE users; --"
  ))
  expect_match(result, "''")
})


# Integration tests — require DB connection

test_that("character aoi resolves against real DB", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  predicate <- .frs_resolve_aoi("BULK")
  sql <- sprintf(
    "SELECT COUNT(*) as n FROM whse_basemapping.fwa_stream_networks_sp WHERE %s LIMIT 1",
    predicate
  )
  result <- DBI::dbGetQuery(conn, sql)
  expect_gt(result$n, 0)
})

test_that("table+id aoi resolves against real assessment watershed", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  predicate <- .frs_resolve_aoi(list(
    table = "whse_basemapping.fwa_assessment_watersheds_poly",
    id_col = "watershed_feature_id",
    id = 1387
  ))
  sql <- sprintf(
    "SELECT COUNT(*) as n FROM whse_basemapping.fwa_stream_networks_sp WHERE %s",
    predicate
  )
  result <- DBI::dbGetQuery(conn, sql)
  expect_gt(result$n, 0)
})

test_that("blk+measure aoi resolves against real DB", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  predicate <- .frs_resolve_aoi(list(blk = 360873822, measure = 208877))
  sql <- sprintf(
    "SELECT COUNT(*) as n FROM whse_basemapping.fwa_stream_networks_sp WHERE %s",
    predicate
  )
  result <- DBI::dbGetQuery(conn, sql)
  expect_gt(result$n, 0)
})
