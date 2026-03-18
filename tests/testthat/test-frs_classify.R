# --- Unit tests (no DB) ---

test_that("frs_classify requires at least one mode", {
  expect_error(
    frs_classify("mock", "working.streams", label = "spawning"),
    "At least one"
  )
})

test_that("frs_classify validates identifiers", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )
  expect_error(
    frs_classify("mock", "DROP TABLE foo", label = "x",
                 ranges = list(gradient = c(0, 1))),
    "invalid characters"
  )
})

test_that("frs_classify ranges builds correct SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_classify("mock", "working.streams", label = "spawning",
               ranges = list(gradient = c(0, 0.025),
                             channel_width = c(2, 20)))

  # ALTER (add column) + UPDATE (set values)
  expect_length(sql_log, 2)
  expect_match(sql_log[1], "ADD COLUMN IF NOT EXISTS spawning")
  expect_match(sql_log[2], "UPDATE working.streams SET spawning = TRUE")
  expect_match(sql_log[2], "gradient BETWEEN 0 AND 0.025")
  expect_match(sql_log[2], "channel_width BETWEEN 2 AND 20")
  expect_match(sql_log[2], "AND")
})

test_that("frs_classify breaks builds correct SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_classify("mock", "working.streams", label = "accessible",
               breaks = "working.breaks")

  expect_length(sql_log, 2)
  expect_match(sql_log[2], "NOT EXISTS")
  expect_match(sql_log[2], "working.breaks")
  # Same-BLK measure comparison + cross-BLK ltree check
  expect_match(sql_log[2], "b.downstream_route_measure <= s.downstream_route_measure")
  expect_match(sql_log[2], "fwa_upstream")
})

test_that("frs_classify overrides builds correct SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_classify("mock", "working.streams", label = "spawning",
               overrides = "working.known_habitat")

  expect_length(sql_log, 2)
  expect_match(sql_log[2], "UPDATE working.streams s SET spawning = o.spawning")
  expect_match(sql_log[2], "FROM working.known_habitat o")
})

test_that("frs_classify combined modes generates 3 updates", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_classify("mock", "working.streams", label = "spawning",
               ranges = list(gradient = c(0, 0.025)),
               breaks = "working.breaks",
               overrides = "working.known_habitat")

  # ALTER + ranges UPDATE + breaks UPDATE + overrides UPDATE
  expect_length(sql_log, 4)
  expect_match(sql_log[1], "ADD COLUMN")
  expect_match(sql_log[2], "BETWEEN")
  expect_match(sql_log[3], "fwa_upstream")
  expect_match(sql_log[4], "o.spawning")
})

test_that("frs_classify value = FALSE sets FALSE", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_classify("mock", "working.streams", label = "excluded",
               ranges = list(gradient = c(0.2, 1)), value = FALSE)

  expect_match(sql_log[2], "SET excluded = FALSE")
})

test_that("frs_classify returns conn invisibly", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  result <- frs_classify("mock_conn", "working.streams", label = "x",
                         ranges = list(gradient = c(0, 1)))
  expect_equal(result, "mock_conn")
})

test_that("frs_classify validates range inputs", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  # Non-numeric range
  expect_error(
    frs_classify("mock", "working.streams", label = "x",
                 ranges = list(gradient = c("a", "b"))),
    "is.numeric"
  )

  # Wrong length

  expect_error(
    frs_classify("mock", "working.streams", label = "x",
                 ranges = list(gradient = c(0, 0.5, 1))),
    "length"
  )
})


# --- Integration tests (live DB) ---

.test_aoi <- function() {
  readRDS(system.file("extdata", "test_streamline.rds", package = "fresh"))
}

test_that("frs_classify ranges adds and populates label column", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_classify")
    DBI::dbDisconnect(conn)
  })

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_classify",
    cols = c("linear_feature_id", "blue_line_key", "gradient", "geom"),
    aoi = .test_aoi(),
    overwrite = TRUE
  )

  frs_classify(conn, "working.test_classify", label = "spawning",
               ranges = list(gradient = c(0, 0.025)))

  result <- DBI::dbGetQuery(conn,
    "SELECT spawning, count(*) AS n FROM working.test_classify GROUP BY spawning")

  # Should have both TRUE and NULL rows (some meet threshold, some don't)
  expect_true(TRUE %in% result$spawning)
  expect_true(any(is.na(result$spawning)))
})
