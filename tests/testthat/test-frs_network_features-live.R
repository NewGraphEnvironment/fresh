# Live integration test for frs_network_features against the
# bcfishpass tunnel DB. Skipped when PG_PASS_SHARE is unset (CI,
# unconfigured dev hosts). Validates that frs_network_features
# produces byte-identical (mod array element sort) output to bcfp's
# pre-computed streams_dnstr_* tables.
#
# Reference: bcfishpass tunnel at localhost:63333 (db_newgraph,
# rebuilt Tuesdays from bcfishpass repo). Test uses ADMS as the
# reference WSG since it has a clean PSCIS-barriers slice for diff.

skip_if(Sys.getenv("PG_PASS_SHARE") == "",
        "PG_PASS_SHARE not set — skipping bcfp tunnel parity tests")
skip_on_cran()
skip_on_ci()

bcfp_conn <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host = "localhost", port = 63333, dbname = "bcfishpass",
    user = Sys.getenv("PG_USER_SHARE", "newgraph"),
    password = Sys.getenv("PG_PASS_SHARE")
  )
}

test_that("downstream PSCIS barriers byte-identical to bcfp on ADMS", {
  conn <- bcfp_conn()
  withr::defer(try(DBI::dbDisconnect(conn), silent = TRUE))

  # bcfp's model/01_access/01_model_access_natural.sh:163 builds
  # streams_dnstr_barriers with include_equivalents = 'true' — match
  # that for byte-identical parity.
  ours <- frs_network_features(
    conn,
    segments            = "bcfishpass.streams",
    features            = "bcfishpass.barriers_pscis",
    segment_id_col      = "segmented_stream_id",
    feature_id_col      = "barriers_pscis_id",
    direction           = "downstream",
    aoi                 = "ADMS",
    include_equivalents = TRUE
  )

  # bcfp's streams_dnstr_barriers is a wide table with one row per
  # segment + multiple per-source array columns. Many ADMS rows have
  # non-NULL `barriers_dams_dnstr` but NULL `barriers_pscis_dnstr` —
  # filter to the slice that's apples-to-apples with our PSCIS-only call.
  ref <- DBI::dbGetQuery(conn, "
    SELECT b.segmented_stream_id,
           b.barriers_pscis_dnstr AS feature_ids
    FROM bcfishpass.streams_dnstr_barriers b
    JOIN bcfishpass.streams s
      ON s.segmented_stream_id = b.segmented_stream_id
    WHERE s.watershed_group_code = 'ADMS'
      AND b.barriers_pscis_dnstr IS NOT NULL")

  # Our INNER-JOIN-based primitive only emits segments with at least
  # one downstream feature, matching bcfp's pattern.
  expect_equal(nrow(ours), nrow(ref),
               info = "row count of segments with PSCIS downstream")

  both <- merge(ours, ref,
                by = "segmented_stream_id",
                suffixes = c("_ours", "_ref"))
  expect_equal(nrow(both), nrow(ref),
               info = "all bcfp ref segment_ids present in ours")

  # Per-segment array equality (after sort to ignore element ordering).
  # ours$feature_ids is now an R list-column of character vectors (post #204).
  # ref comes back from DBI::dbGetQuery as `pq__text` literal strings —
  # parse via the same helper so both sides compare apples-to-apples.
  ours_sorted <- lapply(both$feature_ids_ours, function(x) {
    sort(as.character(x))
  })
  ref_sorted <- lapply(both$feature_ids_ref, function(x) {
    sort(.frs_parse_pg_array(x))
  })
  matches <- mapply(function(a, b) identical(a, b),
                    ours_sorted, ref_sorted)
  expect_true(all(matches),
              info = sprintf("%d / %d arrays differ",
                              sum(!matches), length(matches)))
})

test_that("wscode_col / localcode_col override works on bcfp.observations", {
  # bcfishpass.observations uses unsuffixed `wscode` / `localcode`
  # column names rather than the `_ltree` suffix. Without #204's
  # parameterisation, this query errors with "column b.wscode_ltree
  # does not exist".
  conn <- bcfp_conn()
  withr::defer(try(DBI::dbDisconnect(conn), silent = TRUE))

  out <- frs_network_features(
    conn,
    segments       = "bcfishpass.streams",
    features       = "bcfishpass.observations",
    segment_id_col = "segmented_stream_id",
    feature_id_col = "observation_key",
    direction      = "upstream",
    aoi                    = "ADMS",
    features_wscode_col    = "wscode",
    features_localcode_col = "localcode"
  )

  expect_named(out, c("segmented_stream_id", "feature_ids"))
  expect_gt(nrow(out), 0L)
  # feature_ids should be a list-column of character vectors with
  # actual observation_key strings, not array-literal text.
  expect_type(out$feature_ids, "list")
  expect_type(out$feature_ids[[1]], "character")
  expect_gt(length(out$feature_ids[[1]]), 0L)
  # The first vector's first element should look like a 32-char hex
  # observation_key, not a `{...}` literal.
  expect_no_match(out$feature_ids[[1]][1], "^\\{")
})

test_that("upstream PSCIS barriers structurally produce the inverse mapping",
{
  # Sanity check on direction = "upstream" — for each barrier, fetch
  # arrays of OTHER barriers upstream of it. We don't have a bcfp
  # reference for this exact slice (their tables are streams-keyed),
  # so this test just confirms the SQL runs and returns a sensible
  # shape on real data. Byte-identical parity is downstream-only.
  conn <- bcfp_conn()
  withr::defer(try(DBI::dbDisconnect(conn), silent = TRUE))

  out <- frs_network_features(
    conn,
    segments       = "bcfishpass.streams",
    features       = "bcfishpass.barriers_pscis",
    segment_id_col = "segmented_stream_id",
    feature_id_col = "barriers_pscis_id",
    direction      = "upstream",
    aoi            = "ADMS"
  )

  expect_named(out, c("segmented_stream_id", "feature_ids"))
  expect_gt(nrow(out), 0L)
  # At least some segments should have upstream barriers (ADMS isn't
  # entirely barriered at its highest reach).
  any_upstream <- any(!sapply(out$feature_ids, function(x) {
    is.null(x) || length(x) == 0L
  }))
  expect_true(any_upstream,
              info = "at least one segment has upstream barriers in ADMS")
})
