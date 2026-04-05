# --- Unit tests: frs_break_find ---

test_that("frs_break_find requires exactly one mode", {
  expect_error(
    frs_break_find("mock", "working.streams"),
    "Provide one of"
  )
  expect_error(
    frs_break_find("mock", "working.streams",
                   attribute = "gradient", threshold = 0.05,
                   points_table = "some.table"),
    "Provide only one"
  )
})

test_that("frs_break_find validates identifiers", {
  expect_error(
    frs_break_find("mock", "DROP TABLE foo",
                   attribute = "gradient", threshold = 0.05),
    "invalid characters"
  )
})

test_that("frs_break_find attribute mode builds correct SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_break_find("mock", "working.streams",
                 attribute = "gradient", threshold = 0.05)

  # Should have DROP (overwrite=TRUE default) + CREATE
  expect_length(sql_log, 2)
  expect_match(sql_log[1], "DROP TABLE IF EXISTS working.breaks")
  expect_match(sql_log[2], "CREATE TABLE working.breaks")
  expect_match(sql_log[2], "fwa_slopealonginterval")
  expect_match(sql_log[2], "gradient > 0.05")
})

test_that("frs_break_find table mode builds correct SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_break_find("mock", "working.streams",
                 points_table = "bcfishpass.falls_events_sp")

  expect_match(sql_log[2], "FROM bcfishpass.falls_events_sp")
  expect_match(sql_log[2], "blue_line_key")
})

test_that("frs_break_find table mode adds AOI filter", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_break_find("mock", "working.streams",
                 points_table = "bcfishpass.falls_events_sp")

  expect_match(sql_log[2], "WHERE.*blue_line_key IN")
})

test_that("frs_break_find table mode adds where filter", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_break_find("mock", "working.streams",
                 points_table = "bcfishpass.falls_vw",
                 where = "barrier_ind = TRUE")

  expect_match(sql_log[2], "WHERE.*barrier_ind = TRUE")
})

test_that("frs_break_find table mode combines where and aoi", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_break_find("mock", "working.streams",
                 points_table = "bcfishpass.falls_vw",
                 where = "barrier_ind = TRUE")

  expect_match(sql_log[2], "blue_line_key IN")
  expect_match(sql_log[2], "barrier_ind = TRUE")
  expect_match(sql_log[2], "AND")
})

test_that("frs_break_find returns conn invisibly", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  result <- frs_break_find("mock_conn", "working.streams",
                           attribute = "gradient", threshold = 0.05)
  expect_equal(result, "mock_conn")
})

test_that("frs_break_find points mode rejects non-sf", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  expect_error(
    frs_break_find("mock", "working.streams",
                   points = data.frame(x = 1, y = 2)),
    "sf object"
  )
})

test_that("frs_break_find skips drop when overwrite = FALSE", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_break_find("mock", "working.streams",
                 attribute = "gradient", threshold = 0.05,
                 overwrite = FALSE)

  expect_length(sql_log, 1)
  expect_match(sql_log[1], "CREATE TABLE")
})


# --- Unit tests: frs_break_validate ---

test_that("frs_break_validate validates identifiers", {
  expect_error(
    frs_break_validate("mock", "DROP foo", "evidence.table"),
    "invalid characters"
  )
})

test_that("frs_break_validate builds SQL with where filter", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_break_validate("mock", "working.breaks",
                     evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
                     where = "e.species_code IN ('CO', 'CH')")

  expect_length(sql_log, 1)
  expect_match(sql_log[1], "DELETE FROM working.breaks")
  expect_match(sql_log[1], "species_code IN \\('CO', 'CH'\\)")
})

test_that("frs_break_validate builds SQL without where filter", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_break_validate("mock", "working.breaks",
                     evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw")

  expect_match(sql_log[1], "DELETE FROM working.breaks")
  # The base SQL has "e.downstream_route_measure" for the upstream check,
  # but there should be no additional user-specified filter
  # Count the "AND e." occurrences — only the built-in measure check
  and_e_count <- lengths(regmatches(sql_log[1],
    gregexpr("AND e\\.", sql_log[1])))
  expect_equal(and_e_count, 1L)  # only e.downstream_route_measure
})

test_that("frs_break_validate returns conn invisibly", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  result <- frs_break_validate("mock_conn", "working.breaks",
                               "bcfishobs.table")
  expect_equal(result, "mock_conn")
})


# --- Unit tests: frs_break_apply ---

test_that("frs_break_apply validates identifiers", {
  expect_error(
    frs_break_apply("mock", "DROP TABLE foo", "working.breaks"),
    "invalid characters"
  )
})

test_that("frs_break_apply builds 4 SQL statements with carried columns", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    },
    .frs_table_columns = function(conn, table, exclude_generated = FALSE) {
      c("linear_feature_id", "blue_line_key", "gradient",
        "downstream_route_measure", "upstream_route_measure", "geom")
    }
  )

  frs_break_apply("mock", "working.streams", "working.breaks")

  # temp create, shorten, insert, temp drop
  expect_length(sql_log, 4)
  expect_match(sql_log[1], "CREATE TEMPORARY TABLE temp_broken_streams")
  expect_match(sql_log[1], "ST_LocateBetween")
  expect_match(sql_log[2], "UPDATE working.streams")
  expect_match(sql_log[3], "INSERT INTO working.streams")
  # Carried columns should appear in INSERT
  expect_match(sql_log[3], "blue_line_key")
  expect_match(sql_log[3], "gradient")
  expect_match(sql_log[3], "s\\.blue_line_key")
  expect_match(sql_log[4], "DROP TABLE IF EXISTS temp_broken_streams")
})

test_that("frs_break_apply returns conn invisibly", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L,
    .frs_table_columns = function(conn, table, exclude_generated = FALSE) {
      c("linear_feature_id", "downstream_route_measure",
        "upstream_route_measure", "geom")
    }
  )

  result <- frs_break_apply("mock_conn", "working.streams", "working.breaks")
  expect_equal(result, "mock_conn")
})


# --- Unit tests: frs_break wrapper ---

test_that("frs_break calls find, validate, apply in sequence", {
  call_log <- character(0)

  mockery::stub(frs_break, "frs_break_find", function(...) {
    call_log <<- c(call_log, "find")
    invisible("mock")
  })
  mockery::stub(frs_break, "frs_break_validate", function(...) {
    call_log <<- c(call_log, "validate")
    invisible("mock")
  })
  mockery::stub(frs_break, "frs_break_apply", function(...) {
    call_log <<- c(call_log, "apply")
    invisible("mock")
  })

  frs_break("mock", "working.streams",
            attribute = "gradient", threshold = 0.05,
            evidence_table = "bcfishobs.table",
            where = "e.species_code = 'CO'")

  expect_equal(call_log, c("find", "validate", "apply"))
})

test_that("frs_break skips validate when no evidence_table", {
  call_log <- character(0)

  mockery::stub(frs_break, "frs_break_find", function(...) {
    call_log <<- c(call_log, "find")
    invisible("mock")
  })
  mockery::stub(frs_break, "frs_break_validate", function(...) {
    call_log <<- c(call_log, "validate")
    invisible("mock")
  })
  mockery::stub(frs_break, "frs_break_apply", function(...) {
    call_log <<- c(call_log, "apply")
    invisible("mock")
  })

  frs_break("mock", "working.streams",
            attribute = "gradient", threshold = 0.05)

  expect_equal(call_log, c("find", "apply"))
})


# --- Integration tests (live DB, Byman-Ailport AOI) ---

.test_aoi <- function() {
  readRDS(system.file("extdata", "test_streamline.rds", package = "fresh"))
}

test_that("frs_break_find attribute mode creates breaks table", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_break_streams")
    .frs_test_drop(conn, "working.test_break_find")
    DBI::dbDisconnect(conn)
  })

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_break_streams",
    cols = c("linear_feature_id", "blue_line_key",
             "downstream_route_measure", "upstream_route_measure",
             "gradient", "geom"),
    aoi = .test_aoi()
  )

  # Use fwa_slopealonginterval to find gradient breaks at 100m resolution
  frs_break_find(conn,
    table = "working.test_break_streams",
    to = "working.test_break_find",
    attribute = "gradient",
    threshold = 0.02
  )

  count <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_break_find")
  expect_true(count$n > 0)

  cols <- DBI::dbGetQuery(conn,
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'working' AND table_name = 'test_break_find'
     ORDER BY ordinal_position")
  expect_true("blue_line_key" %in% cols$column_name)
  expect_true("downstream_route_measure" %in% cols$column_name)
})

test_that("frs_break_apply splits stream segments", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_break_apply_streams")
    .frs_test_drop(conn, "working.test_break_apply_breaks")
    DBI::dbDisconnect(conn)
  })

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_break_apply_streams",
    cols = c("linear_feature_id", "blue_line_key",
             "downstream_route_measure", "upstream_route_measure",
             "gradient", "geom"),
    aoi = .test_aoi()
  )

  count_before <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_break_apply_streams")

  # Find gradient breaks at 100m resolution, threshold 2%
  frs_break_find(conn,
    table = "working.test_break_apply_streams",
    to = "working.test_break_apply_breaks",
    attribute = "gradient",
    threshold = 0.02
  )

  n_breaks <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_break_apply_breaks")

  frs_break_apply(conn,
    table = "working.test_break_apply_streams",
    breaks = "working.test_break_apply_breaks"
  )

  # Count after — should have more rows if breaks fell within segments
  count_after <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_break_apply_streams")
  expect_true(count_after$n >= count_before$n)
  # If there were breaks, we should see new segments
  if (n_breaks$n > 0) {
    expect_true(count_after$n > count_before$n)
  }
})
