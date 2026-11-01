# =====================================================================
# frs_feature_index — per-segment arrays of features up/downstream
# =====================================================================
#
# The output is keyed on (id_segment, watershed_group_code): id_segment is
# unique only within a watershed group (fresh#218), so a segments table
# holding several groups, as a persisted fresh.streams does, repeats values
# across them (fresh#277 part 3). The fixture is a pg_temp network with two
# groups sharing id_segment 2 on different blue lines, built out of whole
# cloth: fwa_downstream()/fwa_upstream() are pure, so no FWA rows are
# needed, only fwapg's functions.

# Two groups, one shared id_segment. Features sit on each group's own blue
# line, so the same-blk arm of the join decides every match and the cross-blk
# ltree arm is never true (the codes are unrelated).
.fi_fixture <- function(conn) {
  for (t in c("fi_streams", "fi_features", "fi_dnstr", "fi_upstr")) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", t))
  }
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE fi_streams AS SELECT * FROM (VALUES
      (2, 100, 50::double precision, '100'::ltree, '100'::ltree, 'TEST'::text),
      (2, 200, 50, '200', '200', 'OTHR'),
      (3, 200, 0, '200', '200', 'OTHR')
    ) v(id_segment, blue_line_key, downstream_route_measure,
        wscode_ltree, localcode_ltree, watershed_group_code)")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE fi_features AS SELECT * FROM (VALUES
      (10, 100, 10::double precision, '100'::ltree, '100'::ltree),
      (20, 200, 10, '200', '200'),
      (21, 200, 30, '200', '200')
    ) v(feature_id, blue_line_key, downstream_route_measure,
        wscode_ltree, localcode_ltree)")
  invisible(conn)
}

# One row per output row: group, segment, features as "a,b" (NA for none)
.fi_read <- function(conn, to, col) {
  DBI::dbGetQuery(conn, sprintf("
    SELECT watershed_group_code AS wsg, id_segment,
           array_to_string(%s, ',') AS f
    FROM %s ORDER BY 1, 2", col, to))
}

test_that("frs_feature_index keys its output on id_segment and watershed_group_code", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .fi_fixture(conn)

  frs_feature_index(conn, "pg_temp.fi_streams", "pg_temp.fi_features",
                    direction = "downstream", to = "pg_temp.fi_dnstr",
                    verbose = FALSE)
  cols <- names(DBI::dbGetQuery(conn, "SELECT * FROM pg_temp.fi_dnstr LIMIT 0"))
  expect_setequal(cols, c("id_segment", "watershed_group_code", "features_dnstr"))

  # TEST's segment 2 sees only its own blue line's feature; OTHR's segment 2,
  # the same id_segment, sees its two; OTHR's segment 3 at the mouth sees none.
  # Grouped on id_segment alone the two 2s collapse into one row of {10,20,21}.
  got <- .fi_read(conn, "pg_temp.fi_dnstr", "features_dnstr")
  expect_equal(got$wsg, c("OTHR", "OTHR", "TEST"))
  expect_equal(got$id_segment, c(2L, 3L, 2L))
  expect_equal(got$f, c("20,21", NA, "10"))

  # The same split upstream: only OTHR's mouth segment has features above it
  frs_feature_index(conn, "pg_temp.fi_streams", "pg_temp.fi_features",
                    direction = "upstream", to = "pg_temp.fi_upstr",
                    verbose = FALSE)
  got <- .fi_read(conn, "pg_temp.fi_upstr", "features_upstr")
  expect_equal(got$wsg, c("OTHR", "OTHR", "TEST"))
  expect_equal(got$id_segment, c(2L, 3L, 2L))
  expect_equal(got$f, c(NA, "20,21", NA))
})

test_that("frs_feature_index indexes the output on both key columns", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .fi_fixture(conn)

  frs_feature_index(conn, "pg_temp.fi_streams", "pg_temp.fi_features",
                    to = "pg_temp.fi_dnstr", verbose = FALSE)
  defs <- DBI::dbGetQuery(conn,
    "SELECT indexdef FROM pg_indexes WHERE tablename = 'fi_dnstr'")$indexdef
  expect_gt(length(defs), 0)
  expect_match(defs, "\\(id_segment, watershed_group_code\\)", all = FALSE)
})

test_that("frs_feature_index names a segments table lacking watershed_group_code", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .fi_fixture(conn)
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.fi_streams_nowsg")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE fi_streams_nowsg AS
    SELECT id_segment, blue_line_key, downstream_route_measure,
           wscode_ltree, localcode_ltree
    FROM pg_temp.fi_streams")
  # An existing output table must survive the refusal: the check comes
  # before the DROP that `overwrite = TRUE` would otherwise run first
  DBI::dbExecute(conn, "CREATE TEMP TABLE fi_dnstr AS SELECT 1 AS kept")

  expect_error(
    frs_feature_index(conn, "pg_temp.fi_streams_nowsg", "pg_temp.fi_features",
                      to = "pg_temp.fi_dnstr", verbose = FALSE),
    "segments pg_temp.fi_streams_nowsg must carry watershed_group_code")
  expect_equal(DBI::dbGetQuery(conn, "SELECT kept FROM pg_temp.fi_dnstr")$kept, 1L)
})
