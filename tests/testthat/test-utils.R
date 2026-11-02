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

test_that(".frs_rule_ha_min reads the floor key of the rule's type (#237)", {
  expect_equal(.frs_rule_ha_min(list(waterbody_type = "L", lake_ha_min = 10)),
               10)
  expect_equal(.frs_rule_ha_min(list(waterbody_type = "W",
                                     wetland_ha_min = 0.5)), 0.5)
  expect_null(.frs_rule_ha_min(list(waterbody_type = "W", lake_ha_min = 10)))
  expect_null(.frs_rule_ha_min(list(waterbody_type = "L",
                                    wetland_ha_min = 1)))
  expect_null(.frs_rule_ha_min(list(waterbody_type = "R",
                                    lake_ha_min = 10)))
  expect_null(.frs_rule_ha_min(list(lake_ha_min = 10)))
  expect_null(.frs_rule_ha_min(list(waterbody_type = "L")))
  expect_null(.frs_rule_ha_min(list(waterbody_type = "W",
                                    wetland_ha_min = NA_real_)))
  expect_null(.frs_rule_ha_min(NULL))
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
    "INSERT INTO %s (%s) SELECT %s FROM %s",
    dst, cols$cols_sql, cols$cols_sql, src))

  res <- DBI::dbGetQuery(conn, sprintf(
    "SELECT linear_feature_id, id_segment, mad_m3s FROM %s", dst))
  expect_equal(res$id_segment, 7L)
  expect_equal(res$mad_m3s, 0.5)
  # The widened return (fresh#282): which column was added, and the target's
  # columns after alignment, are what .frs_persist_streams() keys its NULL
  # guard on.
  expect_equal(cols$cols_added, "mad_m3s")
  expect_setequal(cols$cols_from,
                  c("linear_feature_id", "mad_m3s", "id_segment"))
  expect_setequal(cols$cols_to,
                  c("linear_feature_id", "mad_m3s", "id_segment"))
  # Idempotent on an already-aligned target, and nothing added the second time
  expect_no_error(cols2 <- .frs_persist_columns(conn, dst, src))
  expect_length(cols2$cols_added, 0)
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


test_that(".frs_wsg_in qualifies its inner column", {
  s <- .frs_wsg_in("working.streams")
  expect_match(s, "AND watershed_group_code IN", fixed = TRUE)
  # Qualified, so a `table` without the column errors instead of resolving the
  # name outward to the habitat row — which would make the subquery a
  # correlated no-op that matches every row and reads as applied (fresh#242).
  expect_match(s, "SELECT s.watershed_group_code FROM working.streams s",
               fixed = TRUE)
  expect_false(grepl("SELECT watershed_group_code FROM", s, fixed = TRUE))
})

# -- fetch SQL helpers (#286) -------------------------------------------------

test_that(".frs_build_where adds an sf aoi as ST_Intersects", {
  poly <- sf::st_sfc(sf::st_polygon(list(
    matrix(c(0, 0, 10, 0, 10, 10, 0, 10, 0, 0), ncol = 2, byrow = TRUE)
  )), crs = 3005)
  w <- .frs_build_where(watershed_group_code = "BULK", aoi = poly)
  expect_match(w, "^ WHERE watershed_group_code = 'BULK' AND ST_Intersects\\(geom, ST_GeomFromText\\(")
})

test_that(".frs_build_where with a NULL aoi is unchanged", {
  expect_identical(.frs_build_where(), "")
  expect_identical(
    .frs_build_where(blue_line_key = 1, aoi = NULL),
    " WHERE blue_line_key = 1"
  )
})

test_that(".frs_geom_select passes cols through without simplify_m", {
  expect_identical(.frs_geom_select(c("a", "geom")), "a, geom")
})

test_that(".frs_geom_select simplifies and normalizes the geometry column", {
  expect_identical(
    .frs_geom_select(c("a", "geom", "b"), simplify_m = 25),
    "a, ST_Normalize(ST_SimplifyPreserveTopology(geom, 25)) AS geom, b"
  )
})

test_that(".frs_geom_select skips ST_Normalize when normalize = FALSE", {
  expect_identical(
    .frs_geom_select(c("a", "geom"), simplify_m = 2.5, normalize = FALSE),
    "a, ST_SimplifyPreserveTopology(geom, 2.5) AS geom"
  )
})

test_that(".frs_geom_select rejects a bad simplify_m", {
  for (bad in list(0, -1, NA_real_, Inf, c(1, 2), "10", TRUE)) {
    expect_error(.frs_geom_select(c("geom"), simplify_m = bad),
                 "simplify_m must be a single positive number")
  }
})

test_that(".frs_geom_select errors when the geometry column is not selected", {
  expect_error(.frs_geom_select(c("a", "b"), simplify_m = 10),
               "needs the geometry column 'geom'")
})

test_that(".frs_order_by builds a clause or nothing", {
  expect_identical(.frs_order_by(NULL), "")
  expect_identical(.frs_order_by("waterbody_poly_id"),
                   " ORDER BY waterbody_poly_id")
})

test_that(".frs_order_by takes several key columns", {
  expect_identical(
    .frs_order_by(c("linear_feature_id", "downstream_route_measure")),
    " ORDER BY linear_feature_id, downstream_route_measure"
  )
})

test_that(".frs_order_by rejects anything but identifiers", {
  for (bad in list("*", c("a", "*"), character(0), NA_character_,
                   c("a", NA), 1, "id; DROP TABLE x")) {
    expect_error(.frs_order_by(bad))
  }
})

test_that(".frs_resolve_aoi sends full coordinates whatever digits is set to", {
  withr::local_options(digits = 7)
  poly <- sf::st_sfc(sf::st_polygon(list(matrix(c(
    1234567.891, 456789.123, 1234667.891, 456789.123,
    1234667.891, 456889.123, 1234567.891, 456789.123
  ), ncol = 2, byrow = TRUE))), crs = 3005)
  expect_match(.frs_resolve_aoi(poly), "1234567.891 456789.123", fixed = TRUE)
})

test_that(".frs_resolve_aoi errors on an sf aoi with no CRS", {
  poly <- sf::st_sfc(sf::st_polygon(list(
    matrix(c(0, 0, 10, 0, 10, 10, 0, 0), ncol = 2, byrow = TRUE)
  )))
  expect_error(.frs_resolve_aoi(poly), "crs")
})

test_that(".frs_sql_exact writes 17 significant digits and refuses non-finite input", {
  # R's own parser is not correctly rounded for 17-digit text (1 ulp off in
  # about a fifth of cases), so the exact round trip is pinned against
  # Postgres in test-frs_fetch_live.R; here, the digits and the values R does
  # read back exactly
  expect_identical(.frs_sql_exact(1234567.8912345678), "1234567.8912345679")
  for (x in c(2415.57257727526, 1e6, 0.1, 208877L)) {
    expect_identical(as.numeric(.frs_sql_exact(x)), as.double(x))
  }
  expect_identical(.frs_sql_exact(1e6), "1000000")
  for (bad in list(NA_real_, Inf, -Inf, NaN, c(1, 2), "1", NULL)) {
    expect_error(.frs_sql_exact(bad, "m"), "m must be a single finite number")
  }
})


# -- Persist partition delete (fresh#282) -------------------------------------
# Pure-string tests: there is no Postgres service in .github/workflows/, so
# these are the only proof of the delete key that runs on CI.

test_that(".frs_persist_delete_sql keys a WSG job on the watershed group", {
  sql <- .frs_persist_delete_sql("fresh.streams", "working.streams_bulk",
    wsg_code = "BULK",
    cols_to = c("id_segment", "watershed_group_code", "linear_feature_id"),
    cols_from = c("id_segment", "watershed_group_code", "linear_feature_id"))
  expect_match(sql, "^DELETE FROM fresh\\.streams WHERE watershed_group_code")
  expect_match(sql, "'BULK'", fixed = TRUE)
  expect_false(grepl("id_segment", sql))
})

test_that(".frs_persist_delete_sql quotes a WSG code rather than pasting it", {
  # The mirai path used to interpolate '%s' raw while the sequential path went
  # through .frs_quote_string(). One helper, one quoting rule.
  sql <- .frs_persist_delete_sql("fresh.streams", "working.streams_x",
    wsg_code = "O'HARA", cols_to = "watershed_group_code",
    cols_from = "watershed_group_code")
  expect_match(sql, "'O''HARA'", fixed = TRUE)
})

test_that(".frs_persist_delete_sql keys a custom AOI on the parent segment", {
  cols <- c("id_segment", "watershed_group_code", "linear_feature_id",
            "downstream_route_measure")
  sql <- .frs_persist_delete_sql("fresh.streams", "working.streams_rich",
    wsg_code = NULL, cols_to = cols, cols_from = cols)
  expect_match(sql, "DELETE FROM fresh\\.streams WHERE linear_feature_id IN")
  expect_match(sql, "SELECT linear_feature_id FROM working\\.streams_rich")
  # Not the key fresh#282 was filed against: id_segment is unique only within
  # a watershed group, and a job's derived ids collide with real same-group
  # linear_feature_ids.
  expect_false(grepl("id_segment", sql))
  # And not the pair key either — it leaves those same-group collisions in.
  expect_false(grepl("watershed_group_code", sql))
})

test_that(".frs_persist_delete_sql falls back to id_segment only off-FWA", {
  cols <- c("id_segment", "watershed_group_code")
  sql <- .frs_persist_delete_sql("other.segments", "working.segments_x",
    wsg_code = NULL, cols_to = cols, cols_from = cols)
  expect_match(sql, "WHERE id_segment IN \\(SELECT id_segment FROM")
})

test_that(".frs_persist_delete_sql errors when one side lacks the key", {
  # A silent fallback here would be a fallback to the key fresh#282 showed to
  # be wrong, so it must name the table and stop.
  expect_error(
    .frs_persist_delete_sql("fresh.streams", "working.streams_x",
      wsg_code = NULL,
      cols_to = c("id_segment", "linear_feature_id"),
      cols_from = "id_segment"),
    "working\\.streams_x"
  )
  expect_error(
    .frs_persist_delete_sql("fresh.streams", "working.streams_x",
      wsg_code = NULL,
      cols_to = "id_segment",
      cols_from = c("id_segment", "linear_feature_id")),
    "fresh\\.streams"
  )
})

test_that(".frs_persist_delete_sql errors with no key at all", {
  expect_error(
    .frs_persist_delete_sql("a.b", "c.d", wsg_code = NULL,
      cols_to = "geom", cols_from = "geom"),
    "no key to delete on"
  )
})

test_that(".frs_persist_delete_sql errors when a WSG target lacks the column", {
  expect_error(
    .frs_persist_delete_sql("a.b", "c.d", wsg_code = "BULK",
      cols_to = c("id_segment", "linear_feature_id"),
      cols_from = c("id_segment", "linear_feature_id",
                    "watershed_group_code")),
    "no watershed_group_code column"
  )
})

test_that(".frs_persist_delete_sql refuses a target equal to its source", {
  # DELETE ... WHERE col IN (SELECT col FROM <same table>) matches every row
  # against itself, so the table would empty and the INSERT would then read
  # from the table it just emptied. Nothing validated this before.
  cols <- c("id_segment", "linear_feature_id")
  expect_error(
    .frs_persist_delete_sql("working.streams_bulk", "working.streams_bulk",
      wsg_code = NULL, cols_to = cols, cols_from = cols),
    "same table"
  )
  # Case-insensitively, since Postgres folds an unquoted identifier.
  expect_error(
    .frs_persist_delete_sql("Working.Streams_Bulk", "working.streams_bulk",
      wsg_code = "BULK", cols_to = "watershed_group_code",
      cols_from = "watershed_group_code"),
    "same table"
  )
})

test_that(".frs_same_relation compares folded names", {
  expect_true(.frs_same_relation("fresh.streams", "FRESH.Streams"))
  expect_false(.frs_same_relation("fresh.streams", "fresh.streams_habitat"))
})


test_that(".frs_persist_streams works inside a caller's transaction", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  src <- "working.test_282_txn_src"
  dst <- "working.test_282_txn_dst"
  on.exit({
    try(DBI::dbRollback(conn), silent = TRUE)
    for (t in c(src, dst)) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
    }
    DBI::dbDisconnect(conn)
  })
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  for (t in c(src, dst)) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
  }
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s (id_segment integer, linear_feature_id bigint)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 11::integer AS id_segment,
       42::bigint AS linear_feature_id", src))

  # dbBegin() refuses a nested transaction, and a caller holding one open has
  # already made the pair atomic with respect to their own commit, so the
  # helper must proceed rather than raise.
  DBI::dbBegin(conn)
  expect_no_error(.frs_persist_streams(conn, dst, src, NULL))
  DBI::dbCommit(conn)
  expect_equal(
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", dst))$n,
    1L)
})

test_that(".frs_persist_streams raises on a dbBegin failure that is not nesting", {
  skip_if_not(.frs_db_available(), "DB not available")
  skip_if_not_installed("mockery")
  conn <- frs_db_conn()
  src <- "working.test_282_bgn_src"
  dst <- "working.test_282_bgn_dst"
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
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s (id_segment integer, linear_feature_id bigint)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 11::integer AS id_segment,
       42::bigint AS linear_feature_id", src))

  # Reading every dbBegin() failure as "already in a transaction" would fall
  # back to the autocommitted pair the transaction exists to replace, which is
  # the shape of the one-shot guard above: inferring a condition from a
  # failure instead of measuring it. Only the nesting message may proceed.
  mockery::stub(.frs_persist_streams, "DBI::dbBegin",
                function(...) stop("server closed the connection unexpectedly"))
  expect_error(.frs_persist_streams(conn, dst, src, NULL),
               "server closed the connection")
  expect_equal(
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", dst))$n,
    0L)
})

test_that(".frs_persist_streams refuses a target that RESOLVES to its source", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  src <- "working.test_282_rc_src"
  on.exit({
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", src))
    DBI::dbExecute(conn, "SET search_path TO DEFAULT")
    DBI::dbDisconnect(conn)
  })
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", src))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 11::integer AS id_segment,
       42::bigint AS linear_feature_id", src))

  # .frs_same_relation() compares strings, which is exact only for two
  # schema-qualified names. An unqualified name resolves through the
  # connection's search_path, so these two name ONE table and compare
  # unequal -- and a delete whose subselect reads the table it deletes from
  # matches every row, emptying it, with the insert then reading what it just
  # emptied. The regclass test in .frs_persist_streams() is what catches it;
  # without that test this call empties the table and returns quietly.
  DBI::dbExecute(conn, "SET search_path TO working, public")
  expect_error(.frs_persist_streams(conn, "test_282_rc_src", src, NULL),
               "resolve to the same table")
  expect_equal(
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", src))$n,
    1L)

  # And the string compare still catches the qualified spelling, with no
  # database reached, which is why both exist.
  expect_error(.frs_persist_delete_sql(src, src, NULL, "a", "a"),
               "same table")
})

test_that(".frs_persist_delete_key needs its key on BOTH sides", {
  # The delete reads the key on the target and the insert writes it from the
  # source, so one side carrying it is not enough. Each arm separately: a
  # mutation that drops either `cols_from` half must redden something.
  expect_error(
    .frs_persist_delete_sql("fresh.t", "working.f", "BULK",
                            cols_to = c("watershed_group_code", "id_segment"),
                            cols_from = "id_segment"),
    "working.f has no watershed_group_code")
  expect_error(
    .frs_persist_delete_sql("fresh.t", "working.f", "BULK",
                            cols_to = "id_segment",
                            cols_from = c("watershed_group_code",
                                          "id_segment")),
    "fresh.t has no watershed_group_code")
  # Both sides lacking it names both tables.
  expect_error(
    .frs_persist_delete_sql("fresh.t", "working.f", "BULK",
                            cols_to = "id_segment",
                            cols_from = "id_segment"),
    "fresh.t and working.f has no watershed_group_code")

  # Same for the id_segment fallback, which is the last key available when
  # neither table is the Freshwater Atlas.
  expect_error(
    .frs_persist_delete_sql("fresh.t", "working.f", NULL,
                            cols_to = "id_segment", cols_from = "other"),
    "id_segment is missing")
  expect_error(
    .frs_persist_delete_sql("fresh.t", "working.f", NULL,
                            cols_to = "other", cols_from = "id_segment"),
    "id_segment is missing")
})

test_that(".frs_partition_wsg keeps the group only for a whole-group job", {
  # The persist delete removes the whole group, so the group is the partition
  # only when the job segmented all of it. frs_habitat() accepts wsg AND aoi
  # together, and that job holds a subset: ANDed into the group filter for a
  # character aoi, replacing it for an sf/list aoi.
  expect_equal(.frs_partition_wsg("BULK", NULL), "BULK")
  expect_null(.frs_partition_wsg("BULK", "gradient < 0.05"))
  expect_null(.frs_partition_wsg("BULK", list(table = "x")))
  expect_null(.frs_partition_wsg("BULK", data.frame(a = 1)))
})

test_that(".frs_persist_streams refuses a target whose key it just added", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  src <- "working.test_282_persist_src"
  dst <- "working.test_282_persist_dst"
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
  # A target from an older run that never carried linear_feature_id, holding a
  # row. .frs_persist_columns() adds the column, so that row holds NULL for it
  # and a delete keyed on it would match nothing — the job's own earlier rows
  # would duplicate rather than be replaced. Same shape as fresh#225.
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s (id_segment integer)", dst))
  DBI::dbExecute(conn, sprintf("INSERT INTO %s VALUES (7)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 7::integer AS id_segment,
       42::bigint AS linear_feature_id", src))

  expect_error(.frs_persist_streams(conn, dst, src, NULL),
               "1 row\\(s\\) hold NULL")
  # The guard fires before the delete, so the pre-existing row is still there.
  expect_equal(
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", dst))$n,
    1L)

  # The warm path, which is where the first version of this guard failed. Its
  # predicate was "this call added the key column", and .frs_persist_columns()
  # has already run the ALTER by the time the guard raises -- so a second call
  # found nothing newly added, went inert, and wrote the duplicate the guard
  # exists to prevent. The condition is a property of the target, not of this
  # call, so it must still hold on every later run.
  expect_error(.frs_persist_streams(conn, dst, src, NULL),
               "1 row\\(s\\) hold NULL")
  expect_error(.frs_persist_streams(conn, dst, src, NULL),
               "holds rows with no linear_feature_id")
  expect_equal(
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", dst))$n,
    1L)
})

test_that(".frs_persist_streams replaces its partition atomically", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  src <- "working.test_282_atomic_src"
  dst <- "working.test_282_atomic_dst"
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
  # A DELETE and an INSERT autocommitted separately lose the partition when
  # anything stops the pair between them. Force the insert half to fail with a
  # constraint the source violates, and the row the delete would have removed
  # must still be there.
  #
  # The target carries a unique index, as every persisted streams table does
  # (fresh.streams has streams_pkey on (id_segment, watershed_group_code)).
  # Without one this fixture cannot reach the failure mode that the first fix
  # here introduced: a data-modifying CTE puts the delete and the insert under
  # one command id, so the insert's uniqueness check still sees the rows the
  # delete is removing and the second run of any ground aborts. An unkeyed
  # target is idempotent under both forms and so tells them apart not at all.
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s (id_segment integer, watershed_group_code varchar(4),
       linear_feature_id bigint, tag text NOT NULL)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE UNIQUE INDEX test_282_atomic_pkey
       ON %s (id_segment, watershed_group_code)", dst))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s VALUES (11, 'BULK', 42, 'mine')", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 11::integer AS id_segment,
       'BULK'::varchar(4) AS watershed_group_code,
       42::bigint AS linear_feature_id, NULL::text AS tag", src))

  expect_error(.frs_persist_streams(conn, dst, src, NULL), "not-null|null value")
  res <- DBI::dbGetQuery(conn, sprintf(
    "SELECT linear_feature_id, tag FROM %s", dst))
  expect_equal(nrow(res), 1L)
  expect_equal(res$tag, "mine")
})

test_that(".frs_persist_streams re-runs over a target with a unique index", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  src <- "working.test_282_uniq_src"
  dst <- "working.test_282_uniq_dst"
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
  # The shape of a real persist target, which the other fixtures here lack:
  # `CREATE TABLE ... AS SELECT ... LIMIT 0` copies no constraints, so a
  # target this helper created itself can never carry the unique index the
  # tables it is actually run against do. Re-running the same ground must
  # replace, under either key, which is what the first atomicity fix broke.
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s (id_segment integer, watershed_group_code varchar(4),
       linear_feature_id bigint)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE UNIQUE INDEX test_282_uniq_pkey
       ON %s (id_segment, watershed_group_code)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 11::integer AS id_segment,
       'BULK'::varchar(4) AS watershed_group_code,
       42::bigint AS linear_feature_id", src))

  n_of <- function() {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int AS n FROM %s", dst))$n
  }
  for (i in 1:3) {
    expect_no_error(.frs_persist_streams(conn, dst, src, NULL))
    expect_equal(n_of(), 1L)
  }
  for (i in 1:3) {
    expect_no_error(.frs_persist_streams(conn, dst, src, "BULK"))
    expect_equal(n_of(), 1L)
  }
})

test_that(".frs_persist_streams allows an empty target gaining the key", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  src <- "working.test_282_empty_src"
  dst <- "working.test_282_empty_dst"
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
  # Same shape, no pre-existing rows: adding the column is harmless, so the
  # guard must not fire. The cold path of the idempotent branch.
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s (id_segment integer)", dst))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT 7::integer AS id_segment,
       42::bigint AS linear_feature_id", src))

  expect_no_error(.frs_persist_streams(conn, dst, src, NULL))
  res <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, linear_feature_id FROM %s", dst))
  expect_equal(nrow(res), 1L)
  expect_equal(res$id_segment, 7L)
})


test_that("the delete key chooser and the statement it builds never disagree", {
  # The guard in .frs_persist_streams() and the DELETE itself must be about the
  # same column. Asserted as a property over every column set that reaches a
  # key, rather than by reading two code paths and finding them consistent --
  # "one fact derived twice" is the shape this is here to prevent.
  cases <- list(
    list(wsg = "BULK", to = c("id_segment", "watershed_group_code",
                              "linear_feature_id"),
         from = c("id_segment", "watershed_group_code",
                  "linear_feature_id")),
    list(wsg = "BULK", to = c("id_segment", "watershed_group_code"),
         from = c("id_segment", "watershed_group_code")),
    list(wsg = NULL, to = c("id_segment", "watershed_group_code",
                            "linear_feature_id"),
         from = c("id_segment", "watershed_group_code",
                  "linear_feature_id")),
    list(wsg = NULL, to = c("id_segment", "linear_feature_id"),
         from = c("id_segment", "linear_feature_id")),
    list(wsg = NULL, to = c("id_segment", "watershed_group_code"),
         from = c("id_segment", "watershed_group_code")),
    list(wsg = NULL, to = "id_segment", from = "id_segment")
  )
  for (cs in cases) {
    key <- .frs_persist_delete_key("fresh.streams", "working.streams_x",
      cs$wsg, cs$to, cs$from)
    sql <- .frs_persist_delete_sql("fresh.streams", "working.streams_x",
      cs$wsg, cs$to, cs$from)
    expect_match(sql, paste0("WHERE ", key), fixed = TRUE,
                 info = paste(key, "|", paste(cs$to, collapse = ",")))
    # And no other candidate key is named by the statement.
    for (other in setdiff(c("id_segment", "watershed_group_code",
                            "linear_feature_id"), key)) {
      expect_false(grepl(paste0("WHERE ", other), sql, fixed = TRUE),
                   info = paste("statement names", other, "not", key))
    }
  }
})

test_that(".frs_persist_delete_key returns the three keys it should", {
  expect_equal(
    .frs_persist_delete_key("a.b", "c.d", "BULK",
      c("id_segment", "watershed_group_code"),
      c("id_segment", "watershed_group_code")),
    "watershed_group_code")
  expect_equal(
    .frs_persist_delete_key("a.b", "c.d", NULL,
      c("id_segment", "linear_feature_id"),
      c("id_segment", "linear_feature_id")),
    "linear_feature_id")
  expect_equal(
    .frs_persist_delete_key("a.b", "c.d", NULL, "id_segment", "id_segment"),
    "id_segment")
})
