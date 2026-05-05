# Validation-layer tests for frs_network_features().
# Phase 1 of #201: confirms the function rejects malformed input
# before reaching SQL composition. SQL-composition tests + live
# parity tests land in Phase 2 + Phase 3.

test_that("`direction` is required (no default)", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id"
    ),
    regexp = "`direction` is required"
  )
})

test_that("`direction` must be one of downstream/upstream", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "sideways"
    ),
    regexp = "should be one of|'arg' should be one of"
  )
})

test_that("`feature_id_col` is required (no default)", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      direction = "downstream"
    ),
    regexp = "`feature_id_col` is required"
  )
})

test_that("identifiers reject characters outside [A-Za-z_][A-Za-z0-9_.]*", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams; DROP TABLE x",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream"
    ),
    regexp = "invalid characters"
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id with spaces",
      direction = "downstream"
    ),
    regexp = "invalid characters"
  )
})

test_that("`aoi` must be a WSG code matching [A-Z]{3,5}", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = "lowercase"
    ),
    regexp = "watershed group code"
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = "AB"
    ),
    regexp = "watershed group code"
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = ""
    ),
    regexp = "non-empty"
  )
})

test_that("`include_equivalents` must be a single non-NA logical", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      include_equivalents = NA
    )
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      include_equivalents = c(TRUE, FALSE)
    )
  )
})

## SQL composition (Phase 2) — mocked via local_mocked_bindings ----------

test_that("downstream direction composes fwa_downstream predicate", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = "s1", feature_ids = "{f1}")
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "modelled_crossing_id",
    direction = "downstream"
  )
  expect_match(captured, "whse_basemapping\\.fwa_downstream\\(")
  expect_no_match(captured, "fwa_upstream")
})

test_that("upstream direction composes fwa_upstream predicate", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = "s1", feature_ids = "{f1}")
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "modelled_crossing_id",
    direction = "upstream"
  )
  expect_match(captured, "whse_basemapping\\.fwa_upstream\\(")
  expect_no_match(captured, "fwa_downstream")
})

test_that("segments-first / features-second arg order in fwa predicate", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = "s1", feature_ids = "{f1}")
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream"
  )
  # `a.` (segments alias) appears before `b.` (features alias) inside the
  # fwa_downstream() arg list — bcfp pattern.
  pos_a <- regexpr("a\\.blue_line_key", captured)
  pos_b <- regexpr("b\\.blue_line_key", captured)
  expect_true(pos_a > 0 && pos_b > 0 && pos_a < pos_b)
})

test_that("aoi injects WHERE on watershed_group_code", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = character(), feature_ids = character())
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream",
    aoi = "ADMS"
  )
  expect_match(captured, "WHERE a\\.watershed_group_code = 'ADMS'")
})

test_that("aoi NULL omits the WHERE clause", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = character(), feature_ids = character())
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream"
  )
  expect_no_match(captured, "watershed_group_code")
})

test_that("include_equivalents = FALSE (default) produces 'false' in SQL", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = character(), feature_ids = character())
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream"
  )
  expect_match(captured, "false, 1")
})

test_that("include_equivalents = TRUE produces 'true' in SQL", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = character(), feature_ids = character())
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream",
    include_equivalents = TRUE
  )
  expect_match(captured, "true, 1")
})

test_that("returned tibble preserves segment_id_col name verbatim", {
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      # frs_db_query returns the segment_id column under the alias used in
      # SELECT (here `segment_id`). The function should rename to match the
      # caller's segment_id_col input.
      tibble::tibble(segment_id = c("s1", "s2"),
                     feature_ids = c("{f1}", "{f2,f3}"))
    }
  )
  out <- frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    segment_id_col = "linear_feature_id",
    feature_id_col = "id",
    direction = "downstream"
  )
  expect_named(out, c("linear_feature_id", "feature_ids"))
})

## #204: wscode_col / localcode_col + array parsing -----------------------

test_that("wscode/localcode args default to ltree-suffixed names on both sides", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = character(), feature_ids = character())
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream"
  )
  expect_match(captured, "a\\.wscode_ltree")
  expect_match(captured, "a\\.localcode_ltree")
  expect_match(captured, "b\\.wscode_ltree")
  expect_match(captured, "b\\.localcode_ltree")
})

test_that("features-side override threads through SQL (segments stay default)", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = character(), feature_ids = character())
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "bcfishpass.streams",
    features = "bcfishpass.observations",
    feature_id_col = "observation_key",
    direction = "upstream",
    features_wscode_col = "wscode",
    features_localcode_col = "localcode"
  )
  # Segments side keeps the ltree default; features side gets the override.
  expect_match(captured, "a\\.wscode_ltree, a\\.localcode_ltree")
  expect_match(captured, "b\\.wscode, b\\.localcode")
  expect_match(captured, "ORDER BY a\\.id_segment,\\s+b\\.wscode DESC,\\s+b\\.localcode DESC")
})

test_that("segments-side and features-side overrides are independent", {
  captured <- NULL
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      captured <<- sql
      tibble::tibble(segment_id = character(), feature_ids = character())
    }
  )
  frs_network_features(
    conn = "mock",
    segments = "weird.segments",
    features = "weird.features",
    feature_id_col = "id",
    direction = "downstream",
    segments_wscode_col = "ws_a",
    segments_localcode_col = "lc_a",
    features_wscode_col = "ws_b",
    features_localcode_col = "lc_b"
  )
  expect_match(captured, "a\\.ws_a, a\\.lc_a")
  expect_match(captured, "b\\.ws_b, b\\.lc_b")
})

test_that("wscode/localcode args reject invalid identifiers", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      segments_wscode_col = "wscode; DROP TABLE x"
    ),
    regexp = "invalid characters"
  )
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      features_localcode_col = "loc'al"
    ),
    regexp = "invalid characters"
  )
})

test_that("feature_ids returned as list-column of character vectors", {
  local_mocked_bindings(
    frs_db_query = function(conn, sql, ...) {
      tibble::tibble(
        segment_id = c("s1", "s2", "s3"),
        feature_ids = c("{f1}", "{f2,f3,f4}", "{}")
      )
    }
  )
  out <- frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream"
  )
  expect_type(out$feature_ids, "list")
  expect_equal(out$feature_ids[[1]], "f1")
  expect_equal(out$feature_ids[[2]], c("f2", "f3", "f4"))
  expect_equal(out$feature_ids[[3]], character(0))
  expect_equal(lengths(out$feature_ids), c(1L, 3L, 0L))
})

test_that(".frs_parse_pg_array handles edge cases", {
  expect_equal(.frs_parse_pg_array("{a,b,c}"), c("a", "b", "c"))
  expect_equal(.frs_parse_pg_array("{single}"), "single")
  expect_equal(.frs_parse_pg_array("{}"), character(0))
  expect_equal(.frs_parse_pg_array(NA_character_), character(0))
  expect_equal(.frs_parse_pg_array(NA), character(0))
  expect_equal(.frs_parse_pg_array("not-an-array"), character(0))
  expect_equal(.frs_parse_pg_array("{a,NULL,c}"),
               c("a", NA_character_, "c"))
})
