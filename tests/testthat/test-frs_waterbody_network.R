test_that("frs_waterbody_network builds correct upstream SQL", {
  # Mock frs_db_query to capture the SQL
  sql_sent <- NULL
  mockery::stub(frs_waterbody_network, "frs_db_query", function(conn, sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_waterbody_network("mock",
    blue_line_key = 360873822,
    downstream_route_measure = 166030
  )

  expect_match(sql_sent, "fwa_upstream")
  expect_match(sql_sent, "fwa_lakes_poly")
  expect_match(sql_sent, "network_wbkeys")
  expect_match(sql_sent, "waterbody_key IS NOT NULL")
  expect_match(sql_sent, "360873822")
})

test_that("frs_waterbody_network switches to downstream", {
  sql_sent <- NULL
  mockery::stub(frs_waterbody_network, "frs_db_query", function(conn, sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_waterbody_network("mock",
    blue_line_key = 360873822,
    downstream_route_measure = 166030,
    direction = "downstream"
  )

  expect_match(sql_sent, "fwa_downstream")
  expect_no_match(sql_sent, "fwa_upstream")
})

test_that("frs_waterbody_network accepts custom table and cols", {
  sql_sent <- NULL
  mockery::stub(frs_waterbody_network, "frs_db_query", function(conn, sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_waterbody_network("mock",
    blue_line_key = 360873822,
    downstream_route_measure = 166030,
    table = "whse_basemapping.fwa_wetlands_poly",
    cols = c("waterbody_key", "area_ha", "geom")
  )

  expect_match(sql_sent, "fwa_wetlands_poly")
  expect_match(sql_sent, "p.waterbody_key, p.area_ha, p.geom")
})

test_that("frs_waterbody_network rejects invalid direction", {
  expect_error(
    frs_waterbody_network("mock", 360873822, 166030, direction = "sideways"),
    "arg"
  )
})
