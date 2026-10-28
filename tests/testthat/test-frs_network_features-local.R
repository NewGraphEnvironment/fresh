# Live tests for frs_network_features() against a local fwapg (`FRESH_PG*`,
# defaulting to the `docker/` container; see helper-db.R). Never on CI.
#
# #272: an aoi-scoped downstream walk builds a session temp table of the
# AOI's segments and prefilters the features to the two things
# fwa_downstream() can return. These tests compare that path with the plain,
# unprefiltered join on real FWA data, and check the temp table is gone after.

# The AOI is SKGT. Its streams reach the Fraser (wscode `100`), which has no
# segment in SKGT, so some of its downstream features sit on a stream whose
# code is neither one of SKGT's own nor on one of its blue lines: only the
# prefilter's ancestor arm admits those (22 of 40,495 pairs with the fixture
# below). Removing that arm changed no answer pair in VICT, LKEL or UPET,
# so a test there could not see it (measured 2026-10-28).
#
# Features: every 25th FWA segment province-wide, plus a copy of every 7th
# SKGT segment with its codes NULL and its id negated. fwa_downstream()
# returns a feature on the segment's own blue line without reading the
# feature's codes, so only the prefilter's blue-line arm admits those: in
# FWA itself no blue line carries two wscodes, and without the copies that
# arm would be untested. The whole network as `features` would be the
# densest table possible; for VICT the prefilter admits 210 k segments and
# the walk takes about 43 s (the plain join about 93 s), measured 2026-10-28.
nf_local_features <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE nf_features AS
    SELECT linear_feature_id, blue_line_key, downstream_route_measure,
           wscode_ltree, localcode_ltree
    FROM whse_basemapping.fwa_stream_networks_sp
    WHERE linear_feature_id % 25 = 0
    UNION ALL
    SELECT -linear_feature_id, blue_line_key, downstream_route_measure,
           NULL::ltree, NULL::ltree
    FROM whse_basemapping.fwa_stream_networks_sp
    WHERE watershed_group_code = 'SKGT' AND linear_feature_id % 7 = 0")
  DBI::dbExecute(conn, "CREATE INDEX ON nf_features (blue_line_key)")
  DBI::dbExecute(conn, "CREATE INDEX ON nf_features USING gist (wscode_ltree)")
  DBI::dbExecute(conn, "CREATE INDEX ON nf_features USING gist (localcode_ltree)")
  DBI::dbExecute(conn, "ANALYZE nf_features")
  "pg_temp.nf_features"
}

# This session's own frs_tmp_ tables. pg_my_temp_schema() keeps another
# session's pg_temp_N leftovers out; it is non-zero here because
# nf_local_features() already made this session's temp schema.
nf_tmp_tables <- function(conn) {
  DBI::dbGetQuery(conn, "
    SELECT c.relname FROM pg_class c
    WHERE c.relnamespace = pg_my_temp_schema()
      AND c.relkind = 'r'
      AND c.relname LIKE 'frs\\_tmp\\_%'")$relname
}

test_that("aoi-scoped downstream walk equals the unprefiltered join (SKGT)", {
  conn <- local_fwapg()
  features <- nf_local_features(conn)
  temp_schema <- DBI::dbGetQuery(conn, "SELECT pg_my_temp_schema()::int AS o")$o
  expect_false(identical(temp_schema, 0L))

  # The walk runs through frs_db_query(): look for the temp table there, so
  # the "gone afterwards" check below is not vacuous.
  seen <- list()
  real_query <- frs_db_query
  local_mocked_bindings(frs_db_query = function(conn, query) {
    seen[[length(seen) + 1L]] <<- nf_tmp_tables(conn)
    real_query(conn, query)
  })

  for (ie in c(FALSE, TRUE)) {
    ours <- frs_network_features(
      conn,
      segments            = "whse_basemapping.fwa_stream_networks_sp",
      features            = features,
      segment_id_col      = "linear_feature_id",
      feature_id_col      = "linear_feature_id",
      direction           = "downstream",
      aoi                 = "SKGT",
      include_equivalents = ie
    )
    ref <- DBI::dbGetQuery(conn, sprintf("
      SELECT a.linear_feature_id::text AS id,
             array_agg(b.linear_feature_id)::text AS feature_ids
      FROM whse_basemapping.fwa_stream_networks_sp a
      INNER JOIN %s b ON whse_basemapping.fwa_downstream(
        a.blue_line_key, a.downstream_route_measure,
        a.wscode_ltree, a.localcode_ltree,
        b.blue_line_key, b.downstream_route_measure,
        b.wscode_ltree, b.localcode_ltree,
        %s, 1)
      WHERE a.watershed_group_code = 'SKGT'
      GROUP BY a.linear_feature_id", features, if (ie) "true" else "false"))

    info <- sprintf("include_equivalents = %s", ie)
    expect_gt(nrow(ref), 0L)
    expect_equal(nrow(ours), nrow(ref), info = info)
    ours_ids <- as.character(ours$linear_feature_id)
    expect_setequal(ours_ids, ref$id)
    ours_sets <- lapply(ours$feature_ids, function(x) sort(as.character(x)))
    ref_sets <- lapply(ref$feature_ids, function(x) sort(.frs_parse_pg_array(x)))
    names(ours_sets) <- ours_ids
    names(ref_sets) <- ref$id
    expect_identical(ours_sets[ref$id], ref_sets, info = info)
    # the fixture reaches both arms: NULL-coded features (blue-line arm) and
    # features on the Fraser below SKGT (ancestor arm)
    all_ids <- unlist(ref_sets, use.names = FALSE)
    expect_true(any(startsWith(all_ids, "-")), info = info)
    ancestor_sql <- sprintf("
      WITH own AS (
        SELECT blue_line_key, wscode_ltree
        FROM whse_basemapping.fwa_stream_networks_sp
        WHERE watershed_group_code = 'SKGT')
      SELECT count(*)::int AS n FROM %s f
      WHERE f.linear_feature_id = ANY ('{%s}'::bigint[])
        AND f.blue_line_key NOT IN (SELECT blue_line_key FROM own)
        AND f.wscode_ltree NOT IN (
          SELECT wscode_ltree FROM own WHERE wscode_ltree IS NOT NULL)",
      features, paste(unique(all_ids), collapse = ",")
    )
    expect_gt(DBI::dbGetQuery(conn, ancestor_sql)$n, 0L)

    expect_length(seen[[length(seen)]], 1L)
    expect_length(nf_tmp_tables(conn), 0L)
  }
})
