test_that("frs_categorize builds correct CASE SQL", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  frs_categorize("mock", "working.streams",
    label = "habitat_type",
    cols = c("co_spawning", "co_rearing", "accessible"),
    values = c("CO_SPAWNING", "CO_REARING", "ACCESSIBLE"),
    default = "INACCESSIBLE")

  # ALTER (add column) + UPDATE (CASE)
  expect_length(sql_log, 2)
  expect_match(sql_log[1], "ADD COLUMN IF NOT EXISTS habitat_type text")
  expect_match(sql_log[2], "UPDATE working.streams SET habitat_type = CASE")
  expect_match(sql_log[2], "WHEN co_spawning IS TRUE THEN 'CO_SPAWNING'")
  expect_match(sql_log[2], "WHEN co_rearing IS TRUE THEN 'CO_REARING'")
  expect_match(sql_log[2], "WHEN accessible IS TRUE THEN 'ACCESSIBLE'")
  expect_match(sql_log[2], "ELSE 'INACCESSIBLE'")
})

test_that("frs_categorize respects priority order", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  # Spawning before rearing — spawning should appear first in CASE
  frs_categorize("mock", "working.streams",
    label = "type",
    cols = c("spawning", "rearing"),
    values = c("SPAWN", "REAR"))

  expect_match(sql_log[2], "WHEN spawning.*WHEN rearing")
})

test_that("frs_categorize validates inputs", {
  expect_error(
    frs_categorize("mock", "DROP TABLE foo",
      label = "x", cols = "a", values = "A"),
    "invalid characters")

  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  # Mismatched lengths
  expect_error(
    frs_categorize("mock", "working.streams",
      label = "x", cols = c("a", "b"), values = "A"),
    "length")
})

test_that("frs_categorize returns conn invisibly", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  result <- frs_categorize("mock_conn", "working.streams",
    label = "x", cols = "a", values = "A")
  expect_equal(result, "mock_conn")
})
