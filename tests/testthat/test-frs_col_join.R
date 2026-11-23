# --- Unit tests (no DB) ---

# The type probe reads the database; unit tests stand it in.
.mock_col_types <- function(conn, from, cols) {
  stats::setNames(rep("double precision", length(cols)), cols)
}

test_that("frs_col_join builds correct SQL for single key", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) { sql_log <<- c(sql_log, sql); 0L }
  )
  local_mocked_bindings(.frs_query_col_types = .mock_col_types)

  frs_col_join("mock", "working.streams",
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")

  expect_length(sql_log, 3)
  expect_match(sql_log[1], "ADD COLUMN IF NOT EXISTS channel_width")
  expect_match(sql_log[2], "ADD COLUMN IF NOT EXISTS channel_width_source")
  expect_match(sql_log[3], "UPDATE working.streams t SET")
  expect_match(sql_log[3], "channel_width = _src.channel_width")
  expect_match(sql_log[3], "channel_width_source = _src.channel_width_source")
  expect_match(sql_log[3], "t.linear_feature_id = _src.linear_feature_id")
})

test_that("frs_col_join handles composite keys", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) { sql_log <<- c(sql_log, sql); 0L }
  )
  local_mocked_bindings(.frs_query_col_types = .mock_col_types)

  frs_col_join("mock", "working.streams",
    from = "fwa_stream_networks_mean_annual_precip",
    cols = "map_upstream",
    by = c("wscode_ltree", "localcode_ltree"))

  update_sql <- sql_log[length(sql_log)]
  expect_match(update_sql, "t.wscode_ltree = _src.wscode_ltree")
  expect_match(update_sql, "t.localcode_ltree = _src.localcode_ltree")
})

test_that("frs_col_join handles named by (different column names)", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) { sql_log <<- c(sql_log, sql); 0L }
  )
  local_mocked_bindings(.frs_query_col_types = .mock_col_types)

  frs_col_join("mock", "working.streams",
    from = "custom_model.widths",
    cols = "width_m",
    by = c(linear_feature_id = "lid"))

  update_sql <- sql_log[length(sql_log)]
  expect_match(update_sql, "t.linear_feature_id = _src.lid")
})

test_that("frs_col_join accepts subquery in from", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) { sql_log <<- c(sql_log, sql); 0L }
  )
  local_mocked_bindings(.frs_query_col_types = .mock_col_types)

  frs_col_join("mock", "working.streams",
    from = "(SELECT l.linear_feature_id, ua.upstream_area_ha
             FROM fwa_streams_watersheds_lut l
             JOIN fwa_watersheds_upstream_area ua
               ON l.watershed_feature_id = ua.watershed_feature_id)",
    cols = "upstream_area_ha",
    by = "linear_feature_id")

  update_sql <- sql_log[length(sql_log)]
  expect_match(update_sql, "fwa_streams_watersheds_lut")
  expect_match(update_sql, "upstream_area_ha = _src.upstream_area_ha")
})

test_that("frs_col_join validates identifiers", {
  expect_error(
    frs_col_join("mock", "DROP TABLE foo",
      from = "lookup", cols = "x", by = "id"),
    "invalid characters"
  )
})

test_that("frs_col_join returns conn invisibly", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )
  local_mocked_bindings(.frs_query_col_types = .mock_col_types)

  result <- frs_col_join("mock_conn", "working.streams",
    from = "lookup", cols = "x", by = "id")
  expect_equal(result, "mock_conn")
})


# --- Integration tests (live DB) ---

test_that("frs_col_join adds channel_width from FWA lookup", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, frs_test_tbl("test_col_join"))
    DBI::dbDisconnect(conn)
  })

  aoi <- readRDS(system.file("extdata", "test_streamline.rds", package = "fresh"))

  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = frs_test_tbl("test_col_join"),
    cols = c("linear_feature_id", "blue_line_key", "geom"),
    aoi = aoi, overwrite = TRUE)

  frs_col_join(conn, frs_test_tbl("test_col_join"),
    from = "fwa_stream_networks_channel_width",
    cols = "channel_width",
    by = "linear_feature_id")

  result <- DBI::dbGetQuery(conn,
    sprintf("SELECT channel_width FROM %s
     WHERE channel_width IS NOT NULL LIMIT 5", frs_test_tbl("test_col_join")))

  expect_true(nrow(result) > 0)
  expect_true(all(result$channel_width > 0))
})


# Columns are typed as the source has them, for a subquery as for a table
# (#239), and an unqualified name is resolved as the UPDATE resolves it
# (#222): the information_schema lookup this replaced typed a subquery's
# columns text, could not see a pg_temp table, and said USER-DEFINED for
# ltree.
.cj_types <- function(conn, tbl, cols) {
  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT a.attname AS col, format_type(a.atttypid, a.atttypmod) AS type
     FROM pg_attribute a WHERE a.attrelid = %s::regclass AND a.attnum > 0
       AND NOT a.attisdropped", .frs_quote_string(tbl)))
  stats::setNames(got$type, got$col)[cols]
}

.cj_fixture <- function(conn) {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.cj_src, pg_temp.cj_dst")
  DBI::dbExecute(conn, "CREATE TEMP TABLE cj_src AS
    SELECT 1::bigint AS linear_feature_id, 2.5::double precision AS mad_m3s,
           7::integer AS n, '100.200'::ltree AS code")
  DBI::dbExecute(conn, "CREATE TEMP TABLE cj_dst AS
    SELECT 1::bigint AS linear_feature_id")
}

test_that("frs_col_join types a subquery's columns as the source has them (#239)", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .cj_fixture(conn)
  frs_col_join(conn, "pg_temp.cj_dst",
    from = "(SELECT linear_feature_id, mad_m3s, n FROM pg_temp.cj_src)",
    cols = c("mad_m3s", "n"))
  expect_equal(unname(.cj_types(conn, "pg_temp.cj_dst", c("mad_m3s", "n"))),
               c("double precision", "integer"))
  # The first numeric predicate on them, which failed on text columns.
  expect_equal(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS k FROM pg_temp.cj_dst
     WHERE mad_m3s BETWEEN 1 AND 3 AND n > 5")$k, 1L)
})

test_that("frs_col_join types an unqualified table and an ltree column (#222)", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .cj_fixture(conn)
  # Unqualified, so it resolves through search_path (pg_temp first).
  frs_col_join(conn, "pg_temp.cj_dst", from = "cj_src",
               cols = c("mad_m3s", "code"))
  expect_equal(unname(.cj_types(conn, "pg_temp.cj_dst", c("mad_m3s", "code"))),
               c("double precision", "ltree"))
  expect_equal(DBI::dbGetQuery(conn,
    "SELECT code::text AS code FROM pg_temp.cj_dst")$code, "100.200")
})

test_that("frs_col_join errors on a column the source lacks, before any ALTER", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .cj_fixture(conn)
  expect_error(frs_col_join(conn, "pg_temp.cj_dst", from = "pg_temp.cj_src",
                            cols = c("mad_m3s", "no_such_col")),
               "no_such_col")
  expect_false("mad_m3s" %in% .frs_cols_of(conn, "pg_temp.cj_dst"))
})

# format_type() with no modifier names char(n) and bit(n) `character` and
# `bit`, which ADD COLUMN reads as char(1) and bit(1): a subquery's char(4)
# column would be created too narrow, the UPDATE would fail, and the column
# would stay behind (code-check round 3).
test_that("frs_col_join widens char(n) and bit(n) rather than narrowing them", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.cj_w")
  DBI::dbExecute(conn, "CREATE TEMP TABLE cj_w AS SELECT 1::bigint AS id")
  frs_col_join(conn, "pg_temp.cj_w",
    from = "(SELECT 1::bigint AS id, 'abcd'::char(4) AS c,
               B'101'::bit(3) AS b, ARRAY['xy'::char(2)] AS ca)",
    cols = c("c", "b", "ca"), by = "id")
  expect_equal(unname(.cj_types(conn, "pg_temp.cj_w", c("c", "b", "ca"))),
               c("character varying", "bit varying", "character varying[]"))
  got <- DBI::dbGetQuery(conn,
    "SELECT c, b::text AS b, ca[1] AS ca FROM pg_temp.cj_w")
  expect_equal(got$c, "abcd")
  expect_equal(got$b, "101")
  expect_equal(got$ca, "xy")
})
