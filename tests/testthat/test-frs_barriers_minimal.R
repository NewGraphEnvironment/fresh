# -- input validation (mocked) -----------------------------------------------

test_that("frs_barriers_minimal rejects invalid identifiers", {
  expect_error(
    frs_barriers_minimal("mock", from = "bad;name"),
    "source table"
  )
  expect_error(
    frs_barriers_minimal("mock", from = "working.barriers", to = "bad;name"),
    "destination table"
  )
})

test_that("frs_barriers_minimal rejects invalid tolerance", {
  expect_error(
    frs_barriers_minimal("mock", from = "working.barriers", tolerance = -1),
    "tolerance must be a single non-negative numeric"
  )
  expect_error(
    frs_barriers_minimal("mock", from = "working.barriers", tolerance = c(1, 2)),
    "tolerance must be a single non-negative numeric"
  )
  expect_error(
    frs_barriers_minimal("mock", from = "working.barriers", tolerance = "one"),
    "tolerance must be a single non-negative numeric"
  )
})

test_that("frs_barriers_minimal generates SQL with fwa_upstream self-join", {
  captured <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql, ...) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  # mock connection is NOT a DBIConnection, so schema-column check is skipped
  frs_barriers_minimal("mock-conn",
    from = "working.barriers_raw",
    to   = "working.barriers_minimal")

  delete_sql <- paste(captured, collapse = "\n")
  expect_match(delete_sql, "DROP TABLE IF EXISTS working.barriers_minimal")
  expect_match(delete_sql, "CREATE TABLE working.barriers_minimal AS SELECT \\* FROM working.barriers_raw")
  expect_match(delete_sql, "DELETE FROM working.barriers_minimal")
  expect_match(delete_sql, "whse_basemapping.fwa_upstream")
  expect_match(delete_sql, "b.ctid <> a.ctid")
})

test_that("frs_barriers_minimal passes tolerance into SQL", {
  captured <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql, ...) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  frs_barriers_minimal("mock-conn",
    from = "working.barriers_raw",
    tolerance = 5)
  expect_match(paste(captured, collapse = "\n"), "false, 5\\s*\\)")

  captured <- character(0)
  frs_barriers_minimal("mock-conn",
    from = "working.barriers_raw",
    tolerance = 0.001)
  expect_match(paste(captured, collapse = "\n"), "false, 0.001\\s*\\)")
})

test_that("frs_barriers_minimal skips drop when overwrite is FALSE", {
  captured <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql, ...) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  frs_barriers_minimal("mock-conn",
    from = "working.barriers_raw",
    overwrite = FALSE)
  expect_false(any(grepl("DROP TABLE", captured)))
})

# -- live DB tests -----------------------------------------------------------

# Helper: create a synthetic barriers table with real ltree values pulled
# from fwa_stream_networks_sp. Writes to the `working` schema (assumed to
# exist with table-create permission — consistent with other fresh live
# DB tests).
.setup_synthetic_barriers <- function(conn, table) {
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", table))
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE %s (
      id integer,
      blue_line_key integer,
      downstream_route_measure double precision,
      wscode_ltree ltree,
      localcode_ltree ltree
    )", table))
  invisible(NULL)
}

.insert_synthetic_barrier <- function(conn, table, id, blk, drm) {
  DBI::dbExecute(conn, sprintf("
    INSERT INTO %s (id, blue_line_key, downstream_route_measure,
                    wscode_ltree, localcode_ltree)
    SELECT %d, %d, %f, wscode_ltree, localcode_ltree
    FROM whse_basemapping.fwa_stream_networks_sp
    WHERE blue_line_key = %d
    ORDER BY abs(downstream_route_measure - %f)
    LIMIT 1",
    table, id, blk, drm, blk, drm))
  invisible(NULL)
}

test_that("frs_barriers_minimal reduces two points on same reach to the downstream-most", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_bm_raw")
    .frs_test_drop(conn, "working.test_bm_min")
    DBI::dbDisconnect(conn)
  })

  # Find any BLK with a long reach — topology needed for upstream/downstream logic
  blk_sample <- DBI::dbGetQuery(conn, "
    SELECT blue_line_key,
           min(downstream_route_measure) AS drm_min,
           max(downstream_route_measure) AS drm_max
    FROM whse_basemapping.fwa_stream_networks_sp
    WHERE watershed_group_code = 'BULK'
      AND edge_type = 1000
    GROUP BY blue_line_key
    HAVING max(downstream_route_measure) - min(downstream_route_measure) > 5000
    ORDER BY blue_line_key
    LIMIT 1")
  skip_if(nrow(blk_sample) == 0, "no suitable BLK found for test")

  blk <- blk_sample$blue_line_key
  drm_down <- blk_sample$drm_min + 500
  drm_up   <- blk_sample$drm_min + 4500

  .setup_synthetic_barriers(conn, "working.test_bm_raw")
  .insert_synthetic_barrier(conn, "working.test_bm_raw", 1L, blk, drm_down)
  .insert_synthetic_barrier(conn, "working.test_bm_raw", 2L, blk, drm_up)

  frs_barriers_minimal(conn,
    from = "working.test_bm_raw",
    to   = "working.test_bm_min")

  result <- DBI::dbGetQuery(conn, "
    SELECT id, downstream_route_measure
    FROM working.test_bm_min
    ORDER BY id")

  expect_equal(nrow(result), 1L)
  expect_equal(result$id, 1L)  # the downstream-most one
})

test_that("frs_barriers_minimal keeps points on different blue_line_keys", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_bm_raw")
    .frs_test_drop(conn, "working.test_bm_min")
    DBI::dbDisconnect(conn)
  })

  # Two unrelated BLKs in different watersheds
  blks <- DBI::dbGetQuery(conn, "
    SELECT DISTINCT ON (watershed_group_code) blue_line_key,
           min(downstream_route_measure) AS drm_min
    FROM whse_basemapping.fwa_stream_networks_sp
    WHERE watershed_group_code IN ('ADMS', 'BULK')
      AND edge_type = 1000
    GROUP BY watershed_group_code, blue_line_key
    ORDER BY watershed_group_code, blue_line_key
    LIMIT 2")
  skip_if(nrow(blks) < 2, "not enough BLKs across watersheds")

  .setup_synthetic_barriers(conn, "working.test_bm_raw")
  .insert_synthetic_barrier(conn, "working.test_bm_raw",
    1L, blks$blue_line_key[1], blks$drm_min[1] + 100)
  .insert_synthetic_barrier(conn, "working.test_bm_raw",
    2L, blks$blue_line_key[2], blks$drm_min[2] + 100)

  frs_barriers_minimal(conn,
    from = "working.test_bm_raw",
    to   = "working.test_bm_min")

  result <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM working.test_bm_min")
  expect_equal(result$n, 2L)
})

test_that("frs_barriers_minimal errors on source table missing ltree columns", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_bm_nocols")
    DBI::dbDisconnect(conn)
  })

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_bm_nocols (
      blue_line_key integer,
      downstream_route_measure double precision
    )")

  expect_error(
    frs_barriers_minimal(conn, from = "working.test_bm_nocols"),
    "missing required columns.*wscode_ltree.*localcode_ltree"
  )
})
