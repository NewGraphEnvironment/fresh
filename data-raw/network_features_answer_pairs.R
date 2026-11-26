# Re-derive the answer-pair counts in the header of
# tests/testthat/test-frs_network_features-local.R (#302).
#
# The header says the prefilter's strict-ancestor arm alone admits "22 of
# 40,495 answer pairs at include_equivalents = FALSE and 22 of 40,769 at
# TRUE, with every 25th FWA segment as features". An answer pair is one
# (SKGT segment, feature) pair that the test's reference join returns:
# fwa_downstream(segment, feature, include_equivalents, 1). A pair only the
# ancestor arm admits has its feature on no SKGT blue line and on no SKGT
# wscode, the test's own `ancestor_sql` rule.
#
# The fixture is the test's: nf_local_features() is parsed out of the test
# file and evaluated, not copied, so the two cannot drift. Counts are given
# for its first part (every 25th FWA segment, positive ids: the header's
# population) and for the whole fixture (plus the NULL-coded SKGT copies).
#
# Connects as the live tests do (FRESH_PG*, defaulting to the docker/
# container on localhost:5432). Run from the repo root, e.g.
#   FRESH_PGPORT=5433 Rscript data-raw/network_features_answer_pairs.R \
#     > data-raw/logs/docker_rebuild_324/answer_pairs_5433.tsv

env <- function(k, d) {
  v <- Sys.getenv(k)
  if (nzchar(v)) v else d
}
conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = env("FRESH_PGHOST", "localhost"),
  port = as.integer(env("FRESH_PGPORT", "5432")),
  dbname = env("FRESH_PGDATABASE", "fwapg"),
  user = env("FRESH_PGUSER", "postgres"),
  password = env("FRESH_PGPASSWORD", "postgres")
)
on_exit <- function() DBI::dbDisconnect(conn)

test_file <- "tests/testthat/test-frs_network_features-local.R"
exprs <- parse(test_file, keep.source = FALSE)
is_fixture <- vapply(exprs, function(e) {
  is.call(e) && identical(e[[1]], as.name("<-")) &&
    identical(e[[2]], as.name("nf_local_features"))
}, logical(1))
stopifnot(sum(is_fixture) == 1L)
eval(exprs[[which(is_fixture)]])
features <- nf_local_features(conn)

meta <- DBI::dbGetQuery(conn, "
  SELECT current_setting('server_version') AS pg,
         substring(postgis_full_version() FROM 'GEOS=\"([^\"]+)\"') AS geos,
         (SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp) AS segments,
         (SELECT count(DISTINCT watershed_group_code)
            FROM whse_basemapping.fwa_stream_networks_sp) AS groups,
         (SELECT count(*) FROM pg_temp.nf_features WHERE linear_feature_id > 0)
           AS features_every_25th,
         (SELECT count(*) FROM pg_temp.nf_features) AS features_all")
run_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
cat(sprintf("# %s port %s, PostgreSQL %s, GEOS %s\n",
            run_utc, env("FRESH_PGPORT", "5432"), meta$pg, meta$geos))
cat(sprintf("# %s segments in %s groups; features: %s every 25th, %s in the whole fixture\n",
            meta$segments, meta$groups, meta$features_every_25th, meta$features_all))

count_sql <- function(ie, population) {
  sql <- "
    WITH own AS (
      SELECT blue_line_key, wscode_ltree
      FROM whse_basemapping.fwa_stream_networks_sp
      WHERE watershed_group_code = 'SKGT'),
    pairs AS (
      SELECT b.blue_line_key, b.wscode_ltree
      FROM whse_basemapping.fwa_stream_networks_sp a
      INNER JOIN %s b ON whse_basemapping.fwa_downstream(
        a.blue_line_key, a.downstream_route_measure,
        a.wscode_ltree, a.localcode_ltree,
        b.blue_line_key, b.downstream_route_measure,
        b.wscode_ltree, b.localcode_ltree,
        %s, 1)
      WHERE a.watershed_group_code = 'SKGT' AND %s)
    SELECT count(*)::bigint AS pairs,
           count(*) FILTER (
             WHERE blue_line_key NOT IN (SELECT blue_line_key FROM own)
               AND wscode_ltree NOT IN (
                 SELECT wscode_ltree FROM own WHERE wscode_ltree IS NOT NULL)
           )::bigint AS ancestor_only
    FROM pairs"
  sprintf(sql, features, if (ie) "true" else "false",
          if (population == "every_25th") "b.linear_feature_id > 0" else "true")
}

cat("population\tinclude_equivalents\tpairs\tancestor_only\n")
for (population in c("every_25th", "whole_fixture")) {
  for (ie in c(FALSE, TRUE)) {
    r <- DBI::dbGetQuery(conn, count_sql(ie, population))
    cat(sprintf("%s\t%s\t%s\t%s\n", population, ie, r$pairs, r$ancestor_only))
  }
}
on_exit()
