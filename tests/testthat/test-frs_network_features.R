# Validation-layer tests for frs_network_features().
# Phase 1 of #201: confirms the function rejects malformed input
# before reaching SQL composition. SQL-composition tests + live
# parity tests land in Phase 2 + Phase 3.

# Mock both DB entry points. `.frs_db_execute` records each statement
# (the aoi path's temp-table DDL and its DROP); `frs_db_query` records the
# walk. `query_fn` replaces the walk's return, e.g. to make it throw.
mock_nf_db <- function(query_fn = NULL, exec_fn = NULL, env = parent.frame()) {
  rec <- new.env()
  rec$exec <- character(0)
  rec$query <- NULL
  testthat::local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      rec$exec <- c(rec$exec, sql)
      if (!is.null(exec_fn)) exec_fn(sql)
      0L
    },
    frs_db_query = function(conn, sql, ...) {
      rec$query <- sql
      if (!is.null(query_fn)) return(query_fn(sql))
      tibble::tibble(segment_id = character(), feature_ids = character())
    },
    .env = env
  )
  rec
}

# The temp table's name, read from the CREATE statement.
nf_tmp_name <- function(rec) {
  create <- grep("^CREATE TEMP TABLE", rec$exec, value = TRUE)
  regmatches(create, regexpr("pg_temp\\.frs_tmp_[a-z0-9]+", create))
}

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

test_that("aoi scopes segments in the temp table's DDL, not the walk's WHERE", {
  rec <- mock_nf_db()
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream",
    aoi = "ADMS"
  )
  create <- grep("^CREATE TEMP TABLE", rec$exec, value = TRUE)
  expect_length(create, 1L)
  expect_match(create, "FROM fresh.streams WHERE watershed_group_code = 'ADMS'",
               fixed = TRUE)
  expect_no_match(rec$query, "watershed_group_code")
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

## #272: aoi-scoped downstream walk — temp table + feature prefilter ------

test_that("downstream + aoi builds an indexed, analyzed temp table first", {
  rec <- mock_nf_db()
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream",
    aoi = "ADMS"
  )
  tmp <- nf_tmp_name(rec)
  expect_length(tmp, 1L)
  ddl <- rec$exec[!grepl("^DROP", rec$exec)]
  expect_match(ddl[1], paste0(
    "CREATE TEMP TABLE ", tmp, " AS SELECT id_segment, blue_line_key, ",
    "downstream_route_measure, wscode_ltree, localcode_ltree FROM fresh.streams"
  ), fixed = TRUE)
  expect_true(any(ddl == sprintf("CREATE INDEX ON %s (blue_line_key)", tmp)))
  expect_true(any(ddl == sprintf("CREATE INDEX ON %s USING gist (wscode_ltree)", tmp)))
  expect_true(any(ddl == sprintf("CREATE INDEX ON %s USING gist (localcode_ltree)", tmp)))
  expect_identical(ddl[length(ddl)], sprintf("ANALYZE %s", tmp))
  expect_length(ddl, 5L)
})

test_that("downstream + aoi walks the temp table against prefiltered features", {
  rec <- mock_nf_db()
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream",
    aoi = "ADMS"
  )
  tmp <- nf_tmp_name(rec)
  q <- rec$query
  expect_match(q, sprintf("FROM %s a\\s+INNER JOIN \\(", gsub(".", "\\.", tmp, fixed = TRUE)))
  # only the five columns the walk reads, so a view's geom is not materialized
  projection <- paste0(
    "SELECT f.id, f.blue_line_key, f.downstream_route_measure, ",
    "f.wscode_ltree, f.localcode_ltree\\s+FROM fresh.crossings f"
  )
  expect_match(q, projection)
  expect_match(q, "f.wscode_ltree = ANY (ARRAY(", fixed = TRUE)
  expect_match(q, sprintf("SELECT DISTINCT subpath(s.wscode_ltree, 0, k) FROM %s s", tmp),
               fixed = TRUE)
  expect_match(q, "generate_series(1, nlevel(s.wscode_ltree)) k", fixed = TRUE)
  blk_arm <- sprintf(
    "OR f.blue_line_key = ANY (ARRAY(SELECT DISTINCT s.blue_line_key FROM %s s))", tmp
  )
  expect_match(q, blk_arm, fixed = TRUE)
  expect_match(q, "\\) b ON\\s+whse_basemapping\\.fwa_downstream\\(")
  expect_no_match(q, "fresh\\.streams")
})

test_that("aoi = NULL sends no DDL and no prefilter", {
  rec <- mock_nf_db()
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream"
  )
  expect_length(rec$exec, 0L)
  expect_no_match(rec$query, "subpath|ANY \\(ARRAY|frs_tmp_")
  expect_match(rec$query, "FROM fresh.streams a\\s+INNER JOIN fresh.crossings b ON")
})

test_that("direction = upstream sends no DDL and no prefilter, with or without aoi", {
  for (aoi in list(NULL, "ADMS")) {
    rec <- mock_nf_db()
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "upstream",
      aoi = aoi
    )
    expect_length(rec$exec, 0L)
    expect_no_match(rec$query, "subpath|ANY \\(ARRAY|frs_tmp_")
    expect_match(rec$query, "FROM fresh.streams a\\s+INNER JOIN fresh.crossings b ON")
    if (!is.null(aoi)) {
      expect_match(rec$query, "WHERE a\\.watershed_group_code = 'ADMS'")
    }
  }
})

test_that("per-side code columns thread into the temp table and the prefilter", {
  rec <- mock_nf_db()
  frs_network_features(
    conn = "mock",
    segments = "weird.segments",
    features = "weird.features",
    feature_id_col = "id",
    direction = "downstream",
    aoi = "ADMS",
    segments_wscode_col = "ws_a",
    segments_localcode_col = "lc_a",
    features_wscode_col = "ws_b",
    features_localcode_col = "lc_b"
  )
  tmp <- nf_tmp_name(rec)
  expect_match(rec$exec[1], "SELECT id_segment, blue_line_key, downstream_route_measure, ws_a, lc_a FROM",
               fixed = TRUE)
  expect_true(any(rec$exec == sprintf("CREATE INDEX ON %s USING gist (ws_a)", tmp)))
  expect_true(any(rec$exec == sprintf("CREATE INDEX ON %s USING gist (lc_a)", tmp)))
  q <- rec$query
  expect_match(q, "SELECT f.id, f.blue_line_key, f.downstream_route_measure, f.ws_b, f.lc_b",
               fixed = TRUE)
  expect_match(q, "f.ws_b = ANY (ARRAY(", fixed = TRUE)
  expect_match(q, "subpath(s.ws_a, 0, k)", fixed = TRUE)
  expect_match(q, "nlevel(s.ws_a)", fixed = TRUE)
  expect_match(q, "a.ws_a, a.lc_a", fixed = TRUE)
  expect_match(q, "b.ws_b, b.lc_b", fixed = TRUE)
})

test_that("an id column that is also a key column is projected once", {
  # Before #272, feature_id_col = "blue_line_key" was legal: the walk read
  # b.blue_line_key twice from a table. A subquery projecting it twice would
  # make b.blue_line_key ambiguous.
  rec <- mock_nf_db()
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    segment_id_col = "blue_line_key",
    feature_id_col = "blue_line_key",
    direction = "downstream",
    aoi = "ADMS"
  )
  expect_match(rec$exec[1], "SELECT blue_line_key, downstream_route_measure, wscode_ltree",
               fixed = TRUE)
  expect_match(rec$query, "SELECT f.blue_line_key, f.downstream_route_measure, f.wscode_ltree",
               fixed = TRUE)
})

test_that("the temp table is dropped after the walk, last", {
  rec <- mock_nf_db()
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "id",
    direction = "downstream",
    aoi = "ADMS"
  )
  tmp <- nf_tmp_name(rec)
  expect_identical(rec$exec[length(rec$exec)], sprintf("DROP TABLE IF EXISTS %s", tmp))
  expect_length(grep("^DROP", rec$exec), 1L)
})

test_that("the temp table's DROP is attempted when the walk throws", {
  # This proves the DROP is sent, not that the table is gone: inside a
  # caller's aborted transaction the DROP itself fails (and is swallowed),
  # and the table lives until the caller rolls back.
  rec <- mock_nf_db(query_fn = function(sql) stop("walk failed"))
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = "ADMS"
    ),
    "walk failed"
  )
  tmp <- nf_tmp_name(rec)
  expect_identical(rec$exec[length(rec$exec)], sprintf("DROP TABLE IF EXISTS %s", tmp))
})

test_that("a session that cannot build the temp table gets a named cause", {
  msg <- "cannot execute CREATE TABLE in a read-only transaction"
  rec <- mock_nf_db(exec_fn = function(sql) {
    if (startsWith(sql, "CREATE TEMP TABLE")) stop(msg)
  })
  err <- tryCatch(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      aoi = "ADMS"
    ),
    error = function(e) e
  )
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "session temp table", fixed = TRUE)
  expect_match(conditionMessage(err), "read-only transaction or standby", fixed = TRUE)
  expect_match(conditionMessage(err), "transaction pooler that sent one of these statements",
               fixed = TRUE)
  expect_match(conditionMessage(err), msg, fixed = TRUE)
  expect_identical(conditionMessage(err$parent), msg)
  expect_null(rec$query)
  # the DROP is still attempted, since the CREATE may have partly run
  expect_match(rec$exec[length(rec$exec)], "^DROP TABLE IF EXISTS pg_temp\\.frs_tmp_")
})

test_that("ORDER BY ends in the feature id in both directions", {
  for (dir in c("downstream", "upstream")) {
    for (aoi in list(NULL, "ADMS")) {
      rec <- mock_nf_db()
      frs_network_features(
        conn = "mock",
        segments = "fresh.streams",
        features = "fresh.crossings",
        feature_id_col = "modelled_crossing_id",
        direction = dir,
        aoi = aoi
      )
      tail_keys <- paste0(
        "b\\.downstream_route_measure DESC,\\s+",
        "b\\.modelled_crossing_id\\s+\\) d"
      )
      expect_match(rec$query, tail_keys)
    }
  }
})

## #281: result = "exists" ------------------------------------------------

# The walk with the scoped path's random temp-table name replaced by a fixed
# one, so two calls' SQL can be compared.
nf_sql <- function(..., aoi = NULL, direction = "downstream") {
  rec <- mock_nf_db()
  frs_network_features(
    conn = "mock",
    segments = "fresh.streams",
    features = "fresh.crossings",
    feature_id_col = "modelled_crossing_id",
    direction = direction,
    aoi = aoi,
    ...
  )
  q <- rec$query
  tmp <- nf_tmp_name(rec)
  if (length(tmp)) q <- gsub(tmp, "pg_temp.TMP", q, fixed = TRUE)
  list(query = q, exec = rec$exec, tmp = tmp)
}

test_that("`result` must be one of ids/exists", {
  expect_error(
    frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      feature_id_col = "id",
      direction = "downstream",
      result = "count"
    ),
    "should be one of"
  )
})

test_that("result = \"ids\" sends the same walk as the default", {
  for (dir in c("downstream", "upstream")) {
    for (aoi in list(NULL, "ADMS")) {
      expect_identical(
        nf_sql(aoi = aoi, direction = dir)$query,
        nf_sql(result = "ids", aoi = aoi, direction = dir)$query
      )
    }
  }
})

test_that("result = \"exists\" builds no arrays and sorts no pairs", {
  for (dir in c("downstream", "upstream")) {
    for (aoi in list(NULL, "ADMS")) {
      q <- nf_sql(result = "exists", aoi = aoi, direction = dir)$query
      expect_no_match(q, "array_agg|ORDER BY|GROUP BY")
      # one row per distinct segment id, as the array walk's GROUP BY gives
      expect_match(q, "SELECT DISTINCT\\s+a\\.id_segment\\b")
      # and the caller's id column, not the default
      q2 <- nf_sql(result = "exists", aoi = aoi, direction = dir,
                   segment_id_col = "linear_feature_id")$query
      expect_match(q2, "SELECT DISTINCT\\s+a\\.linear_feature_id\\b")
      expect_match(q, sprintf("whse_basemapping\\.fwa_%s\\(", dir))
      expect_match(q, "true, 1|false, 1")
    }
  }
})

test_that("result = \"exists\" keeps the scoped walk: temp table and prefilter", {
  ids <- nf_sql(aoi = "ADMS")
  ex <- nf_sql(result = "exists", aoi = "ADMS")
  # the same DDL, and the same DROP last
  norm <- function(x) gsub(x$tmp, "pg_temp.TMP", x$exec, fixed = TRUE)
  expect_identical(norm(ex), norm(ids))
  expect_identical(ex$exec[length(ex$exec)], sprintf("DROP TABLE IF EXISTS %s", ex$tmp))
  # the walk reads the temp table and the prefiltered features, never the
  # base tables directly
  expect_match(ex$query, "FROM pg_temp\\.TMP a")
  prefilter <- .frs_walk_prefilter(
    "fresh.crossings", "pg_temp.TMP",
    c("modelled_crossing_id", "blue_line_key", "downstream_route_measure",
      "wscode_ltree", "localcode_ltree"),
    "wscode_ltree", "wscode_ltree"
  )
  expect_true(grepl(prefilter, ex$query, fixed = TRUE))
  expect_no_match(ex$query, "fresh\\.streams")
})

test_that("result = \"exists\" without the scoped walk filters on aoi and creates nothing", {
  for (dir in c("downstream", "upstream")) {
    ex <- nf_sql(result = "exists", aoi = NULL, direction = dir)
    expect_length(ex$exec, 0L)
    expect_match(ex$query, "FROM fresh\\.streams a")
    expect_no_match(ex$query, "watershed_group_code|subpath|frs_tmp_")
  }
  ex <- nf_sql(result = "exists", aoi = "ADMS", direction = "upstream")
  expect_length(ex$exec, 0L)
  expect_match(ex$query, "a\\.watershed_group_code = 'ADMS'")
  expect_no_match(ex$query, "subpath|frs_tmp_")
})

test_that("result = \"exists\" returns the id column and a logical has_features", {
  for (ids in list(c("s1", "s2"), character(0))) {
    # a data.frame, as sf::st_read() returns: `d$x <- TRUE` on a zero-row
    # data.frame errors where a tibble would recycle
    mock_nf_db(query_fn = function(sql) data.frame(segment_id = ids))
    out <- frs_network_features(
      conn = "mock",
      segments = "fresh.streams",
      features = "fresh.crossings",
      segment_id_col = "linear_feature_id",
      feature_id_col = "id",
      direction = "downstream",
      result = "exists"
    )
    expect_named(out, c("linear_feature_id", "has_features"))
    expect_identical(out$linear_feature_id, ids)
    expect_type(out$has_features, "logical")
    expect_identical(out$has_features, rep(TRUE, length(ids)))
  }
})

test_that("result = \"exists\" walks the array walk's own join and filter", {
  # Round 3 of #281's review: a second hand-written predicate could wire
  # include_equivalents or the code columns differently and still contain
  # every fragment the tests above look for.
  walk_from <- function(q) {
    regmatches(q, regexpr("FROM [^\n]+ a\n[\\s\\S]*?(?=\\s+ORDER BY|\\s*$)", q,
                          perl = TRUE))
  }
  for (dir in c("downstream", "upstream")) {
    for (aoi in list(NULL, "ADMS")) {
      for (ie in c(FALSE, TRUE)) {
        args <- list(aoi = aoi, direction = dir, include_equivalents = ie,
                     segments_wscode_col = "seg_ws",
                     segments_localcode_col = "seg_lc",
                     features_wscode_col = "ft_ws",
                     features_localcode_col = "ft_lc")
        ids <- do.call(nf_sql, args)$query
        ex <- do.call(nf_sql, c(args, result = "exists"))$query
        info <- sprintf("%s, aoi = %s, include_equivalents = %s",
                        dir, if (is.null(aoi)) "NULL" else aoi, ie)
        w <- walk_from(ids)
        expect_length(w, 1L)
        expect_identical(walk_from(ex), w, info = info)
        expect_match(w, sprintf("%s, 1\n", if (ie) "true" else "false"),
                     fixed = TRUE)
        expect_match(w, paste0(
          "a.blue_line_key, a.downstream_route_measure,\\s+",
          "a.seg_ws, a.seg_lc,\\s+",
          "b.blue_line_key, b.downstream_route_measure,\\s+",
          "b.ft_ws, b.ft_lc,"
        ))
      }
    }
  }
})
