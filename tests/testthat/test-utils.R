# -- SQL quoting ---------------------------------------------------------------

test_that(".frs_quote_string escapes single quotes", {
  expect_equal(fresh:::.frs_quote_string("BULK"), "'BULK'")
  expect_equal(fresh:::.frs_quote_string("O'Brien"), "'O''Brien'")
  expect_equal(fresh:::.frs_quote_string("'; DROP TABLE --"), "'''; DROP TABLE --'")
})

# -- identifier validation ----------------------------------------------------

test_that(".frs_validate_identifier accepts valid names", {
  expect_silent(fresh:::.frs_validate_identifier("blue_line_key", "column"))
  expect_silent(fresh:::.frs_validate_identifier("whse_basemapping.fwa_stream_networks_sp", "table"))
  expect_silent(fresh:::.frs_validate_identifier("*", "column"))
})

test_that(".frs_validate_identifier rejects injection attempts", {
  expect_error(fresh:::.frs_validate_identifier("'; DROP TABLE --", "table"),
    "table contains invalid characters")
  expect_error(fresh:::.frs_validate_identifier("col; DELETE", "column"),
    "column contains invalid characters")
  expect_error(fresh:::.frs_validate_identifier("1bad", "column"),
    "column contains invalid characters")
})

# -- env var check -------------------------------------------------------------

# -- .frs_index_working ---------------------------------------------------------

test_that(".frs_index_working is idempotent — no error on double call", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  tbl <- "working.test_idx_idem"
  on.exit({
    .frs_test_drop(conn, tbl)
    DBI::dbDisconnect(conn)
  })

  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
  .frs_db_execute(conn, sprintf(
    "CREATE TABLE %s (
       id_segment integer,
       blue_line_key integer,
       downstream_route_measure double precision,
       wscode_ltree ltree,
       localcode_ltree ltree,
       label text
     )", tbl))

  # First call creates indexes
  expect_no_error(fresh:::.frs_index_working(conn, tbl))

  # Second call is a no-op — IF NOT EXISTS prevents error

  expect_no_error(fresh:::.frs_index_working(conn, tbl))

  # Verify indexes exist
  idx_count <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) AS n FROM pg_indexes WHERE tablename = 'test_idx_idem'"))
  expect_true(idx_count$n >= 6)
})

test_that(".frs_index_working skips non-DB connections", {
  mock_conn <- structure(list(), class = "mock_connection")
  expect_no_error(fresh:::.frs_index_working(mock_conn, "schema.table"))
})

# -- .frs_find_waterbody_rule --------------------------------------------------

test_that(".frs_find_waterbody_rule returns matching L rule", {
  rules <- list(
    list(edge_types = c("stream", "canal")),
    list(waterbody_type = "R", channel_width = c(0, 9999)),
    list(waterbody_type = "L", lake_ha_min = 100)
  )
  r <- .frs_find_waterbody_rule(rules, "L")
  expect_type(r, "list")
  expect_equal(r$waterbody_type, "L")
  expect_equal(r$lake_ha_min, 100)
})

test_that(".frs_find_waterbody_rule returns matching W rule", {
  rules <- list(
    list(edge_types = "wetland", thresholds = FALSE),
    list(waterbody_type = "W", wetland_ha_min = 5)
  )
  r <- .frs_find_waterbody_rule(rules, "W")
  expect_equal(r$waterbody_type, "W")
  expect_equal(r$wetland_ha_min, 5)
})

test_that(".frs_find_waterbody_rule returns NULL when no matching rule", {
  rules <- list(
    list(edge_types = c("stream", "canal")),
    list(waterbody_type = "R", channel_width = c(0, 9999))
  )
  expect_null(.frs_find_waterbody_rule(rules, "L"))
  expect_null(.frs_find_waterbody_rule(rules, "W"))
})

test_that(".frs_find_waterbody_rule handles NULL / empty rules", {
  expect_null(.frs_find_waterbody_rule(NULL, "L"))
  expect_null(.frs_find_waterbody_rule(list(), "L"))
})

test_that(".frs_find_waterbody_rule returns the first match if multiple", {
  rules <- list(
    list(waterbody_type = "L", lake_ha_min = 50),
    list(waterbody_type = "L", lake_ha_min = 200)
  )
  r <- .frs_find_waterbody_rule(rules, "L")
  expect_equal(r$lake_ha_min, 50)
})

test_that(".frs_persist_columns adds missing columns to a stale target (fresh#114)", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  src <- "working.test_114_persist_src"
  dst <- "working.test_114_persist_dst"
  on.exit({
    for (t in c(src, dst)) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
    }
    DBI::dbDisconnect(conn)
  })
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  for (t in c(src, dst)) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
  }
  # Target built by an "older" run: no mad_m3s, which the source now
  # carries *before* id_segment — a positional INSERT would fail.
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s (linear_feature_id integer, id_segment integer)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 1::integer AS linear_feature_id,
       0.5::double precision AS mad_m3s, 7::integer AS id_segment", src))

  cols <- .frs_persist_columns(conn, dst, src)
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s (%s) SELECT %s FROM %s", dst, cols, cols, src))

  res <- DBI::dbGetQuery(conn, sprintf(
    "SELECT linear_feature_id, id_segment, mad_m3s FROM %s", dst))
  expect_equal(res$id_segment, 7L)
  expect_equal(res$mad_m3s, 0.5)
  # Idempotent on an already-aligned target
  expect_no_error(.frs_persist_columns(conn, dst, src))
})

test_that(".frs_persist_columns errors on a shared column type mismatch (fresh#114)", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  src <- "working.test_114_persist_src2"
  dst <- "working.test_114_persist_dst2"
  on.exit({
    for (t in c(src, dst)) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
    }
    DBI::dbDisconnect(conn)
  })
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  for (t in c(src, dst)) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
  }
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s (mad_m3s text)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 0.5::double precision AS mad_m3s", src))
  expect_error(.frs_persist_columns(conn, dst, src),
               "mad_m3s \\(text vs double precision\\)")
})

# -- Per-WSG habitat model (fresh#220) ----------------------------------------

test_that(".frs_habitat_models resolves per WSG, defaulting to cw", {
  pm <- data.frame(watershed_group_code = c("ADMS", "BULK"),
                   model = c("mad", "cw"), stringsAsFactors = FALSE)
  res <- .frs_habitat_models(c("ADMS", "BULK", "LDEN"), pm)
  expect_equal(res, c(ADMS = "mad", BULK = "cw", LDEN = "cw"))
  # NA WSG (custom AOI rows without a group) -> cw
  expect_equal(unname(.frs_habitat_models(NA_character_, pm)), "cw")
  # An NA key in params_method does not claim NULL-group rows
  pm_na <- data.frame(watershed_group_code = c(NA, "ADMS"),
                      model = c("mad", "cw"))
  expect_equal(unname(.frs_habitat_models(NA_character_, pm_na)), "cw")
  expect_equal(.frs_habitat_models(character(0), pm),
               stats::setNames(character(0), character(0)))
})

test_that(".frs_habitat_models validates params_method", {
  expect_error(.frs_habitat_models("ADMS", data.frame(wsg = "ADMS")),
               "watershed_group_code")
  expect_error(.frs_habitat_models("ADMS",
    data.frame(watershed_group_code = "ADMS", model = "xx")),
    "cw.*mad")
})

test_that("bundled parameters_habitat_method.csv resolves all cw", {
  pm <- utils::read.csv(system.file("extdata",
    "parameters_habitat_method.csv", package = "fresh"))
  expect_true(all(.frs_habitat_models(pm$watershed_group_code, pm) == "cw"))
})

test_that(".frs_preds_by_model single model returns preds untouched", {
  cw <- list(spawn = "A", rear = "B")
  mad <- list(spawn = "C", rear = "D")
  expect_identical(
    .frs_preds_by_model(list(cw = cw, mad = mad), c(X = "cw", Y = "cw")), cw)
  expect_identical(
    .frs_preds_by_model(list(cw = cw, mad = mad), c(X = "mad")), mad)
})

test_that(".frs_preds_by_model mixed models switch on watershed_group_code", {
  cw <- list(spawn = "A", rear = "B")
  mad <- list(spawn = "C", rear = "D")
  res <- .frs_preds_by_model(list(cw = cw, mad = mad),
                             c(ADMS = "mad", BULK = "cw", LDEN = "mad"))
  expect_equal(res$spawn,
    "CASE WHEN s.watershed_group_code IN ('ADMS', 'LDEN') THEN (C) ELSE (A) END")
  expect_equal(res$rear,
    "CASE WHEN s.watershed_group_code IN ('ADMS', 'LDEN') THEN (D) ELSE (B) END")
})

test_that(".frs_sql_num renders Inf as a Postgres infinity literal", {
  # frs_params() fills a blank *_mad_max / *_channel_width_max with Inf
  expect_equal(.frs_sql_num(Inf), "'Infinity'::double precision")
  expect_equal(.frs_sql_num(-Inf), "'-Infinity'::double precision")
  expect_equal(.frs_sql_num(0.0549), "0.0549")
})

test_that(".frs_sql_num handles every input shape it receives", {
  # Enumerates the shapes that reach it from CSV params and rules YAML
  expect_equal(.frs_sql_num(2), "2")
  expect_equal(.frs_sql_num(2L), "2")
  expect_equal(.frs_sql_num(list(0.05)), "0.05")          # yaml list element
  expect_equal(.frs_sql_num(list(Inf)), "'Infinity'::double precision")
  expect_equal(.frs_sql_num(c(1, 2)), c("1", "2"))        # vector unchanged
  expect_equal(.frs_sql_num(NA_real_), "NA")              # pre-existing
  # Mixed int/float YAML sequence end to end
  rule <- yaml::yaml.load("gradient: [0, 0.05]\nchannel_width: [1, 9999.5]")
  expect_true(is.list(rule$gradient))
  expect_equal(.frs_rule_to_sql(rule),
    "(s.gradient BETWEEN 0 AND 0.05 AND s.channel_width BETWEEN 1 AND 9999.5)")
})

test_that(".frs_preds_by_model with no WSGs (empty table) returns cw", {
  cw <- list(spawn = "A")
  expect_identical(
    .frs_preds_by_model(list(cw = cw, mad = NULL),
                        .frs_habitat_models(character(0), data.frame(
                          watershed_group_code = "ADMS", model = "mad"))),
    cw)
})
