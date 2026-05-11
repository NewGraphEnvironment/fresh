# Tests for frs_candidates_pick().
# Tier 1: input validation (no DB). Tier 2: SQL composition via mocked
# .frs_db_execute and .frs_table_columns. Live byte-identical validation
# against bcfp's PSCIS-to-stream selection is documented in
# planning/active/task_plan.md Phase 3.

# ----- Tier 1: validation -----

test_that("`table_in` is required (no default)", {
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_to = "schema.out",
      col_key = "id",
      order_by = "score DESC"
    ),
    regexp = "`table_in` is required"
  )
})

test_that("`table_to` is required (no default)", {
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      col_key = "id",
      order_by = "score DESC"
    ),
    regexp = "`table_to` is required"
  )
})

test_that("`col_key` is required (no default)", {
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      order_by = "score DESC"
    ),
    regexp = "`col_key` is required"
  )
})

test_that("`order_by` is required and non-empty", {
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id"
    ),
    regexp = "`order_by` is required"
  )
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id",
      order_by = character(0)
    ),
    regexp = "`order_by` is required"
  )
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id",
      order_by = c("score DESC", "")  # empty string in vector
    ),
    regexp = "`order_by` is required"
  )
})

test_that("identifiers reject characters outside [A-Za-z_][A-Za-z0-9_.]*", {
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in; DROP TABLE x",
      table_to = "schema.out",
      col_key = "id",
      order_by = "score DESC"
    ),
    regexp = "invalid characters"
  )
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id with spaces",
      order_by = "score DESC"
    ),
    regexp = "invalid characters"
  )
})

test_that("`exp_score`, when supplied, must be a non-empty character", {
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id",
      exp_score = "",
      order_by = "score DESC"
    ),
    regexp = "`exp_score`"
  )
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id",
      exp_score = c("a", "b"),
      order_by = "score DESC"
    ),
    regexp = "`exp_score`"
  )
})

test_that("`exp_filter`, when supplied, must be a non-empty character", {
  expect_error(
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id",
      exp_filter = "",
      order_by = "id ASC"
    ),
    regexp = "`exp_filter`"
  )
})

# ----- Tier 2: SQL composition (mocked .frs_db_execute) -----

with_captured_sql <- function(call_expr,
                              cols_in = c("id", "blue_line_key", "distance_to_stream")) {
  # RPostgres requires one statement per dbExecute call — the function
  # dispatches DROP and CREATE separately. .frs_table_columns is only
  # called when exp_score is supplied (the reserved-column collision
  # check). Both are mocked.
  captured <- list()
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      captured[[length(captured) + 1L]] <<- sql
      0L
    },
    .frs_table_columns = function(conn, table, exclude_generated = FALSE) cols_in
  )
  call_expr()
  captured
}

test_that("SQL composes DROP + CREATE + WITH scored + DISTINCT ON + ORDER BY", {
  sqls <- with_captured_sql(function() {
    frs_candidates_pick(
      conn = "mock",
      table_in = "working_bulk.pscis_candidates",
      table_to = "working_bulk.pscis",
      col_key = "stream_crossing_id",
      exp_score = "CASE WHEN stream_name = gnis_name THEN 100 ELSE 0 END",
      exp_filter = "score >= 0",
      order_by = c("score DESC", "distance_to_stream ASC")
    )
  })
  expect_length(sqls, 2L)
  expect_match(sqls[[1]], "DROP TABLE IF EXISTS working_bulk\\.pscis")
  expect_match(sqls[[2]], "CREATE TABLE working_bulk\\.pscis AS")
  expect_match(sqls[[2]], "WITH scored AS")
  expect_match(sqls[[2]], "CASE WHEN stream_name = gnis_name THEN 100 ELSE 0 END")
  expect_match(sqls[[2]], "SELECT DISTINCT ON \\(stream_crossing_id\\)")
  expect_match(sqls[[2]], "WHERE score >= 0")
  # col_key prepended to ORDER BY
  expect_match(
    sqls[[2]],
    "ORDER BY stream_crossing_id, score DESC, distance_to_stream ASC"
  )
})

test_that("exp_score = NULL omits the WITH scored CTE", {
  sqls <- with_captured_sql(function() {
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id",
      order_by = c("assessment_date DESC")
    )
  })
  expect_no_match(sqls[[2]], "WITH scored")
  expect_match(sqls[[2]], "SELECT DISTINCT ON \\(id\\) \\*\\s*\\n\\s*FROM schema\\.in")
})

test_that("exp_filter = NULL omits the WHERE clause", {
  sqls <- with_captured_sql(function() {
    frs_candidates_pick(
      conn = "mock",
      table_in = "schema.in",
      table_to = "schema.out",
      col_key = "id",
      order_by = "id ASC"
    )
  })
  expect_no_match(sqls[[2]], "\\bWHERE\\b")
})

test_that("table_in with existing `score` column is rejected when exp_score is set", {
  expect_error(
    with_captured_sql(
      function() {
        frs_candidates_pick(
          conn = "mock",
          table_in = "schema.in",
          table_to = "schema.out",
          col_key = "id",
          exp_score = "CASE WHEN ... THEN 1 ELSE 0 END",
          order_by = "score DESC"
        )
      },
      cols_in = c("id", "score", "distance_to_stream")  # collides
    ),
    regexp = "already has a `score` column"
  )
})

test_that("table_in with `score` column is allowed when exp_score is NULL", {
  # No collision check fires when exp_score not set — caller is
  # referencing the existing score column in order_by directly.
  expect_silent({
    sqls <- with_captured_sql(
      function() {
        frs_candidates_pick(
          conn = "mock",
          table_in = "schema.in",
          table_to = "schema.out",
          col_key = "id",
          order_by = "score DESC"
        )
      },
      cols_in = c("id", "score", "distance_to_stream")
    )
  })
  expect_match(sqls[[2]], "ORDER BY id, score DESC")
})
