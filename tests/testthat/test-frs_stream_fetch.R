test_that("frs_stream_fetch returns sf with watershed_group_code filter", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  streams <- frs_stream_fetch(conn, watershed_group_code = "BULK", limit = 5)
  expect_s3_class(streams, "sf")
  expect_true(nrow(streams) > 0)
  expect_true("blue_line_key" %in% names(streams))
  expect_true(all(streams$watershed_group_code == "BULK"))
})

test_that("frs_stream_fetch filters by stream_order_min", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  streams <- frs_stream_fetch(conn,
    watershed_group_code = "BULK",
    stream_order_min = 5,
    limit = 10
  )
  expect_true(all(streams$stream_order >= 5))
})

# -- stream guard tests (mocked) ---------------------------------------------

test_that("frs_stream_fetch includes guards by default", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_stream_fetch("mock", watershed_group_code = "BULK", limit = 1)

  expect_match(sql_sent, "localcode_ltree IS NOT NULL")
  expect_match(sql_sent, "wscode_ltree <@ '999'")
})

test_that("frs_stream_fetch skips guards with include_all = TRUE", {
  sql_sent <- NULL
  local_mocked_bindings(frs_db_query = function(conn, sql, ...) {
    sql_sent <<- sql
    data.frame()
  })

  frs_stream_fetch("mock", watershed_group_code = "BULK", include_all = TRUE, limit = 1)

  expect_no_match(sql_sent, "edge_type NOT IN")
})
