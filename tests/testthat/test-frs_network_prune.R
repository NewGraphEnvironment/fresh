# -- stream guard tests (mocked) ---------------------------------------------

test_that("frs_network_prune includes guards by default", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network_prune(blue_line_key = 360873822, downstream_route_measure = 166030)

  expect_match(sql_sent, "localcode_ltree IS NOT NULL")
})

test_that("frs_network_prune skips guards with include_all = TRUE", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_network_prune(blue_line_key = 360873822, downstream_route_measure = 166030,
    include_all = TRUE)

  expect_no_match(sql_sent, "edge_type NOT IN")
})

# -- live DB tests ------------------------------------------------------------

test_that("frs_network_prune filters upstream by stream order", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  snapped <- frs_point_snap(x = -126.5, y = 54.5)

  pruned <- frs_network_prune(
    blue_line_key = snapped$blue_line_key,
    downstream_route_measure = snapped$downstream_route_measure,
    stream_order_min = 3
  )
  expect_s3_class(pruned, "sf")
  if (nrow(pruned) > 0) {
    expect_true(all(pruned$stream_order >= 3))
  }
})

test_that("frs_network_prune filters by gradient", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")

  snapped <- frs_point_snap(x = -126.5, y = 54.5)

  pruned <- frs_network_prune(
    blue_line_key = snapped$blue_line_key,
    downstream_route_measure = snapped$downstream_route_measure,
    gradient_max = 0.03
  )
  expect_s3_class(pruned, "sf")
  if (nrow(pruned) > 0) {
    expect_true(all(pruned$gradient <= 0.03))
  }
})
