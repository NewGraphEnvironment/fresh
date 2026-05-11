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
      table_a_id_col = "stream_crossing_id",
      table_b_id_col = "modelled_crossing_id"
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
      table_a_id_col = "stream_crossing_id",
      table_b_id_col = "modelled_crossing_id"
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
      table_a_id_col = "stream_crossing_id",
      table_b_id_col = "modelled_crossing_id"
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
    table_a_id_col = "stream_crossing_id",
    table_b_id_col = "modelled_crossing_id"
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
    table_a_id_col = "stream_crossing_id",
    table_b_id_col = "modelled_crossing_id"
  )

  expect_error(do.call(frs_point_match,
                       modifyList(base_args, list(table_a = "schema; DROP TABLE x"))),
               regexp = "invalid characters")
  expect_error(do.call(frs_point_match,
                       modifyList(base_args, list(table_b_id_col = "id with spaces"))),
               regexp = "invalid characters")
})

test_that("`table_a_id_col` and `table_b_id_col` must differ", {
  expect_error(
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.points",
      table_b = "schema_b.points",
      table_to = "schema_out.matched",
      distance_max = 100,
      table_a_id_col = "id",
      table_b_id_col = "id"
    ),
    regexp = "must differ"
  )
})

# ----- Phase 2: SQL composition (mocked .frs_db_execute) -----

with_captured_sql <- function(call_expr) {
  captured <- NULL
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      captured <<- sql
      0L
    }
  )
  call_expr()
  captured
}

test_that("SQL composes DROP + CREATE + same-blk join + DISTINCT ON", {
  sql <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "working_adms.pscis_assessment_snapped",
      table_b = "fresh.modelled_stream_crossings",
      table_to = "working_adms.pscis",
      distance_max = 100,
      table_a_id_col = "stream_crossing_id",
      table_b_id_col = "modelled_crossing_id"
    )
  })
  expect_match(sql, "DROP TABLE IF EXISTS working_adms\\.pscis")
  expect_match(sql, "CREATE TABLE working_adms\\.pscis AS")
  expect_match(sql, "DISTINCT ON \\(a\\.stream_crossing_id, a\\.blue_line_key\\)")
  expect_match(sql, "a\\.blue_line_key = b\\.blue_line_key")
})

test_that("distance_max appears as a numeric literal in the join predicate", {
  sql <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      table_a_id_col = "a_id",
      table_b_id_col = "b_id"
    )
  })
  # ABS(a.drm - b.drm) < 100
  expect_match(sql, "ABS\\(a\\.downstream_route_measure - b\\.downstream_route_measure\\)\\s*\\n?\\s*<\\s*100")
})

test_that("LEFT JOIN preserves table_a rows with no match", {
  sql <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      table_a_id_col = "a_id",
      table_b_id_col = "b_id"
    )
  })
  expect_match(sql, "LEFT JOIN schema_b\\.y b")
  expect_no_match(sql, "INNER JOIN")
})

test_that("ORDER BY uses distance_instream ASC NULLS LAST for dedup tiebreak", {
  sql <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      table_a_id_col = "a_id",
      table_b_id_col = "b_id"
    )
  })
  expect_match(sql, "ASC NULLS LAST")
})

test_that("table_b_id_col carried through SELECT as named column", {
  sql <- with_captured_sql(function() {
    frs_point_match(
      conn = "mock",
      table_a = "schema_a.x",
      table_b = "schema_b.y",
      table_to = "schema_out.z",
      distance_max = 100,
      table_a_id_col = "a_id",
      table_b_id_col = "b_id"
    )
  })
  expect_match(sql, "b\\.b_id AS b_id")
})
