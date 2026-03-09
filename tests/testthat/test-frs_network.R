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
  # Ref uses standard ltree cols, main query uses custom
  expect_match(sql_sent, "wscode_ltree AS wscode")
  expect_match(sql_sent, "s\\.wscode, s\\.localcode")
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
  expect_true("species_code" %in% frs_default_cols("bcfishobs.fiss_fish_obsrvtn_events_vw"))
  expect_true("falls_name" %in% frs_default_cols("bcfishpass.falls_vw"))
  expect_equal(frs_default_cols("some.unknown_table"), "*")
})

test_that("frs_network rejects NULL blue_line_key", {
  expect_error(frs_network(NULL, 166030), "single numeric")
})

test_that("frs_network rejects NA blue_line_key", {
  expect_error(frs_network(NA, 166030), "single numeric")
})

test_that("frs_network rejects character blue_line_key", {
  expect_error(frs_network("abc", 166030), "single numeric")
})

test_that("frs_network rejects NA downstream_route_measure", {
  expect_error(frs_network(360873822, NA), "single numeric")
})

test_that("frs_network rejects vector measure", {
  expect_error(frs_network(360873822, c(100, 200)), "single numeric")
})

test_that("frs_network rejects NA upstream_measure", {
  expect_error(frs_network(360873822, 166030, upstream_measure = NA), "single numeric")
})

test_that("frs_network rejects character upstream_blk", {
  expect_error(
    frs_network(360873822, 166030, upstream_measure = 200000, upstream_blk = "bad"),
    "single numeric"
  )
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

test_that("upstream_measure <= downstream_route_measure errors on same BLK", {
  expect_error(
    frs_network(360873822, 200000, upstream_measure = 100000),
    "greater"
  )
})

test_that("upstream_blk skips measure check for different BLK", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    if (grepl("is_upstream", sql)) return(data.frame(is_upstream = TRUE))
    sql_sent <<- sql
    data.frame()
  })

  # upstream_measure < downstream_route_measure but on different BLK — should NOT error
  frs_network(360873822, 208877, upstream_measure = 838,
    upstream_blk = 360886221, tables = list(
      streams = "whse_basemapping.fwa_stream_networks_sp"
    ))

  # ref_up should use the upstream BLK
  expect_match(sql_sent, "360886221")
  expect_match(sql_sent, "838")
})

test_that("upstream_blk uses different BLK in ref_up for direct table", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    if (grepl("is_upstream", sql)) return(data.frame(is_upstream = TRUE))
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 165115, upstream_measure = 838,
    upstream_blk = 360886221, tables = list(
      crossings = "bcfishpass.crossings"
    ))

  # ref_down uses downstream BLK
  expect_match(sql_sent, "ref_down")
  # ref_up uses upstream BLK
  expect_match(sql_sent, "360886221")
  expect_match(sql_sent, "NOT EXISTS")
})

test_that("upstream_blk on different network errors", {
  call_count <- 0
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    call_count <<- call_count + 1
    if (grepl("fwa_upstream", sql)) {
      # Validation query — not upstream
      data.frame(is_upstream = FALSE)
    } else {
      data.frame()
    }
  })

  expect_error(
    frs_network(360873822, 208877, upstream_measure = 79244,
      upstream_blk = 356570562, tables = list(
        streams = "whse_basemapping.fwa_stream_networks_sp"
      )),
    "not upstream"
  )
})

test_that("upstream_blk on same network passes validation", {
  call_count <- 0
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    call_count <<- call_count + 1
    if (grepl("fwa_upstream\\(", sql) && grepl("is_upstream", sql)) {
      data.frame(is_upstream = TRUE)
    } else {
      data.frame()
    }
  })

  result <- frs_network(360873822, 165115, upstream_measure = 838,
    upstream_blk = 360886221, tables = list(
      streams = "whse_basemapping.fwa_stream_networks_sp"
    ))

  # Should have called: 1 validation + 1 data query = 2
  expect_equal(call_count, 2)
})

test_that("upstream_blk uses different BLK in ref_up for waterbody table", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    if (grepl("is_upstream", sql)) return(data.frame(is_upstream = TRUE))
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 165115, upstream_measure = 838,
    upstream_blk = 360886221, tables = list(
      lakes = "whse_basemapping.fwa_lakes_poly"
    ))

  expect_match(sql_sent, "360886221")
  expect_match(sql_sent, "network_wbkeys")
  expect_match(sql_sent, "NOT EXISTS")
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

test_that("upstream_blk without upstream_measure is ignored", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  # upstream_blk provided but upstream_measure is NULL — no subtraction
  frs_network(360873822, 166030, upstream_blk = 360886221)
  expect_match(sql_sent, "WITH ref AS")
  expect_no_match(sql_sent, "ref_down")
})

test_that("frs_network equal measures on same BLK errors", {
  expect_error(
    frs_network(360873822, 208877, upstream_measure = 208877),
    "greater"
  )
})

test_that("frs_network same BLK passed as upstream_blk still checks measures", {
  # Explicitly passing upstream_blk = same as blue_line_key should still enforce measure check
  expect_error(
    frs_network(360873822, 200000, upstream_measure = 100000,
      upstream_blk = 360873822),
    "greater"
  )
})

test_that("frs_network upstream_blk with downstream direction errors", {
  expect_error(
    frs_network(360873822, 166030, upstream_measure = 838,
      upstream_blk = 360886221, direction = "downstream"),
    "upstream_measure"
  )
})

test_that("frs_check_upstream errors on empty result", {
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    if (grepl("is_upstream", sql)) {
      # Empty result — BLK not found in stream network
      data.frame(is_upstream = logical(0))
    } else {
      data.frame()
    }
  })

  expect_error(
    frs_network(360873822, 208877, upstream_measure = 838,
      upstream_blk = 999999999, tables = list(
        streams = "whse_basemapping.fwa_stream_networks_sp"
      )),
    "not upstream"
  )
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
  # Ref always comes from streams with standard ltree cols
  expect_match(sql_sent, "wscode_ltree AS wscode")
  expect_match(sql_sent, "localcode_ltree AS localcode")
  # But the main query uses the custom col names
  expect_match(sql_sent, "s\\.wscode, s\\.localcode")
})

# -- stream guard tests -------------------------------------------------------

test_that("frs_network includes guards for FWA streams by default", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030)

  expect_match(sql_sent, "localcode_ltree IS NOT NULL")
  expect_match(sql_sent, "wscode_ltree <@ '999'")
})

test_that("frs_network skips guards with include_all = TRUE", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030, include_all = TRUE)

  expect_no_match(sql_sent, "edge_type NOT IN")
  expect_no_match(sql_sent, "wscode_ltree <@ '999'")
})

test_that("frs_network includes guards in waterbody CTE", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030, tables = list(
    lakes = "whse_basemapping.fwa_lakes_poly"
  ))

  expect_match(sql_sent, "localcode_ltree IS NOT NULL")
})

test_that("frs_network skips guards for non-FWA tables", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network(360873822, 166030, tables = list(
    streams = list(
      table = "bcfishpass.streams_co_vw",
      wscode_col = "wscode",
      localcode_col = "localcode"
    )
  ))

  expect_no_match(sql_sent, "edge_type NOT IN")
})
