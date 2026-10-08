# --- Unit tests: frs_break_find ---

test_that("frs_break_find requires attribute", {
  expect_error(
    frs_break_find("mock", "working.streams"),
    "attribute is required"
  )
})

test_that("frs_break_find requires threshold or classes", {
  expect_error(
    frs_break_find("mock", "working.streams", attribute = "gradient"),
    "threshold or classes is required"
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
  expect_match(sql_log[2], "vertex_grades")
  expect_match(sql_log[2], "gradient > 0.05")
})

test_that("frs_feature_find table mode builds correct SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_feature_find("mock", "working.streams",
                   points_table = "bcfishpass.falls_events_sp")

  expect_match(sql_log[2], "FROM bcfishpass.falls_events_sp")
  expect_match(sql_log[2], "blue_line_key")
})

test_that("frs_feature_find adds BLK filter", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_feature_find("mock", "working.streams",
                   points_table = "bcfishpass.falls_events_sp")

  expect_match(sql_log[2], "WHERE.*blue_line_key IN")
})

test_that("frs_feature_find adds where filter", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_feature_find("mock", "working.streams",
                   points_table = "bcfishpass.falls_vw",
                   where = "barrier_ind = TRUE")

  expect_match(sql_log[2], "WHERE.*barrier_ind = TRUE")
})

test_that("frs_feature_find combines where and BLK filter", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_feature_find("mock", "working.streams",
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

test_that("frs_feature_find points mode rejects non-sf", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  expect_error(
    frs_feature_find("mock", "working.streams",
                     points = data.frame(x = 1, y = 2)),
    "sf object"
  )
})

test_that("frs_feature_find points mode snaps and writes features", {
  exec <- character(0)
  written <- NULL
  local_mocked_bindings(
    frs_point_snap = function(conn, points, ...) {
      expect_identical(list(...)$col_id, "site")
      sf::st_sf(site = c("a", "c"), blue_line_key = c(10L, 30L),
                downstream_route_measure = c(100, 300),
                geom = sf::st_sfc(sf::st_point(c(0, 0)),
                                  sf::st_point(c(1, 1)), crs = 3005))
    },
    .frs_db_write_temp = function(conn, df) {
      written <<- df
      "frs_tmp_mock"
    },
    .frs_db_execute = function(conn, sql) {
      exec <<- c(exec, sql)
      0L
    }
  )
  pts <- sf::st_sf(
    site = c("a", "b", "c"), kind = c("weir", "gauge", "weir"),
    geometry = sf::st_sfc(sf::st_point(c(-126.5, 54.5)),
                          sf::st_point(c(-126.6, 54.6)),
                          sf::st_point(c(-126.7, 54.4)), crs = 4326))

  expect_message(
    frs_feature_find("mock", "working.streams", to = "working.features",
                     points = pts, col_id = "site", label_col = "kind"),
    "1 of 3 points had no stream within 100 m")
  expect_identical(written$feature_id, c("a", "c"))
  expect_identical(written$label_src, c("weir", "weir"))
  create <- grep("^CREATE TABLE working.features AS", exec, value = TRUE)
  expect_length(create, 1L)
  expect_match(create, "label_src::text AS label", fixed = TRUE)
  expect_match(create,
               "'sf' AS source, feature_id::text AS feature_id FROM frs_tmp_mock",
               fixed = TRUE)
  expect_match(create, paste0("blue_line_key IN (SELECT DISTINCT ",
                              "blue_line_key FROM working.streams)"),
               fixed = TRUE)
  expect_true(any(grepl("DROP TABLE IF EXISTS frs_tmp_mock", exec)))
})

test_that("frs_feature_find points mode honours label and append", {
  exec <- character(0)
  local_mocked_bindings(
    frs_point_snap = function(conn, points, ...) {
      sf::st_sf(id_point = 1L, blue_line_key = 10L,
                downstream_route_measure = 100,
                geom = sf::st_sfc(sf::st_point(c(0, 0)), crs = 3005))
    },
    .frs_db_write_temp = function(conn, df) "frs_tmp_mock",
    .frs_db_execute = function(conn, sql) {
      exec <<- c(exec, sql)
      0L
    }
  )
  pts <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(-126.5, 54.5)),
                                         crs = 4326))
  frs_feature_find("mock", "working.streams", to = "working.features",
                   points = pts, label = "station", append = TRUE)
  expect_false(any(grepl("DROP TABLE IF EXISTS working.features", exec)))
  expect_true(any(grepl("CREATE TABLE IF NOT EXISTS working.features",
                        exec)))
  insert <- grep("^INSERT INTO working.features", exec, value = TRUE)
  expect_length(insert, 1L)
  expect_match(insert, "'station' AS label", fixed = TRUE)
  expect_no_match(insert, "feature_id")
})

test_that("frs_feature_find refuses a `to` it would read", {
  expect_error(
    frs_feature_find("mock", "working.streams", to = "WORKING.streams",
                     points_table = "working.falls"),
    "to must differ from table and points_table")
  expect_error(
    frs_feature_find("mock", "working.streams", to = "working.falls",
                     points_table = "working.falls"),
    "to must differ from table and points_table")
})

test_that("label_map compares and returns label_col as text", {
  expr <- .frs_label_expr(label_col = "barrier_ind",
                          label_map = c("TRUE" = "blocked"))
  expect_match(expr,
               "WHEN lower(barrier_ind::text) IN ('true', 'true') THEN 'blocked'",
               fixed = TRUE)
  expr <- .frs_label_expr(label_col = "barrier_ind",
                          label_map = c("t" = "blocked", "F" = "passable"))
  expect_match(expr,
               "WHEN lower(barrier_ind::text) IN ('t', 'true') THEN 'blocked'",
               fixed = TRUE)
  expect_match(expr,
               "WHEN lower(barrier_ind::text) IN ('f', 'false') THEN 'passable'",
               fixed = TRUE)
  expect_match(expr, "ELSE barrier_ind::text END AS label", fixed = TRUE)
  # Other keys stay exact
  expr <- .frs_label_expr(label_col = "status",
                          label_map = c("BARRIER" = "blocked"))
  expect_match(expr, "WHEN status::text = 'BARRIER' THEN 'blocked'",
               fixed = TRUE)
})

test_that("frs_feature_find points mode checks label_col", {
  local_mocked_bindings(.frs_db_execute = function(conn, sql) 0L)
  pts <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326))
  expect_error(
    frs_feature_find("mock", "working.streams", points = pts,
                     label_col = "kind"),
    "label_col 'kind' is not a column of points")
})

test_that("frs_feature_find snaps real sf points onto the network (live)", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_ff_streams")
    .frs_test_drop(conn, "working.test_ff_pts")
    .frs_test_drop(conn, "working.test_ff_out")
    DBI::dbDisconnect(conn)
  })

  # Points already on streams: snap three sites, keep the snapped positions
  sites <- data.frame(site = c("a", "b", "c"), x = c(-126.5, -126.6, -126.7),
                      y = c(54.5, 54.6, 54.4))
  on_stream <- frs_point_snap(conn, sites, col_id = "site", tolerance = 1000)
  pts <- sf::st_transform(on_stream[, "site"], 4326)
  pts$kind <- c("weir", "gauge", "weir")

  # Working streams hold the BLKs of sites a and b only
  .frs_test_drop(conn, "working.test_ff_streams")
  DBI::dbExecute(conn, sprintf(paste(
    "CREATE TABLE working.test_ff_streams AS",
    "SELECT DISTINCT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp",
    "WHERE blue_line_key IN (%s)"),
    paste(on_stream$blue_line_key[on_stream$site != "c"], collapse = ", ")))

  frs_feature_find(conn, "working.test_ff_streams", to = "working.test_ff_out",
                   points = pts, col_id = "site", label_col = "kind")
  out <- DBI::dbGetQuery(conn, paste(
    "SELECT feature_id, blue_line_key, downstream_route_measure, label,",
    "source FROM working.test_ff_out ORDER BY feature_id"))
  keep <- on_stream$site != "c" &
    !on_stream$blue_line_key %in% on_stream$blue_line_key[on_stream$site == "c"]
  expect_gt(sum(keep), 0L)
  expect_lt(sum(keep), 3L)
  expect_equal(out$feature_id, on_stream$site[keep])
  expect_equal(out$blue_line_key, on_stream$blue_line_key[keep])
  expect_equal(out$downstream_route_measure,
               on_stream$downstream_route_measure[keep])
  expect_equal(out$label, pts$kind[keep])
  expect_true(all(out$source == "sf"))

  # A double id is written as its digits, and a points append lands in a
  # table the table path created (both write feature_id as text)
  pts_num <- pts
  pts_num$site_num <- c(100000, 200000, 300000)
  .frs_test_drop(conn, "working.test_ff_pts")
  DBI::dbExecute(conn, paste(
    "CREATE TABLE working.test_ff_pts AS",
    "SELECT blue_line_key, 0::double precision AS downstream_route_measure,",
    "  1 AS fid FROM working.test_ff_streams"))
  frs_feature_find(conn, "working.test_ff_streams", to = "working.test_ff_out",
                   points_table = "working.test_ff_pts", col_id = "fid")
  frs_feature_find(conn, "working.test_ff_streams", to = "working.test_ff_out",
                   points = pts_num, col_id = "site_num", append = TRUE)
  ids <- DBI::dbGetQuery(conn, paste(
    "SELECT feature_id FROM working.test_ff_out WHERE source = 'sf'",
    "ORDER BY feature_id"))$feature_id
  expect_equal(ids, format(pts_num$site_num[keep], scientific = FALSE))

  # 16-digit whole-number ids keep every digit; an integer label_col maps
  pts_num$site_num <- c(1234567890123456, 1234567890123457, 1234567890123458)
  pts_num$code <- c(1L, 2L, 1L)
  frs_feature_find(conn, "working.test_ff_streams", to = "working.test_ff_out",
                   points = pts_num, col_id = "site_num", label_col = "code",
                   label_map = c("1" = "blocked"))
  out <- DBI::dbGetQuery(conn, paste(
    "SELECT feature_id, label FROM working.test_ff_out ORDER BY feature_id"))
  expect_equal(out$feature_id,
               c("1234567890123456", "1234567890123457")[keep[1:2]])
  expect_equal(out$label, c("blocked", "2")[keep[1:2]])

  # A logical label_col reaches the DB as boolean ('true' as text); a
  # "TRUE" key still maps it
  pts_num$barrier <- c(TRUE, FALSE, TRUE)
  frs_feature_find(conn, "working.test_ff_streams", to = "working.test_ff_out",
                   points = pts_num, col_id = "site_num",
                   label_col = "barrier", label_map = c("TRUE" = "blocked"))
  out <- DBI::dbGetQuery(conn, paste(
    "SELECT label FROM working.test_ff_out ORDER BY feature_id"))
  expect_equal(out$label, c("blocked", "false")[keep[1:2]])

  # psql-style keys
  frs_feature_find(conn, "working.test_ff_streams", to = "working.test_ff_out",
                   points = pts_num, col_id = "site_num",
                   label_col = "barrier",
                   label_map = c("t" = "blocked", "f" = "passable"))
  out <- DBI::dbGetQuery(conn, paste(
    "SELECT label FROM working.test_ff_out ORDER BY feature_id"))
  expect_equal(out$label, c("blocked", "passable")[keep[1:2]])

  # A call that fails after its checks leaves the existing `to` alone
  expect_error(frs_feature_find(conn, "working.test_ff_streams",
                                to = "working.test_ff_out", points = pts_num,
                                label_col = "nope"),
               "label_col 'nope' is not a column of points")
  expect_true(DBI::dbExistsTable(
    conn, DBI::Id(schema = "working", table = "test_ff_out")))
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

test_that("frs_break forwards only arguments its helpers accept", {
  # The find stub swallows `...`, so an argument frs_break_find() dropped
  # would pass silently; compare names against the real formals instead.
  args_find <- NULL
  args_apply <- NULL
  mockery::stub(frs_break, "frs_break_find", function(...) {
    args_find <<- names(list(...))
    invisible("mock")
  })
  mockery::stub(frs_break, "frs_break_apply", function(...) {
    args_apply <<- names(list(...))
    invisible("mock")
  })

  frs_break("mock", "working.streams",
            attribute = "gradient", threshold = 0.05)

  named <- function(x) x[nzchar(x)]
  expect_true(all(named(args_find) %in% names(formals(frs_break_find))))
  expect_true(all(named(args_apply) %in% names(formals(frs_break_apply))))
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
