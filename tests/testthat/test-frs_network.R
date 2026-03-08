test_that("frs_network with no tables returns streams directly", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  result <- frs_network(360873822, 166030)

  expect_match(sql_sent, "fwa_stream_networks_sp")
  expect_match(sql_sent, "fwa_upstream")
  expect_s3_class(result, "data.frame")
})

test_that("frs_network returns named list for multiple tables", {
  local_mocked_bindings(frs_db_query = function(sql, ...) data.frame())

  result <- frs_network(360873822, 166030, tables = list(
    streams = "whse_basemapping.fwa_stream_networks_sp",
    lakes = "whse_basemapping.fwa_lakes_poly"
  ))

  expect_type(result, "list")
  expect_named(result, c("streams", "lakes"))
})

test_that("frs_network detects waterbody bridge for lakes", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030, tables = list(
    lakes = "whse_basemapping.fwa_lakes_poly"
  ))

  expect_match(sql_sent, "network_wbkeys")
  expect_match(sql_sent, "waterbody_key IS NOT NULL")
  expect_match(sql_sent, "fwa_lakes_poly")
})

test_that("frs_network detects waterbody bridge for wetlands", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030, tables = list(
    wetlands = "whse_basemapping.fwa_wetlands_poly"
  ))

  expect_match(sql_sent, "network_wbkeys")
  expect_match(sql_sent, "fwa_wetlands_poly")
})

test_that("frs_network uses direct query for crossings", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030, tables = list(
    crossings = "bcfishpass.crossings"
  ))

  expect_match(sql_sent, "fwa_upstream")
  expect_match(sql_sent, "bcfishpass.crossings")
  expect_no_match(sql_sent, "network_wbkeys")
})

test_that("frs_network passes direction downstream", {
  sqls <- list()
  call_n <- 0
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    call_n <<- call_n + 1
    sqls[[call_n]] <<- sql
    data.frame()
  })

  frs_network(360873822, 166030,
    tables = list(
      streams = "whse_basemapping.fwa_stream_networks_sp",
      lakes = "whse_basemapping.fwa_lakes_poly"
    ),
    direction = "downstream"
  )

  expect_match(sqls[[1]], "fwa_downstream")
  expect_match(sqls[[2]], "fwa_downstream")
})

test_that("frs_network passes custom cols and wscode_col", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030, tables = list(
    co = list(
      table = "bcfishpass.streams_co_vw",
      cols = c("blue_line_key", "mapping_code", "geom"),
      wscode_col = "wscode",
      localcode_col = "localcode"
    )
  ))

  expect_match(sql_sent, "streams_co_vw")
  expect_match(sql_sent, "s.blue_line_key, s.mapping_code, s.geom")
  expect_match(sql_sent, "s.wscode, s.localcode")
})

test_that("frs_network passes extra_where", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030, tables = list(
    co = list(
      table = "bcfishpass.streams_co_vw",
      wscode_col = "wscode",
      localcode_col = "localcode",
      extra_where = "(s.rearing > 0 OR s.spawning > 0)"
    )
  ))

  expect_match(sql_sent, "rearing > 0 OR s.spawning > 0")
})

test_that("frs_default_cols returns sensible defaults", {
  expect_true("geom" %in% frs_default_cols("whse_basemapping.fwa_stream_networks_sp"))
  expect_true("area_ha" %in% frs_default_cols("whse_basemapping.fwa_lakes_poly"))
  expect_true("barrier_status" %in% frs_default_cols("bcfishpass.crossings"))
  expect_true("species_code" %in% frs_default_cols("bcfishpass.observations_vw"))
  expect_equal(frs_default_cols("some.unknown_table"), "*")
})

test_that("frs_network rejects invalid direction", {
  expect_error(frs_network(360873822, 166030, direction = "sideways"), "arg")
})

test_that("upstream_measure with downstream direction errors", {
  expect_error(
    frs_network(360873822, 166030, upstream_measure = 200000, direction = "downstream"),
    "upstream_measure"
  )
})

test_that("upstream_measure <= downstream_route_measure errors", {
  expect_error(
    frs_network(360873822, 200000, upstream_measure = 100000),
    "greater"
  )
})

test_that("upstream_measure generates between SQL for direct table", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 208877, upstream_measure = 233564, tables = list(
    streams = "whse_basemapping.fwa_stream_networks_sp"
  ))

  expect_match(sql_sent, "ref_down")
  expect_match(sql_sent, "ref_up")
  expect_match(sql_sent, "NOT EXISTS")
  expect_match(sql_sent, "208877")
  expect_match(sql_sent, "233564")
})

test_that("upstream_measure generates between SQL for waterbody table", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 208877, upstream_measure = 233564, tables = list(
    lakes = "whse_basemapping.fwa_lakes_poly"
  ))

  expect_match(sql_sent, "ref_down")
  expect_match(sql_sent, "ref_up")
  expect_match(sql_sent, "NOT EXISTS")
  expect_match(sql_sent, "network_wbkeys")
})

test_that("upstream_measure NULL preserves single-ref SQL", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030)

  expect_match(sql_sent, "WITH ref AS")
  expect_no_match(sql_sent, "ref_down")
  expect_no_match(sql_sent, "NOT EXISTS")
})

test_that("upstream_measure with custom wscode_col", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 208877, upstream_measure = 233564, tables = list(
    obs = list(
      table = "bcfishpass.observations_vw",
      wscode_col = "wscode",
      localcode_col = "localcode"
    )
  ))

  expect_match(sql_sent, "ref_up")
  expect_match(sql_sent, "wscode AS wscode")
  expect_match(sql_sent, "localcode AS localcode")
})
