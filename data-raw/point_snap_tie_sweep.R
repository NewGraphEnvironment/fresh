# Sweep for fresh#266: what the two pending fwapg migrations change on
# fresh's own code paths, measured before and after, with the migrations
# applied inside a transaction that is rolled back.
#
# This script does NOT migrate a database. frs_migration_trial() applies the
# files inside one transaction and defers the rollback to the sweep function's
# return, so nothing is committed. It must therefore run against the local
# docker fwapg (docker/), never the shared instance the inherited PG* vars
# name: a COMMIT slipping through would migrate a shared database for
# everyone, and dblink is installed there, so a rollback is not a full undo.
# Do not run scripts/habitat/habitat_province.R or habitat_benchmark_island.R
# during a sweep — both hardcode localhost:5432.
#
# Three states, so each change is attributed rather than inferred:
#   base      - the database as it stands (no migration)
#   tiebreak  - 202610240132__indexpoint_tiebreak alone
#   both      - both migrations, in filename order
#
# fresh's snap is its own SQL against the network table, which neither
# migration touches, so the positions are generated once on the base side and
# the same ones are fed to every state. What the sweep measures is the fwapg
# functions fresh calls at those positions: fwa_locatealong()
# (R/frs_point_locate.R), fwa_watershedatmeasure() (R/frs_watershed_at_measure.R,
# R/utils.R) and fwa_downstreamtrace() (R/frs_cluster.R).
#
# Usage (from the fresh repo root):
#   Rscript data-raw/point_snap_tie_sweep.R <fwapg-commit> <migration.sql>...
#   Rscript data-raw/point_snap_tie_sweep.R b088b43 \
#     /tmp/m/202610131654__watershedatmeasure_drop_exbc.sql \
#     /tmp/m/202610240132__indexpoint_tiebreak.sql
# The migration files are given in filename order; the last one must be the
# indexpoint tiebreak, since the "tiebreak alone" state applies only that one.
#
# Writes data-raw/logs/indexpoint_266/sweep.txt (a non-reproducible header
# then a reproducible body), sweep_summary.csv (the three-state count table),
# sweep_changed.csv (every position whose answer moved, with the state that
# moved it), sweep_tops.csv (the head case, one row per sampled blue line) and
# sweep_errors.csv (every call that raised). A second run must be byte-identical
# in the body.
#
# Measures reach SQL at 17 significant digits (.frs_sql_exact()) and keys
# through %d, as on fresh's own code paths since #274; the two CSVs of
# positions carry each measure as that same text. Runs before #289 sent
# measures through format(), at 7 significant digits.

pkgload::load_all(".", quiet = TRUE)

# -- arguments ----------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop("usage: Rscript data-raw/point_snap_tie_sweep.R <fwapg-commit> <migration.sql>...",
       call. = FALSE)
}
fwapg_commit <- args[[1]]
if (!grepl("^[0-9a-f]{7,40}$", fwapg_commit)) {
  stop("the first argument is the fwapg commit the migrations came from, ",
       "as 7 to 40 hex characters: got ", fwapg_commit, call. = FALSE)
}
sources <- args[-1]
absent <- sources[!file.exists(sources)]
if (length(absent)) {
  stop("no such migration file: ", paste(absent, collapse = ", "), call. = FALSE)
}
if (!grepl("indexpoint_tiebreak", basename(sources[[length(sources)]]))) {
  stop("the last migration must be the indexpoint tiebreak, so the ",
       "'tiebreak alone' state can apply only it: got ",
       basename(sources[[length(sources)]]), call. = FALSE)
}

# Copied and md5'd before any connection, so a file rewritten mid-run cannot
# be credited with the counts, and the trial reads the copy either way.
dir_mig <- file.path(tempdir(), "fresh266_migrations")
dir.create(dir_mig, recursive = TRUE, showWarnings = FALSE)
migrations <- file.path(dir_mig, basename(sources))
stopifnot(all(file.copy(sources, migrations, overwrite = TRUE)))
md5 <- tools::md5sum(migrations)
tiebreak <- migrations[[length(migrations)]]

# Sample sizes, with their reproducible rule: ORDER BY md5(<id>::text) LIMIT n.
# The defaults are the sizes the report is written from; the env vars exist so
# the script can be smoke-tested in a minute, and the values used are recorded
# in the report either way. FRESH_SWEEP_PSCIS caps the PSCIS side, which is
# otherwise every assessment.
n_size <- function(var, default) {
  v <- Sys.getenv(var)
  if (!nzchar(v)) {
    return(default)
  }
  n <- suppressWarnings(as.integer(v))
  if (is.na(n) || n < 1L) stop(var, " must be a positive integer: ", v, call. = FALSE)
  n
}
n_pscis <- n_size("FRESH_SWEEP_PSCIS", NA_integer_)  # NA = every assessment
n_obs <- n_size("FRESH_SWEEP_OBS", 5000L)            # of 378,971 observation points
n_crossings <- n_size("FRESH_SWEEP_CROSSINGS", 20000L)  # of 533,291 crossing measures
n_expensive <- n_size("FRESH_SWEEP_EXPENSIVE", 200L) # for the watershed and trace calls
# The plan said "every tied position plus 200 sampled" for the watershed and
# trace calls. At full size that is 4,777 distinct tied positions, and
# fwa_watershedatmeasure costs 0.64 s a call — about 3.3 h over three states,
# because a pre-existing fwapg error on roughly a third of positions forces the
# row-by-row path. So the tied contribution is sampled too, by the same rule,
# and the report says so. The tie CENSUS stays exhaustive: it is geometry,
# measured once on the base side, and costs nothing.
n_tied <- n_size("FRESH_SWEEP_TIED", 800L)
# Blue lines whose own top measure is sent to fwa_locatealong(): the head case
# the tiebreak migration closes. Before #289 this was an unscripted query.
n_tops <- n_size("FRESH_SWEEP_TOPS", 400L)

# -- the database -------------------------------------------------------------

# FRESH_PG*, defaulting to the docker/ container. Never the inherited PG*.
fwapg_conn <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("FRESH_PGHOST", "localhost"),
    port = as.integer(Sys.getenv("FRESH_PGPORT", "5432")),
    dbname = Sys.getenv("FRESH_PGDATABASE", "fwapg"),
    user = Sys.getenv("FRESH_PGUSER", "postgres"),
    password = Sys.getenv("FRESH_PGPASSWORD", "postgres")
  )
}

conn <- fwapg_conn()
DBI::dbExecute(conn, "SET statement_timeout = '1800s'")

indexpoint_args <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT pg_get_function_arguments(p.oid) AS a FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'whse_basemapping' AND p.proname = 'fwa_indexpoint'")$a
}
has_rework <- function(con) any(grepl("include_disconnected", indexpoint_args(con)))

base_args <- indexpoint_args(conn)
if (has_rework(conn)) {
  stop("this database already has the fwa_indexpoint rework, so there is no ",
       "'before' to measure: point FRESH_PG* at an un-migrated fwapg", call. = FALSE)
}
base_exbc <- DBI::dbGetQuery(conn, "
  SELECT p.prosrc ~* 'exbc' AS e FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'whse_basemapping' AND p.proname = 'fwa_watershedatmeasure'")$e
base_version <- DBI::dbGetQuery(conn,
  "SELECT to_regclass('fwapg.db_version')::text AS r")$r
message(sprintf("base: fwa_indexpoint(%s)", paste(base_args, collapse = " | ")))
message(sprintf("base: exbc in fwa_watershedatmeasure = %s, fwapg.db_version = %s",
                paste(base_exbc, collapse = ","),
                if (is.na(base_version)) "absent" else base_version))

# -- scratch tables -----------------------------------------------------------

# Every scratch table named up front, so the drop at the start covers what a
# run that died midway left behind — not only the ones created before it died.
tbls <- paste0("working.tie266_", c("pscis", "obs", "positions", "measures",
                                    "snap_pscis", "snap_obs", "measures_all",
                                    "expensive", "tops"))
tbl <- function(n) tbls[[match(paste0("working.tie266_", n), tbls)]]
# on.exit() does not fire at a script's top level under Rscript
# (data-raw/point_snap_parity_check.R:46-49), so they are dropped at the start
# as well as the end, and a run that died midway leaves nothing behind
drop_all <- function() for (t in tbls) .frs_test_drop(conn, t)
drop_all()

# -- drift guard --------------------------------------------------------------

# The population figures research/fwa_point_snap.md records (measured
# 2026-10-07, fresh#247). They are independent of fresh's tie rule, so they
# catch database drift that would otherwise be credited to the migration.
# There is no stored fresh output to reproduce: those parity numbers were a
# fresh-vs-link comparison and link is not installed.
candidate <- paste("localcode_ltree IS NOT NULL AND NOT wscode_ltree <@ '999'",
                   "AND edge_type <> 1425")
one <- function(sql) as.numeric(DBI::dbGetQuery(conn, sql)[[1]])
population <- data.frame(
  figure = c("segments", "placeholder_999", "placeholder_999_with_localcode",
             "candidates_fractional_start", "candidates_under_one_metre",
             "pscis_assessments", "fish_observation_points"),
  recorded = c(4907441, 208189, 37416, 2989828, 246, 19905, 378971),
  measured = c(
    one("SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp"),
    one("SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp
         WHERE wscode_ltree <@ '999'"),
    one("SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp
         WHERE wscode_ltree <@ '999' AND localcode_ltree IS NOT NULL"),
    one(sprintf("SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp
                 WHERE %s AND downstream_route_measure <> floor(downstream_route_measure)",
                candidate)),
    one(sprintf("SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp
                 WHERE %s AND ceil(downstream_route_measure) > upstream_route_measure",
                candidate)),
    one("SELECT count(*) FROM whse_fish.pscis_assessment_svw"),
    one("SELECT count(*) FROM whse_fish.fiss_fish_obsrvtn_pnt_sp")
  )
)
population$drift <- population$measured - population$recorded
print(population, row.names = FALSE)
# every figure is a property of the database, not of the sample sizes, so the
# guard applies to a capped smoke run exactly as it does to a full one
if (any(population$drift != 0)) {
  stop("the database has drifted from the figures research/fwa_point_snap.md ",
       "records, so a before/after count cannot be credited to the migration: ",
       "re-measure the research note first", call. = FALSE)
}

# -- the positions, generated once on the base side ---------------------------

# fresh's snap is its own SQL against the network table; neither migration
# touches it, so the positions do not depend on the state. Generating them
# once is what makes the three states comparable.
message("snapping PSCIS and a sample of the fish observations ...")
t_snap <- Sys.time()
invisible(DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s AS SELECT stream_crossing_id, geom
   FROM whse_fish.pscis_assessment_svw %s", tbl("pscis"),
  if (is.na(n_pscis)) "" else sprintf("ORDER BY md5(stream_crossing_id::text) LIMIT %d",
                                      n_pscis))))
invisible(DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s AS SELECT fish_observation_point_id, geom
   FROM whse_fish.fiss_fish_obsrvtn_pnt_sp
   ORDER BY md5(fish_observation_point_id::text) LIMIT %d", tbl("obs"), n_obs)))
frs_point_snap(conn, tbl("pscis"), col_id = "stream_crossing_id", tolerance = 150,
               num_features = 5, to = "working.tie266_snap_pscis")
frs_point_snap(conn, tbl("obs"), col_id = "fish_observation_point_id", tolerance = 150,
               num_features = 5, to = "working.tie266_snap_obs")
invisible(DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s AS
   SELECT 'pscis'::text AS src, stream_crossing_id::text AS id, candidate_rank,
          linear_feature_id, blue_line_key, downstream_route_measure AS m,
          distance_to_stream
   FROM working.tie266_snap_pscis
   UNION ALL
   SELECT 'obs', fish_observation_point_id::text, candidate_rank,
          linear_feature_id, blue_line_key, downstream_route_measure,
          distance_to_stream
   FROM working.tie266_snap_obs", tbl("positions"))))
invisible(DBI::dbExecute(conn, sprintf("CREATE INDEX ON %s (blue_line_key, m)", tbl("positions"))))
secs_snap <- as.numeric(difftime(Sys.time(), t_snap, units = "secs"))
n_positions <- one(sprintf("SELECT count(*) FROM %s", tbl("positions")))
message(sprintf("%s snapped positions in %.0f s", format(n_positions, big.mark = ","),
                secs_snap))

# -- the tie census, measured once (geometry, not a function) -----------------

# A tie is two candidates of ONE point at one distance. Counted on the base
# side only: no migration can change the network's geometry.
ties <- DBI::dbGetQuery(conn, sprintf("
  WITH t AS (
    SELECT src, id, distance_to_stream, count(*) AS n,
           count(DISTINCT blue_line_key) AS n_blk,
           max(m) - min(m) AS m_span
    FROM %s GROUP BY src, id, distance_to_stream HAVING count(*) > 1
  )
  SELECT src,
         count(*) AS tied_groups,
         count(*) FILTER (WHERE n_blk = 1) AS within_one_stream,
         count(*) FILTER (WHERE n_blk > 1) AS across_streams,
         count(DISTINCT id) AS tied_points
  FROM t GROUP BY src ORDER BY src", tbl("positions")))
print(ties, row.names = FALSE)

# The two head cases the issue names, counted from the network itself
heads <- DBI::dbGetQuery(conn, sprintf("
  SELECT count(*) FILTER (WHERE upstream_route_measure = floor(upstream_route_measure))
           AS whole_metre_top,
       count(*) FILTER (WHERE ceil(downstream_route_measure) > upstream_route_measure)
           AS under_one_metre
  FROM whse_basemapping.fwa_stream_networks_sp WHERE %s", candidate))
print(heads, row.names = FALSE)

# -- the measures from the bundled CSVs ---------------------------------------

# crossings.csv carries bcfishpass's own fractional indexing; fresh never
# emits a fractional measure, so that part measures the migration at the
# fwapg level rather than on a fresh code path. Labelled as such in the report.
csv_measures <- function(file, src) {
  d <- utils::read.csv(system.file("extdata", file, package = "fresh"))
  d <- d[!is.na(d$blue_line_key) & !is.na(d$downstream_route_measure), ]
  data.frame(src = src, id = paste0(src, "_", seq_len(nrow(d))),
             blue_line_key = as.numeric(d$blue_line_key),
             m = as.numeric(d$downstream_route_measure))
}
all_measures <- rbind(csv_measures("crossings.csv", "crossings"),
                      csv_measures("falls.csv", "falls"),
                      csv_measures("wsg_outlet.csv", "wsg_outlet"))
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "tie266_measures_all"),
                  all_measures, overwrite = TRUE)
# Read back and compared bit for bit: the sweep sends what it reads from this
# table, so a write that rounded the measures would put #289 back unseen.
back <- DBI::dbGetQuery(conn,
  "SELECT id, blue_line_key, m FROM working.tie266_measures_all")
back <- back[match(all_measures$id, back$id), ]
if (anyNA(back$id) || !identical(as.double(back$m), all_measures$m) ||
      !identical(as.double(back$blue_line_key), all_measures$blue_line_key)) {
  stop("working.tie266_measures_all does not read back the measures written to ",
       "it bit for bit, so the sweep would not send the CSVs' own measures",
       call. = FALSE)
}
# the sample is taken in SQL, by the stated rule, so it is reproducible and
# does not cost 533,291 round trips
invisible(DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s AS
   SELECT src, id, blue_line_key, m FROM working.tie266_measures_all
   WHERE src <> 'crossings'
   UNION ALL
   SELECT src, id, blue_line_key, m FROM (
     SELECT * FROM working.tie266_measures_all WHERE src = 'crossings'
     ORDER BY md5(id) LIMIT %d
   ) c", tbl("measures"), n_crossings)))
csv_counts <- DBI::dbGetQuery(conn, sprintf(
  "SELECT src, count(*) AS n FROM %s GROUP BY src ORDER BY src", tbl("measures")))
print(csv_counts, row.names = FALSE)

# -- the head case ------------------------------------------------------------

# A sample of blue lines, by the same md5 rule, each sent at its own top. The
# top is max(upstream_route_measure) over EVERY segment of the line, because
# fwa_locatealong() scans every segment with no guards
# (tests/testthat/test-frs_fwapg_gate.R, skip_unless_head_case()). m_guarded is
# the top over fresh's candidate segments only, as blk_top() there takes it;
# where the two differ the line's top is a segment fresh never snaps to, and
# the report counts those lines apart.
invisible(DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s AS
   WITH b AS (
     SELECT blue_line_key FROM (
       SELECT DISTINCT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp
     ) d
     ORDER BY md5(blue_line_key::text) LIMIT %d
   )
   SELECT b.blue_line_key,
          max(s.upstream_route_measure) AS m,
          max(s.upstream_route_measure) FILTER (WHERE %s) AS m_guarded
   FROM b JOIN whse_basemapping.fwa_stream_networks_sp s USING (blue_line_key)
   GROUP BY b.blue_line_key", tbl("tops"), n_tops,
  "s.localcode_ltree IS NOT NULL AND NOT s.wscode_ltree <@ '999' AND s.edge_type <> 1425")))
n_tops_sampled <- one(sprintf("SELECT count(*) FROM %s", tbl("tops")))
n_tops_guarded <- one(sprintf("SELECT count(*) FROM %s WHERE m_guarded = m", tbl("tops")))
message(sprintf("%d sampled blue lines; on %d the top is a candidate segment's",
                n_tops_sampled, n_tops_guarded))

# the positions the expensive calls run on: every tied one, plus a sample
invisible(DBI::dbExecute(conn, sprintf(
  "CREATE TABLE working.tie266_expensive AS
   WITH tied AS (
     SELECT blue_line_key, m FROM (
       SELECT DISTINCT p.blue_line_key, p.m
       FROM %s p
       JOIN (SELECT src, id, distance_to_stream FROM %s
             GROUP BY src, id, distance_to_stream HAVING count(*) > 1) t
         ON t.src = p.src AND t.id = p.id AND t.distance_to_stream = p.distance_to_stream
     ) d
     ORDER BY md5(blue_line_key::text || \':\' || m::text) LIMIT %d
   ),
   sampled AS (
     SELECT blue_line_key, m FROM (SELECT DISTINCT blue_line_key, m FROM %s) d
     ORDER BY md5(blue_line_key::text || \':\' || m::text) LIMIT %d
   )
   SELECT * FROM tied UNION SELECT * FROM sampled",
  tbl("positions"), tbl("positions"), n_tied, tbl("positions"), n_expensive)))
n_tied_all <- one(sprintf(
  "SELECT count(*) FROM (SELECT DISTINCT p.blue_line_key, p.m FROM %s p
     JOIN (SELECT src, id, distance_to_stream FROM %s
           GROUP BY src, id, distance_to_stream HAVING count(*) > 1) t
       ON t.src = p.src AND t.id = p.id AND t.distance_to_stream = p.distance_to_stream) d",
  tbl("positions"), tbl("positions")))
n_expensive_actual <- one("SELECT count(*) FROM working.tie266_expensive")
message(sprintf("%s positions for the watershed and trace calls",
                format(n_expensive_actual, big.mark = ",")))

DBI::dbDisconnect(conn)

# -- one state ----------------------------------------------------------------

# Batched one set-returning query per chunk. LEFT JOIN LATERAL ... ON TRUE is
# mandatory: a plain CROSS JOIN LATERAL makes a miss vanish instead of
# counting it, and misses are the number this sweep exists to produce.
# Every chunk carries an explicit ordinal and the answer is joined back on it:
# a VALUES list is a relation, and Postgres never promises to return a relation
# in the order it was written. A SAVEPOINT per chunk, and on a chunk error the
# chunk is re-run row by row under per-row savepoints, so one bad position does
# not lose the rest of them.
chunked <- function(con, d, call_sql, chunk = 2000L, label = "") {
  # The measure goes through .frs_sql_exact() (%.17g), as every fresh code path
  # sends one since #274, and the key through %d. format() would write the
  # measures at 7 significant digits with one decimal count for the whole
  # vector, so the sweep would measure rounded positions (#289).
  vals <- sprintf("(%d,%d,%s)", seq_len(nrow(d)),
                  as.integer(d$blue_line_key),
                  vapply(d$m, .frs_sql_exact, character(1), label = "m"))
  out <- vector("list", max(1L, ceiling(length(vals) / chunk)))
  # kept as rows, not as tab-joined text: strsplit() drops a trailing empty
  # field, so an empty conditionMessage() would make the 4th field missing and
  # the report blow up after the sweep rather than before it
  errs <- list()
  ask <- function(v) DBI::dbGetQuery(con, sprintf(call_sql, paste(v, collapse = ",")))
  for (k in seq_along(out)) {
    at <- seq.int((k - 1L) * chunk + 1L, min(k * chunk, length(vals)))
    DBI::dbExecute(con, "SAVEPOINT chunk")
    got <- tryCatch({
      r <- ask(vals[at])
      DBI::dbExecute(con, "RELEASE SAVEPOINT chunk")
      r
    }, error = function(e) {
      DBI::dbExecute(con, "ROLLBACK TO SAVEPOINT chunk")
      e
    })
    if (inherits(got, "error")) {
      # one row at a time, so an error is attributed to its own position
      rows <- vector("list", length(at))
      for (j in at) {
        DBI::dbExecute(con, "SAVEPOINT one")
        rows[[match(j, at)]] <- tryCatch({
          r <- ask(vals[[j]])
          DBI::dbExecute(con, "RELEASE SAVEPOINT one")
          r
        }, error = function(e) {
          DBI::dbExecute(con, "ROLLBACK TO SAVEPOINT one")
          errs[[length(errs) + 1L]] <<- data.frame(
            call = label, blue_line_key = d$blue_line_key[[j]], m = d$m[[j]],
            message = conditionMessage(e), stringsAsFactors = FALSE)
          NULL
        })
      }
      got <- do.call(rbind, rows[!vapply(rows, is.null, TRUE)])
    }
    out[[k]] <- got
    if (length(errs) &&
          any(grepl("current transaction is aborted",
                    vapply(errs, function(e) e$message, "")))) {
      stop("a chunk left the transaction aborted, so every later answer would be ",
           "an error rather than a measurement: stopping", call. = FALSE)
    }
  }
  rows <- do.call(rbind, out[!vapply(out, is.null, TRUE)])
  # joined back on the ordinal, never on the order the rows arrived in
  if (is.null(rows)) rows <- data.frame(ord = integer())
  list(rows = rows[order(rows$ord), , drop = FALSE],
       errors = if (length(errs)) do.call(rbind, errs) else NULL)
}

# `answer` is the column `call_sql` returns per ordinal; missing ordinals (a
# position whose own call errored) stay NA, which is a third outcome and is
# counted as such rather than folded into "miss".
answers <- function(d, got, answer, as = c("logical", "numeric")) {
  as <- match.arg(as)
  # The driver returns a bigint count as integer64. Assigning that into a
  # logical NA vector coerces the target to double and copies the raw bit
  # pattern, so a count of 12 becomes 5.9e-323: the comparison still detects a
  # change but the report cannot say what it changed to. The template carries
  # the type instead.
  out <- rep(if (as == "logical") NA else NA_real_, nrow(d))
  if (nrow(got$rows)) {
    v <- got$rows[[answer]]
    out[got$rows$ord] <- if (as == "logical") as.logical(v) else as.numeric(v)
  }
  out
}

# Sends each row's %.17g measure back keyed on `key` and counts the rows whose
# stored measure differs from the parsed text. Every row must join, and none
# may differ.
sent_exact <- function(con, d, table, key) {
  if (!nrow(d)) {
    return(invisible())
  }
  k <- d[[key]]
  k <- if (is.character(k)) as.character(DBI::dbQuoteString(con, k)) else
    sprintf("%d", as.integer(k))
  vals <- sprintf("(%s,%s)", k, vapply(d$m, .frs_sql_exact, character(1), label = "m"))
  n <- DBI::dbGetQuery(con, sprintf(
    "SELECT count(*) AS joined,
            count(*) FILTER (WHERE t.m IS DISTINCT FROM v.m::double precision) AS differ
     FROM (VALUES %s) v(k, m) JOIN %s t ON t.%s = v.k",
    paste(vals, collapse = ","), table, key))
  if (as.numeric(n$joined) != nrow(d) || as.numeric(n$differ) != 0) {
    stop(sprintf("%s: %s of %d rows joined and %s differ from the text sent, so the ",
                 table, format(as.numeric(n$joined)), nrow(d), format(as.numeric(n$differ))),
         "sweep would not send the measures it stores", call. = FALSE)
  }
  invisible()
}

sweep_state <- function(label, files) {
  con <- fwapg_conn()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "SET statement_timeout = '1800s'")
  t0 <- Sys.time()
  if (length(files)) {
    # the rollback is deferred to this function's return
    frs_migration_trial(con, files)
    if (!has_rework(con)) {
      stop("state '", label, "' applied its migrations but fwa_indexpoint still has ",
           "the old signature: the trial did not take", call. = FALSE)
    }
  } else {
    # the base state opens its own transaction so the savepoints below have a
    # block to sit in, and so all three states are measured the same way
    DBI::dbBegin(con)
    withr::defer(DBI::dbRollback(con), envir = environment())
  }
  pos <- DBI::dbGetQuery(con, sprintf(
    "SELECT src, id, candidate_rank, blue_line_key, m FROM %s
     ORDER BY src, id, candidate_rank", tbl("positions")))
  csv <- DBI::dbGetQuery(con, sprintf(
    "SELECT src, id, blue_line_key, m FROM %s ORDER BY src, id", tbl("measures")))
  exp_pos <- DBI::dbGetQuery(con,
    "SELECT blue_line_key, m FROM working.tie266_expensive ORDER BY blue_line_key, m")
  tops <- DBI::dbGetQuery(con, sprintf(
    "SELECT blue_line_key, m, m_guarded FROM %s ORDER BY blue_line_key", tbl("tops")))
  # What reaches fwapg is the %.17g text of the value read here, so each state
  # sends that text back and has PostgreSQL compare it with what it stores.
  # This covers the read, the format and the parse in one check (#289). The
  # snapped positions are whole metres, which every step writes exactly.
  sent_exact(con, csv, tbl("measures"), "id")
  sent_exact(con, tops, tbl("tops"), "blue_line_key")
  if (any(pos$m != floor(pos$m))) {
    stop("a snapped position is not a whole metre: fresh's snap has changed",
         call. = FALSE)
  }

  locate <- paste(
    "SELECT v.ord, (w.geom IS NOT NULL) AS hit",
    "FROM (VALUES %s) v(ord, blk, m)",
    "LEFT JOIN LATERAL whse_basemapping.fwa_locatealong(v.blk, v.m::double precision) w",
    "  ON TRUE")
  message(sprintf("state %-9s locatealong over %s snapped positions ...", label,
                  format(nrow(pos), big.mark = ",")))
  loc <- chunked(con, pos, locate, label = paste0(label, "/locatealong"))
  pos$locatealong <- answers(pos, loc, "hit")

  message(sprintf("state %-9s locatealong over %s CSV measures ...", label,
                  format(nrow(csv), big.mark = ",")))
  csv_loc <- chunked(con, csv, locate, label = paste0(label, "/locatealong_csv"))
  csv$locatealong <- answers(csv, csv_loc, "hit")

  message(sprintf("state %-9s locatealong at %s blue lines' own tops ...", label,
                  format(nrow(tops), big.mark = ",")))
  top_loc <- chunked(con, tops, locate, label = paste0(label, "/locatealong_top"))
  tops$locatealong <- answers(tops, top_loc, "hit")

  message(sprintf("state %-9s watershedatmeasure and downstreamtrace over %s ...",
                  label, format(nrow(exp_pos), big.mark = ",")))
  wsd <- chunked(con, exp_pos, paste(
    "SELECT v.ord, (w.geom IS NOT NULL) AS hit",
    "FROM (VALUES %s) v(ord, blk, m)",
    "LEFT JOIN LATERAL whse_basemapping.fwa_watershedatmeasure(v.blk, v.m::double precision) w",
    "  ON TRUE"), chunk = 50L, label = paste0(label, "/watershedatmeasure"))
  exp_pos$watershed <- answers(exp_pos, wsd, "hit")
  trc <- chunked(con, exp_pos, paste(
    "SELECT v.ord, count(w.linear_feature_id) AS n",
    "FROM (VALUES %s) v(ord, blk, m)",
    "LEFT JOIN LATERAL whse_basemapping.fwa_downstreamtrace(v.blk, v.m::double precision) w",
    "  ON TRUE GROUP BY v.ord"), chunk = 50L, label = paste0(label, "/downstreamtrace"))
  exp_pos$trace <- answers(exp_pos, trc, "n", as = "numeric")

  errors <- Filter(Negate(is.null),
                   list(loc$errors, csv_loc$errors, top_loc$errors, wsd$errors,
                        trc$errors))
  list(label = label, positions = pos, csv = csv, tops = tops, expensive = exp_pos,
       errors = if (length(errors)) do.call(rbind, errors) else
         data.frame(call = character(), blue_line_key = numeric(), m = numeric(),
                    message = character(), stringsAsFactors = FALSE),
       secs = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}

states <- list(
  base = sweep_state("base", character()),
  tiebreak = sweep_state("tiebreak", tiebreak),
  both = sweep_state("both", migrations)
)

# the rollback fired on each sweep_state() return; a fourth connection reads
# the committed state and must find the old signature back
check <- fwapg_conn()
after_args <- indexpoint_args(check)
after_exbc <- DBI::dbGetQuery(check, "
  SELECT p.prosrc ~* 'exbc' AS e FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'whse_basemapping' AND p.proname = 'fwa_watershedatmeasure'")$e
DBI::dbDisconnect(check)
if (!identical(after_args, base_args) || !identical(after_exbc, base_exbc)) {
  stop("after the trials the database is not as it was: the rollback did not ",
       "take, CHECK THE DATABASE", call. = FALSE)
}

# -- the counts ---------------------------------------------------------------

summary <- do.call(rbind, lapply(states, function(s) {
  data.frame(
    state = s$label,
    positions = nrow(s$positions),
    locatealong_miss = sum(s$positions$locatealong == FALSE, na.rm = TRUE),
    locatealong_error = sum(is.na(s$positions$locatealong)),
    csv_measures = nrow(s$csv),
    csv_locatealong_miss = sum(s$csv$locatealong == FALSE, na.rm = TRUE),
    csv_locatealong_error = sum(is.na(s$csv$locatealong)),
    expensive_positions = nrow(s$expensive),
    watershed_miss = sum(s$expensive$watershed == FALSE, na.rm = TRUE),
    watershed_error = sum(is.na(s$expensive$watershed)),
    trace_empty = sum(s$expensive$trace == 0L, na.rm = TRUE),
    trace_error = sum(is.na(s$expensive$trace)),
    errors = nrow(s$errors),
    secs = round(s$secs, 1)
  )
}))
print(summary, row.names = FALSE)

# The head case, apart from the summary so that table and the moved list keep
# the shape the earlier runs had. Counted over every sampled line, and over
# those whose top is a candidate segment's (the population blk_top() names).
tops_count <- function(t, label, set) {
  data.frame(state = label, lines = set, tops = nrow(t),
             hit = sum(t$locatealong == TRUE, na.rm = TRUE),
             miss = sum(t$locatealong == FALSE, na.rm = TRUE),
             error = sum(is.na(t$locatealong)))
}
tops_summary <- do.call(rbind, lapply(states, function(s) {
  g <- !is.na(s$tops$m_guarded) & s$tops$m_guarded == s$tops$m
  rbind(tops_count(s$tops, s$label, "all"),
        tops_count(s$tops[g, , drop = FALSE], s$label, "top_is_candidate"))
}))
print(tops_summary, row.names = FALSE)
# one row per line, its answer in each state; the states read the same table in
# the same order, which the stopifnot() pins
stopifnot(all(vapply(states, function(s) {
  identical(s$tops$blue_line_key, states$base$tops$blue_line_key)
}, TRUE)))
tops_lines <- states$base$tops[, c("blue_line_key", "m", "m_guarded")]
for (s in states) tops_lines[[s$label]] <- s$tops$locatealong

# Every position whose answer moved, attributed to the state that moved it.
# NA (the call errored) is a distinct outcome from FALSE (it returned nothing),
# so the comparison is on the pair, not on the value.
moved_between <- function(from, to, frame, col, call_label) {
  a <- from[[frame]][[col]]
  b <- to[[frame]][[col]]
  stopifnot(length(a) == length(b))
  i <- which(xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & a != b))
  if (!length(i)) {
    return(NULL)
  }
  d <- from[[frame]][i, , drop = FALSE]
  # one fixed schema across the frames, so the rows bind: a frame that has no
  # src / id / candidate_rank of its own carries NA there rather than a short row
  data.frame(
    state = to$label, call = call_label,
    src = if (is.null(d$src)) NA_character_ else as.character(d$src),
    id = if (is.null(d$id)) NA_character_ else as.character(d$id),
    candidate_rank = if (is.null(d$candidate_rank)) NA_integer_ else d$candidate_rank,
    blue_line_key = d$blue_line_key, m = d$m,
    was = as.character(a[i]), now = as.character(b[i]),
    stringsAsFactors = FALSE
  )
}
pairs <- list(c("base", "tiebreak"), c("tiebreak", "both"))
frames <- list(
  list(frame = "positions", col = "locatealong", call_label = "fwa_locatealong"),
  list(frame = "csv", col = "locatealong", call_label = "fwa_locatealong(csv)"),
  list(frame = "expensive", col = "watershed", call_label = "fwa_watershedatmeasure"),
  list(frame = "expensive", col = "trace", call_label = "fwa_downstreamtrace")
)
moved <- do.call(rbind, unlist(lapply(pairs, function(p) {
  lapply(frames, function(f) {
    moved_between(states[[p[[1]]]], states[[p[[2]]]], f$frame, f$col, f$call_label)
  })
}), recursive = FALSE))
if (is.null(moved)) {
  moved <- data.frame(state = character(), call = character(), src = character(),
                      id = character(), candidate_rank = integer(),
                      blue_line_key = numeric(), m = numeric(), was = character(),
                      now = character(), stringsAsFactors = FALSE)
}
# method = "radix": order() and sort() otherwise collate by LC_COLLATE, so the
# same data would print in a different order — and fingerprint differently — on
# a machine with another locale, which is the opposite of byte-identical
moved <- moved[order(moved$state, moved$call, moved$blue_line_key, moved$m,
                     moved$src, moved$id, method = "radix"), , drop = FALSE]

# -- the report ---------------------------------------------------------------

# print() and write.csv() write a double at 7 and 15 significant digits, so
# each measure is reported as the %.17g text the sweep sent: the report names
# exactly the position that moved
exact_m <- function(d, cols = "m") {
  for (col in cols) {
    v <- d[[col]]
    d[[col]] <- vapply(v, function(x) if (is.na(x)) NA_character_ else
      .frs_sql_exact(x, col), character(1))
  }
  d
}
# write.csv() quotes every character column, so the measures, made character
# above, are left unquoted as they were when they were numbers
write_exact <- function(d, file, cols = "m") {
  quoted <- which(vapply(d, function(x) is.character(x) || is.factor(x), TRUE))
  utils::write.csv(exact_m(d, cols), file, row.names = FALSE,
                   quote = if (length(quoted)) unname(quoted) else FALSE)
}

dir_out <- file.path("data-raw", "logs", "indexpoint_266")
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

# the body's own fingerprint, so this run and any later one are comparable
md5_of <- function(x) {
  f <- tempfile()
  on.exit(unlink(f), add = TRUE)
  writeLines(x, f)
  unname(tools::md5sum(f))
}
base_md5 <- md5_of(sort(with(states$base$positions, paste(
  src, id, candidate_rank, blue_line_key, m, locatealong, sep = "|")),
  method = "radix"))

errors_by_message <- function() {
  if (!sum(vapply(states, function(s) nrow(s$errors), 0L))) {
    return("  none")
  }
  unlist(lapply(states, function(s) {
    if (!nrow(s$errors)) {
      return(character())
    }
    # the first line only: these messages carry the whole offending statement
    m <- sub("\n.*$", "", s$errors$message)
    t <- table(m)
    t <- t[order(-as.integer(t), names(t), method = "radix")]
    sprintf("  %s: %d x %s", s$label, as.integer(t), names(t))
  }))
}

head_sha <- tryCatch(system("git rev-parse --short HEAD", intern = TRUE),
                     error = function(e) character())
if (length(head_sha) != 1L || !nzchar(head_sha)) head_sha <- "git rev-parse failed"

header <- c(
  "# fresh#266 sweep - header (not reproducible)",
  sprintf("run: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  # sprintf() with a zero-length argument returns character(0), and c() then
  # drops the line entirely: a failing git would delete the provenance with no
  # error and no gap
  sprintf("fresh: %s (%s)", as.character(utils::packageVersion("fresh")), head_sha),
  sprintf("fwapg commit: %s", fwapg_commit),
  "migrations, applied inside a transaction and rolled back:",
  sprintf("  %s  md5 %s", basename(migrations), md5),
  sprintf("host: %s:%s/%s", Sys.getenv("FRESH_PGHOST", "localhost"),
          Sys.getenv("FRESH_PGPORT", "5432"), Sys.getenv("FRESH_PGDATABASE", "fwapg")),
  sprintf("base: fwa_indexpoint(%s)", paste(base_args, collapse = " | ")),
  sprintf("base: exbc in fwa_watershedatmeasure = %s, fwapg.db_version = %s",
          paste(base_exbc, collapse = ","),
          if (is.na(base_version)) "absent" else base_version),
  sprintf("after the trials: unchanged (signature and exbc re-checked on a new connection)"),
  sprintf("snap: %.0f s; states: %s", secs_snap,
          paste(sprintf("%s %.0f s", names(states),
                        vapply(states, function(s) s$secs, 0)), collapse = ", ")),
  sprintf("base-side output md5 (sorted src|id|rank|blk|m|locatealong): %s", base_md5),
  ""
)
body <- c(
  "# fresh#266 sweep - body (a second run must be byte-identical from here)",
  sprintf("samples: %s PSCIS, %d fish observation points, %d of crossings.csv,",
          if (is.na(n_pscis)) "all" else format(n_pscis), n_obs, n_crossings),
  "         all of falls.csv and wsg_outlet.csv,",
  sprintf("         %d sampled positions plus %d of the %s tied ones for the expensive",
          n_expensive, n_tied, format(n_tied_all, big.mark = ",")),
  "         calls (the tie census above is exhaustive; only the watershed and",
  "         trace calls over the tied positions are sampled)",
  sprintf("         %d blue lines for the head case, each sent at its own top",
          n_tops_sampled),
  sprintf("         (max upstream_route_measure over every segment); on %d the top",
          n_tops_guarded),
  "         is a candidate segment's, as blk_top() in the gate test takes it",
  "         sampling rule: ORDER BY md5(<id>::text) LIMIT n",
  "",
  "## population (research/fwa_point_snap.md, fresh#247)",
  utils::capture.output(print(population, row.names = FALSE)),
  "",
  "## CSV measures swept",
  utils::capture.output(print(csv_counts, row.names = FALSE)),
  "",
  "## ties, measured once on the base side (geometry, which no migration changes)",
  utils::capture.output(print(ties, row.names = FALSE)),
  utils::capture.output(print(heads, row.names = FALSE)),
  "",
  "## three states",
  # without `secs`: elapsed time is not reproducible, and the header already
  # carries it. Leaving it here made two otherwise identical runs differ.
  utils::capture.output(print(summary[, setdiff(names(summary), "secs")],
                              row.names = FALSE)),
  "",
  "## errors, by message",
  errors_by_message(),
  "",
  "## the head case: fwa_locatealong() at each sampled blue line's own top",
  "  (one row per line in sweep_tops.csv)",
  utils::capture.output(print(tops_summary, row.names = FALSE)),
  "",
  sprintf("## answers that moved: %d", nrow(moved)),
  if (nrow(moved)) {
    utils::capture.output(print(exact_m(utils::head(moved, 60)), row.names = FALSE))
  } else {
    "  none"
  },
  "",
  "## note on crossings.csv",
  "  its measures are bcfishpass's own fractional indexing; fresh never emits a",
  "  fractional measure, so that part measures the migration at the fwapg level",
  "  rather than on a fresh code path.",
  "",
  "## what this sweep does not pin",
  "  frs_cluster()'s downstream trace starts are always a segment's own",
  "  downstream_route_measure, inside its range under either rule, and its",
  "  CROSS JOIN LATERAL drops a zero-row trace silently - counted above as",
  "  trace_empty rather than pinned as a behaviour change."
)
writeLines(c(header, body), file.path(dir_out, "sweep.txt"))
# `secs` is left out here for the same reason it is left out of the body: it is
# tracked, and two runs over identical inputs would differ on it. The header
# carries the elapsed times.
utils::write.csv(summary[, setdiff(names(summary), "secs")],
                 file.path(dir_out, "sweep_summary.csv"), row.names = FALSE)
write_exact(moved, file.path(dir_out, "sweep_changed.csv"))
write_exact(tops_lines, file.path(dir_out, "sweep_tops.csv"), cols = c("m", "m_guarded"))
all_errors <- do.call(rbind, lapply(states, function(s) {
  if (!nrow(s$errors)) {
    return(NULL)
  }
  # the first line only: a PostgreSQL error from one of these functions embeds
  # the whole offending statement, which is hundreds of lines of fwapg SQL
  e <- s$errors
  e$message <- sub("\n.*$", "", e$message)
  cbind(data.frame(state = s$label), e)
}))
if (is.null(all_errors)) {
  all_errors <- data.frame(state = character(), call = character(),
                           blue_line_key = numeric(), m = numeric(),
                           message = character(), stringsAsFactors = FALSE)
}
write_exact(all_errors, file.path(dir_out, "sweep_errors.csv"))
message("wrote ", file.path(dir_out, "sweep.txt"))

conn <- fwapg_conn()
drop_all()
DBI::dbDisconnect(conn)
