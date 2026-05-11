# Tests for frs_point_match().
# Phase 1 — validation (no DB). Phase 2 — SQL composition (mocked
# .frs_db_execute). Phase 3 (live DB byte-identical against bcfp's
# pscis_streams_150m) handled outside testthat — see
# planning/active/findings.md for the procedure.

# ----- Phase 1: validation -----

test_that("`table_a` is required (no default)", {
  expect_error(
    frs_point_match(
      conn = "mock",
      table_b = "fresh.modelled_stream_crossings",
      table_to = "working_adms.pscis",
      distance_max = 100,
      col_a_id = "stream_crossing_id",
      col_b_id = "modelled_crossing_id"
    ),
    regexp = "`table_a` is required"
  )
})

test_that("`table_b` is required (no default)", {
  expect_error(
    frs_point_match(
      conn = "mock",
      table_a = "working_adms.pscis_assessment_snapped",
      table_to = "working_adms.pscis",
      distance_max = 100,
      col_a_id = "stream_crossing_id",
      col_b_id = "modelled_crossing_id"
    ),
    regexp = "`table_b` is required"
  )
})

test_that("`table_to` is required (no default)", {
  expect_error(
    frs_point_match(
      conn = "mock",
      table_a = "working_adms.pscis_assessment_snapped",
      table_b = "fresh.modelled_stream_crossings",
      distance_max = 100,
      col_a_id = "stream_crossing_id",
      col_b_id = "modelled_crossing_id"
    ),
    regexp = "`table_to` is required"
  )
})

test_that("`distance_max` must be positive scalar numeric", {
  base_args <- list(
    conn = "mock",
    table_a = "working_adms.pscis_assessment_snapped",
    table_b = "fresh.modelled_stream_crossings",
    table_to = "working_adms.pscis",
    col_a_id = "stream_crossing_id",
    col_b_id = "modelled_crossing_id"
  )

  expect_error(do.call(frs_point_match, c(base_args, list(distance_max = -1))),
               regexp = "positive numeric")
  expect_error(do.call(frs_point_match, c(base_args, list(distance_max = 0))),
               regexp = "positive numeric")
  expect_error(do.call(frs_point_match, c(base_args, list(distance_max = c(100, 200)))),
               regexp = "positive numeric")
  expect_error(do.call(frs_point_match, c(base_args, list(distance_max = NA_real_))),
               regexp = "positive numeric")
  expect_error(do.call(frs_point_match, c(base_args, list(distance_max = "100"))),
               regexp = "positive numeric")
})

test_that("identifiers reject characters outside [A-Za-z_][A-Za-z0-9_.]*", {
  base_args <- list(
    conn = "mock",
    table_a = "working_adms.pscis_assessment_snapped",
    table_b = "fresh.modelled_stream_crossings",
    table_to = "working_adms.pscis",
    distance_max = 100,
    col_a_id = "stream_crossing_id",
    col_b_id = "modelled_crossing_id"
  )

  expect_error(do.call(frs_point_match,
                       modifyList(base_args, list(table_a = "schema; DROP TABLE x"))),
               regexp = "invalid characters")
  expect_error(do.call(frs_point_match,
                       modifyList(base_args, list(col_b_id = "id with spaces"))),
               regexp = "invalid characters")
})

test_that("`col_a_id` and `col_b_id` must differ", {
  expect_error(
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.points",
      table_b = "schema_b.points",
      table_to = "schema_out.matched",
      distance_max = 100,
      col_a_id = "id",
      col_b_id = "id"
    ),
    regexp = "must differ"
  )
})

# ----- Phase 2: SQL composition (mocked .frs_db_execute) -----

with_captured_sql <- function(call_expr, cols_a = c("stream_crossing_id", "blue_line_key", "downstream_route_measure", "linear_feature_id")) {
  # RPostgres requires one statement per dbExecute call, so the
  # function dispatches DROP and CREATE separately. Capture both.
  # `.frs_table_columns` introspects table_a — also mocked.
  captured <- list()
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      captured[[length(captured) + 1L]] <<- sql
      0L
    },
    .frs_table_columns = function(conn, table, exclude_generated = FALSE) cols_a
  )
  call_expr()
  captured
}

test_that("SQL composes DROP + CREATE + same-blk join + DISTINCT ON", {
  sqls <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "working_adms.pscis_assessment_snapped",
      table_b = "fresh.modelled_stream_crossings",
      table_to = "working_adms.pscis",
      distance_max = 100,
      col_a_id = "stream_crossing_id",
      col_b_id = "modelled_crossing_id"
    )
  })
  expect_length(sqls, 2L)
  expect_match(sqls[[1]], "DROP TABLE IF EXISTS working_adms\\.pscis")
  expect_match(sqls[[2]], "CREATE TABLE working_adms\\.pscis AS")
  expect_match(sqls[[2]], "DISTINCT ON \\(stream_crossing_id, blue_line_key\\)")
  expect_match(sqls[[2]], "a\\.blue_line_key = b\\.blue_line_key")
})

test_that("SQL applies bidirectional dedup via ROW_NUMBER OVER (PARTITION BY b_id)", {
  sqls <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      col_a_id = "a_id",
      col_b_id = "b_id"
    )
  })
  # The b-side dedup is what mirrors bcfp's "ensure modelled matches one PSCIS".
  expect_match(sqls[[2]], "ROW_NUMBER\\(\\) OVER \\(\\s*\\n?\\s*PARTITION BY b_id")
  # And losers get NULL'd out via CASE WHEN b_rank = 1 ...
  expect_match(sqls[[2]], "CASE WHEN b_rank = 1 THEN ranked\\.b_id ELSE NULL END AS b_id")
})

test_that("SQL refuses table_a containing reserved output column names", {
  expect_error(
    with_captured_sql(
      function() {
        frs_point_match(
          conn = "mock",
          table_a = "schema_a.x",
          table_b = "schema_b.y",
          table_to = "schema_out.z",
          distance_max = 100,
          col_a_id = "a_id",
          col_b_id = "b_id"
        )
      },
      cols_a = c("a_id", "blue_line_key", "downstream_route_measure", "b_id")  # b_id collides
    ),
    regexp = "frs_point_match adds"
  )
})

test_that("distance_max appears as a numeric literal in the join predicate", {
  sqls <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      col_a_id = "a_id",
      col_b_id = "b_id"
    )
  })
  # ABS(a.drm - b.drm) < 100 (in the CREATE statement, sqls[[2]])
  expect_match(
    sqls[[2]],
    "ABS\\(a\\.downstream_route_measure - b\\.downstream_route_measure\\)\\s*\\n?\\s*<\\s*100"
  )
})

test_that("LEFT JOIN preserves table_a rows with no match", {
  sqls <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      col_a_id = "a_id",
      col_b_id = "b_id"
    )
  })
  expect_match(sqls[[2]], "LEFT JOIN schema_b\\.y b")
  expect_no_match(sqls[[2]], "INNER JOIN")
})

test_that("ORDER BY uses distance_instream ASC NULLS LAST for dedup tiebreak", {
  sqls <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      col_a_id = "a_id",
      col_b_id = "b_id"
    )
  })
  expect_match(sqls[[2]], "ASC NULLS LAST")
})

test_that("col_b_id carried through SELECT as named column", {
  sqls <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      col_a_id = "a_id",
      col_b_id = "b_id"
    )
  })
  expect_match(sqls[[2]], "b\\.b_id AS b_id")
})
