# Measure fresh#281: does an existence walk ("is any feature downstream of this
# segment?") beat the array walk, and which SQL form should it take?
#
# Every form walks the same scoped downstream shape #272 built: the group's
# segments in an indexed, analyzed session temp table (.frs_walk_scope(),
# built once per group and reused by every form), the features cut by
# .frs_walk_prefilter(), and the fwa_downstream() predicate with
# include_equivalents = TRUE, as link calls it. Forms:
#
#   ids          the array walk, as frs_network_features() sends it (captured).
#                Its digest reads only the ids, so the planner replaces the
#                unread array_agg with NULL: this times the join, the sort
#                and the GROUP BY, not the arrays (code-check round 1)
#   ids_arrays   the same SQL, digested with sum(cardinality(feature_ids)),
#                which makes the arrays be built; also counts the pairs
#   exists_sql   SELECT DISTINCT a.id FROM tmp a WHERE EXISTS (<feature> b ...)
#   distinct_sql SELECT DISTINCT a.id FROM tmp a INNER JOIN <features> b ON ...
#   exists_base_sql  exists_sql against the feature view itself, unprefiltered,
#                so each segment can probe the view's own indexes and stop at
#                its first match
#   exists       what frs_network_features(result = "exists") sends (captured),
#                once the function has the mode
#   fn_ids       frs_network_features() itself, end to end, as link calls it:
#   fn_exists    its own temp table, the walk, the transfer, and (for ids) the
#                R parse of every array; digested in the database from the
#                ids it returns
#
# Each form is digested to the set of segment ids it returns: count and md5 of
# the ids in order. For `ids` that is the segments with a row in the array
# result, which is what link reads (`id %in% result$id`). Every form of a walk
# must give the same digest.
#
# segments = fresh_default.streams with aoi = <group>; features = link's
# natural barrier views, one per barrier-set shape (CH, BT, ST access).
# Runs go ids, then the other forms, then the other forms reversed, then ids
# (A B C C B A). Each statement has a timeout (NF281_TIMEOUT_MS, default 30
# min); a timed-out run is written with seconds NA and timed_out TRUE, and the
# second ids run is skipped once the first has timed out (timed_out NA).
#
# Local fwapg only, through the FRESH_PG* variables (tests/testthat/helper-db.R
# defaults: the docker/ container), never frs_db_conn(). Refuses to start when
# another client backend is active.
#
# Usage (from the fresh repo root):
#   Rscript data-raw/network_features_exists.R [WSG ...]
#   Rscript data-raw/network_features_exists.R SALR CHWK LFRA
#   NF281_FORMS=ids,distinct_sql Rscript data-raw/network_features_exists.R SETN
#   NF281_FORMS=fn_ids,fn_exists Rscript data-raw/network_features_exists.R SALR
# NF281_VIEWS, NF281_FORMS, NF281_OUT and NF281_TIMEOUT_MS narrow a smoke run
# and keep it out of the log. NF281_EXPLAIN=1 writes EXPLAIN (ANALYZE, BUFFERS)
# of each SQL form to <out>/plans/ instead of timing.
# NF281_ALLOW_OTHERS=1 skips the idle-database refusal, for a smoke run only.
# Writes data-raw/logs/network_features_exists_281/walks.tsv (appended).

pkgload::load_all(".", quiet = TRUE)

wsgs <- toupper(commandArgs(trailingOnly = TRUE))
if (length(wsgs) == 0L) wsgs <- c("SALR", "CHWK", "LFRA")
stopifnot(all(grepl("^[A-Z]{3,5}$", wsgs)))
env_list <- function(name, default) {
  v <- Sys.getenv(name)
  if (nzchar(v)) strsplit(v, ",", fixed = TRUE)[[1]] else default
}
views <- env_list("NF281_VIEWS", c("barriers_ch_access", "barriers_bt_access",
                                   "barriers_st_access"))
forms <- env_list("NF281_FORMS", c("ids", "exists_sql", "distinct_sql"))
stopifnot(forms[1] %in% c("ids", "ids_arrays", "fn_ids"),
          all(forms %in% c("ids", "ids_arrays", "exists_sql", "distinct_sql",
                           "exists_base_sql", "exists", "fn_ids", "fn_exists")))
explain <- identical(Sys.getenv("NF281_EXPLAIN"), "1")
sch <- "fresh_default"
timeout_ms <- as.integer(Sys.getenv("NF281_TIMEOUT_MS", "1800000"))
out_dir <- Sys.getenv("NF281_OUT", "data-raw/logs/network_features_exists_281")
dir.create(file.path(out_dir, "plans"), recursive = TRUE, showWarnings = FALSE)

conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("FRESH_PGHOST", "localhost"),
  port = as.integer(Sys.getenv("FRESH_PGPORT", "5432")),
  dbname = Sys.getenv("FRESH_PGDATABASE", "fwapg"),
  user = Sys.getenv("FRESH_PGUSER", "postgres"),
  password = Sys.getenv("FRESH_PGPASSWORD", "postgres")
)
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))
x(sprintf("SET statement_timeout = %d", timeout_ms))

# Preconditions, before any timing
rels <- paste0(sch, ".", c("streams", views))
missing_rels <- rels[vapply(rels, function(r) {
  is.na(q(sprintf("SELECT to_regclass('%s')::text AS r", r))$r)
}, logical(1))]
if (length(missing_rels)) {
  stop("needs link's `", sch, "` build: missing ",
       paste(missing_rels, collapse = ", "),
       ". Build it with link's default pipeline (lnk_config(\"default\")).",
       call. = FALSE)
}
others <- function() {
  q("SELECT count(*)::int AS n FROM pg_stat_activity
     WHERE datname = current_database() AND state <> 'idle'
       AND pid <> pg_backend_pid() AND backend_type = 'client backend'")$n
}
if (others() > 0L && !identical(Sys.getenv("NF281_ALLOW_OTHERS"), "1")) {
  stop("REFUSE: another client backend is active", call. = FALSE)
}

cols_segments <- c("id_segment", "blue_line_key", "downstream_route_measure",
                   "wscode_ltree", "localcode_ltree")
id_col <- function(view) paste0(view, "_id")

# What frs_network_features() sends, with its temp table renamed to `tmp`:
# the scope is not built (the one built below is walked), the DROP is held
# back, and the walk is captured.
captured_sql <- function(view, aoi, tmp, result = NULL) {
  their_tmp <- NULL
  walk <- NULL
  args <- list(conn, segments = paste0(sch, ".streams"),
               features = paste0(sch, ".", view),
               segment_id_col = "id_segment", feature_id_col = id_col(view),
               direction = "downstream", aoi = aoi, include_equivalents = TRUE)
  if (!is.null(result)) args$result <- result
  testthat::with_mocked_bindings(
    do.call(frs_network_features, args),
    .frs_walk_scope = function(conn, tmp, ...) their_tmp <<- tmp,
    .frs_db_execute = function(conn, sql) 0L,
    frs_db_query = function(conn, query) {
      walk <<- query
      data.frame(id_segment = integer(), feature_ids = character())
    },
    .package = "fresh"
  )
  stopifnot(!is.null(their_tmp), !is.null(walk),
            grepl(their_tmp, walk, fixed = TRUE))
  gsub(their_tmp, tmp, walk, fixed = TRUE)
}

# The two hand-written candidates, on the same scope and prefilter.
candidate_sql <- function(form, view, tmp) {
  feats <- .frs_walk_prefilter(
    paste0(sch, ".", view), tmp,
    c(id_col(view), "blue_line_key", "downstream_route_measure",
      "wscode_ltree", "localcode_ltree"),
    "wscode_ltree", "wscode_ltree"
  )
  pred <- "whse_basemapping.fwa_downstream(
      a.blue_line_key, a.downstream_route_measure,
      a.wscode_ltree, a.localcode_ltree,
      b.blue_line_key, b.downstream_route_measure,
      b.wscode_ltree, b.localcode_ltree,
      true, 1)"
  if (form == "exists_base_sql") feats <- paste0(sch, ".", view)
  if (form %in% c("exists_sql", "exists_base_sql")) {
    sprintf("SELECT DISTINCT a.id_segment FROM %s a
             WHERE EXISTS (SELECT 1 FROM %s b WHERE %s)", tmp, feats, pred)
  } else {
    sprintf("SELECT DISTINCT a.id_segment FROM %s a
             INNER JOIN %s b ON %s", tmp, feats, pred)
  }
}

walk_sql <- function(form, view, aoi, tmp) {
  switch(form,
    ids = ,
    ids_arrays = captured_sql(view, aoi, tmp),
    exists = captured_sql(view, aoi, tmp, result = "exists"),
    candidate_sql(form, view, tmp)
  )
}

digest_sql <- function(sql, pairs = FALSE) {
  paste0("SELECT count(*)::int AS n,
            md5(string_agg(id_segment::text, ',' ORDER BY id_segment)) AS d_ids",
         if (pairs) ", sum(cardinality(feature_ids))::bigint AS n_pairs" else "",
         " FROM (", sql, ") x")
}

# The function end to end, its returned ids digested like digest_sql's.
timed_fn <- function(form, view, aoi) {
  t0 <- Sys.time()
  res <- tryCatch(
    frs_network_features(
      conn, segments = paste0(sch, ".streams"), features = paste0(sch, ".", view),
      segment_id_col = "id_segment", feature_id_col = id_col(view),
      direction = "downstream", aoi = aoi, include_equivalents = TRUE,
      result = sub("^fn_", "", form)
    ),
    error = function(e) {
      if (grepl("statement timeout", conditionMessage(e))) return(NULL)
      stop(e)
    }
  )
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (is.null(res)) {
    return(list(n = NA_integer_, d_ids = NA_character_, secs = NA_real_,
                timed_out = TRUE))
  }
  ids <- sort(as.numeric(res$id_segment))
  stopifnot(!anyNA(ids))
  d <- q(sprintf("SELECT md5(%s) AS d",
                 DBI::dbQuoteString(conn, paste(format(ids, scientific = FALSE,
                                                       trim = TRUE),
                                                collapse = ","))))$d
  list(n = length(ids), d_ids = d, secs = round(secs, 3), timed_out = FALSE)
}

# Run a digest; a statement timeout is a censored run, anything else stops.
timed_digest <- function(sql, pairs = FALSE) {
  t0 <- Sys.time()
  d <- tryCatch(q(digest_sql(sql, pairs)), error = function(e) {
    if (grepl("statement timeout", conditionMessage(e))) return(NULL)
    stop(e)
  })
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (is.null(d)) {
    return(list(n = NA_integer_, d_ids = NA_character_, secs = NA_real_,
                timed_out = TRUE))
  }
  list(n = d$n, d_ids = d$d_ids, secs = round(secs, 3), timed_out = FALSE,
       n_pairs = if (pairs) d$n_pairs else NA)
}

tsv <- file.path(out_dir, "walks.tsv")
cols <- c("wsg", "features", "form", "rep", "segments_out", "seconds",
          "timed_out", "d_ids", "others_active", "measured_utc", "n_pairs")
if (!explain && !file.exists(tsv)) {
  cat(paste(cols, collapse = "\t"), "\n", sep = "", file = tsv)
}
emit <- function(...) {
  row <- list(...)
  cat(paste(vapply(cols, function(k) {
    v <- row[[k]]
    if (is.null(v) || (length(v) == 1L && is.na(v))) "NA" else as.character(v)
  }, character(1)), collapse = "\t"), "\n", sep = "", file = tsv, append = TRUE)
  cat(sprintf("[281] %s %-20s %-12s %s %8s s  %s %s\n", row$wsg, row$features,
              row$form, row$rep,
              if (is.na(row$seconds)) "timeout" else sprintf("%.1f", row$seconds),
              row$segments_out, row$d_ids))
}
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

order_runs <- c(forms, rev(forms))
for (aoi in wsgs) {
  tmp <- sprintf("pg_temp.nf281_%s", tolower(aoi))
  x(sprintf("DROP TABLE IF EXISTS %s", tmp))
  .frs_walk_scope(conn, tmp, paste0(sch, ".streams"), aoi, cols_segments,
                  "wscode_ltree", "localcode_ltree")
  for (v in views) {
    if (explain) {
      for (form in setdiff(forms, c("fn_ids", "fn_exists"))) {
        js <- q(paste("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)",
                      walk_sql(form, v, aoi, tmp)))[[1]]
        writeLines(js, file.path(out_dir, "plans",
                                 sprintf("%s_%s_%s.json", aoi, v, form)))
        cat(sprintf("[281] explain %s %s %s written\n", aoi, v, form))
      }
      next
    }
    ids_censored <- FALSE
    for (rep in seq_along(order_runs)) {
      form <- order_runs[rep]
      is_ids <- form %in% c("ids", "ids_arrays", "fn_ids")
      if (is_ids && rep == length(order_runs) && ids_censored) {
        emit(wsg = aoi, features = v, form = form, rep = rep, timed_out = NA,
             seconds = NA, d_ids = "skipped: first ids run timed out",
             others_active = others(), measured_utc = now())
        next
      }
      r <- if (startsWith(form, "fn_")) {
        timed_fn(form, v, aoi)
      } else {
        timed_digest(walk_sql(form, v, aoi, tmp), pairs = form == "ids_arrays")
      }
      if (is_ids && r$timed_out) ids_censored <- TRUE
      emit(wsg = aoi, features = v, form = form, rep = rep,
           segments_out = r$n, seconds = r$secs, timed_out = r$timed_out,
           d_ids = r$d_ids, others_active = others(), measured_utc = now(),
           n_pairs = r$n_pairs)
    }
  }
  x(sprintf("DROP TABLE IF EXISTS %s", tmp))
}

DBI::dbDisconnect(conn)
