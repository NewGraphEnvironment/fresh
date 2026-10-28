# Measure fresh#272: frs_network_features()'s downstream walk before and after
# the scoped walk (AOI segments in a session temp table, features prefiltered
# to what fwa_downstream() can reach), on the function's own SQL.
#
# Old form: R/frs_network_features.R at tag v0.44.0, sourced into a private
# environment with frs_db_query() replaced by a capture, so the SQL v0.44.0
# sends is run as text. New form: this source tree, with .frs_db_execute()
# passed through and timed (the temp table's DDL) except for the DROP, and
# frs_db_query() captured, so the walk runs against the still-present temp
# table; the script drops it after. Both forms are digested by the same SQL
# (link#261's digest_sql: md5 of `id:array` in the walk's own order, and with
# each array sorted). The sorted digests must agree; the ordered ones may not,
# because the new form breaks ties on the feature id.
#
# segments = fresh_default.streams with aoi = <group>: the shape fresh
# documents, a province-wide segments table scoped by `aoi`. features = link's
# barrier views in fresh_default (CH and BT access views, the anthropogenic
# source). include_equivalents = TRUE, as link calls it.
#
# Runs are interleaved old, new, new, old per walk. Each statement has a
# 10-minute timeout; a timed-out run is recorded (seconds NA, timed_out TRUE)
# and the second old run is skipped once the first has timed out. A censored
# old form takes its digest from the same SQL with `segments` replaced by an
# indexed, analyzed temp copy of the group (the shape link measured), so every
# walk still has an oracle.
#
# Local fwapg only, through the FRESH_PG* variables (tests/testthat/helper-db.R
# defaults: the docker/ container), never frs_db_conn(). Refuses to start when
# another client backend is active.
#
# Usage (from the fresh repo root):
#   Rscript data-raw/network_features_prefilter.R [WSG ...]
#   Rscript data-raw/network_features_prefilter.R SALR LKEL CHWK LSKE
# Writes data-raw/logs/network_features_272/walks.tsv (appended).

pkgload::load_all(".", quiet = TRUE)

wsgs <- toupper(commandArgs(trailingOnly = TRUE))
if (length(wsgs) == 0L) wsgs <- c("SALR", "LKEL", "CHWK", "LSKE")
stopifnot(all(grepl("^[A-Z]{3,5}$", wsgs)))
views <- c("barriers_ch_access", "barriers_bt_access",
           "barriers_anthropogenic_unified")
# NF272_VIEWS, NF272_OUT and NF272_TIMEOUT_MS narrow a smoke run and keep it
# out of the log
if (nzchar(Sys.getenv("NF272_VIEWS"))) {
  views <- strsplit(Sys.getenv("NF272_VIEWS"), ",", fixed = TRUE)[[1]]
}
sch <- "fresh_default"
old_ref <- "v0.44.0"
timeout_ms <- as.integer(Sys.getenv("NF272_TIMEOUT_MS", "600000"))
out_dir <- Sys.getenv("NF272_OUT", "data-raw/logs/network_features_272")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

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
has_schema <- nrow(q(sprintf("SELECT 1 FROM pg_namespace WHERE nspname = '%s'", sch))) > 0L
rels <- paste0(sch, ".", c("streams", views))
rel_absent <- function(r) {
  is.na(q(sprintf("SELECT to_regclass('%s')::text AS r", r))$r)
}
missing_rels <- rels[vapply(rels, rel_absent, logical(1))]
if (!has_schema || length(missing_rels)) {
  what <- if (!has_schema) {
    "the schema is absent"
  } else {
    paste("missing", paste(missing_rels, collapse = ", "))
  }
  stop("needs link's `", sch, "` build: ", what,
       ". Build it with link's default pipeline (lnk_config(\"default\")),",
       " whose lnk_barriers_views() creates the barrier views.", call. = FALSE)
}

others <- function() {
  q("SELECT count(*)::int AS n FROM pg_stat_activity
     WHERE datname = current_database() AND state <> 'idle'
       AND pid <> pg_backend_pid() AND backend_type = 'client backend'")$n
}
if (others() > 0L) stop("REFUSE: another client backend is active", call. = FALSE)

# The old function, captured
old_env <- new.env(parent = asNamespace("fresh"))
old_src <- system2("git", c("show", sprintf("%s:R/frs_network_features.R", old_ref)),
                   stdout = TRUE)
if (!is.null(attr(old_src, "status"))) stop("git show ", old_ref, " failed")
eval(parse(text = old_src), envir = old_env)
old_env$frs_db_query <- function(conn, query) {
  old_env$captured <- query
  data.frame(id_segment = integer(), feature_ids = character())
}
features_name <- function(features) sub("^[^.]+\\.", "", features)
old_sql <- function(segments, features, aoi) {
  old_env$frs_network_features(
    conn,
    segments = segments, features = features,
    segment_id_col = "id_segment",
    feature_id_col = paste0(features_name(features), "_id"),
    direction = "downstream", aoi = aoi, include_equivalents = TRUE
  )
  old_env$captured
}

# The new function: DDL passed through and timed, DROP held back, walk captured
new_sql <- function(segments, features, aoi) {
  ddl_secs <- 0
  drops <- character(0)
  walk <- NULL
  testthat::with_mocked_bindings(
    frs_network_features(
      conn,
      segments = segments, features = features,
      segment_id_col = "id_segment",
      feature_id_col = paste0(features_name(features), "_id"),
      direction = "downstream", aoi = aoi, include_equivalents = TRUE
    ),
    .frs_db_execute = function(conn, sql) {
      if (startsWith(sql, "DROP")) {
        drops <<- c(drops, sql)
        return(0L)
      }
      t0 <- Sys.time()
      n <- DBI::dbExecute(conn, sql)
      ddl_secs <<- ddl_secs + as.numeric(difftime(Sys.time(), t0, units = "secs"))
      n
    },
    frs_db_query = function(conn, query) {
      walk <<- query
      data.frame(id_segment = integer(), feature_ids = character())
    },
    .package = "fresh"
  )
  stopifnot(length(drops) == 1L, !is.null(walk))
  list(sql = walk, ddl_secs = ddl_secs, drop = drops)
}

digest_sql <- function(sql) {
  paste0(
    "SELECT count(*)::int AS n,
       md5(string_agg(id_segment::text || ':' || coalesce(feature_ids::text, ''),
                      ',' ORDER BY id_segment)) AS d_order,
       md5(string_agg(id_segment::text || ':' || coalesce((SELECT array_agg(e ORDER BY e)::text
                      FROM unnest(feature_ids) e), ''), ',' ORDER BY id_segment)) AS d_set
     FROM (", sql, ") x"
  )
}

# Run a digest; a statement timeout is a censored run, anything else stops.
timed_digest <- function(sql) {
  t0 <- Sys.time()
  d <- tryCatch(q(digest_sql(sql)), error = function(e) {
    if (grepl("statement timeout", conditionMessage(e))) return(NULL)
    stop(e)
  })
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (is.null(d)) {
    return(list(n = NA_integer_, d_order = NA_character_, d_set = NA_character_,
                secs = NA_real_, timed_out = TRUE))
  }
  list(n = d$n, d_order = d$d_order, d_set = d$d_set, secs = round(secs, 3),
       timed_out = FALSE)
}

tsv <- file.path(out_dir, "walks.tsv")
cols <- c("wsg", "features", "form", "rep", "segments_out", "ddl_seconds",
          "walk_seconds", "seconds", "timed_out", "d_order", "d_set",
          "others_active", "measured_utc")
if (!file.exists(tsv)) cat(paste(cols, collapse = "\t"), "\n", sep = "", file = tsv)
emit <- function(...) {
  row <- list(...)
  cat(paste(vapply(cols, function(k) {
    v <- row[[k]]
    if (is.null(v) || (length(v) == 1L && is.na(v))) "NA" else as.character(v)
  }, character(1)), collapse = "\t"), "\n", sep = "", file = tsv, append = TRUE)
  cat(sprintf("[272] %s %-32s %-13s %s %8s s  %s\n", row$wsg, row$features,
              row$form, row$rep,
              if (is.na(row$seconds)) "timeout" else sprintf("%.1f", row$seconds),
              row$d_set))
}
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

for (aoi in wsgs) {
  for (v in views) {
    features <- paste0(sch, ".", v)
    old_censored <- FALSE
    for (rep in 1:4) {
      form <- if (rep %in% c(1L, 4L)) "old" else "new"
      if (form == "old" && rep == 4L && old_censored) {
        emit(wsg = aoi, features = v, form = form, rep = rep, timed_out = TRUE,
             seconds = NA, d_set = "skipped: first old run timed out",
             others_active = others(), measured_utc = now())
        next
      }
      if (form == "old") {
        r <- timed_digest(old_sql(paste0(sch, ".streams"), features, aoi))
        if (r$timed_out) old_censored <- TRUE
        emit(wsg = aoi, features = v, form = form, rep = rep,
             segments_out = r$n, walk_seconds = r$secs, seconds = r$secs,
             timed_out = r$timed_out, d_order = r$d_order, d_set = r$d_set,
             others_active = others(), measured_utc = now())
      } else {
        w <- new_sql(paste0(sch, ".streams"), features, aoi)
        r <- timed_digest(w$sql)
        x(w$drop)
        emit(wsg = aoi, features = v, form = form, rep = rep,
             segments_out = r$n, ddl_seconds = round(w$ddl_secs, 3),
             walk_seconds = round(r$secs, 3),
             seconds = round(w$ddl_secs + r$secs, 3),
             timed_out = r$timed_out, d_order = r$d_order, d_set = r$d_set,
             others_active = others(), measured_utc = now())
      }
    }
    if (old_censored) {
      # Oracle for the censored old form: the same v0.44.0 SQL with the group
      # in an indexed, analyzed temp table (link#261's sent shape).
      x("DROP TABLE IF EXISTS pg_temp.nf272_streams")
      x(sprintf("CREATE TEMP TABLE nf272_streams AS
                 SELECT * FROM %s.streams WHERE watershed_group_code = '%s'", sch, aoi))
      for (ix in c("(id_segment)", "(blue_line_key)", "USING gist (wscode_ltree)",
                   "USING gist (localcode_ltree)")) {
        x(sprintf("CREATE INDEX ON pg_temp.nf272_streams %s", ix))
      }
      x("ANALYZE pg_temp.nf272_streams")
      r <- timed_digest(old_sql("pg_temp.nf272_streams", features, aoi))
      emit(wsg = aoi, features = v, form = "old_scoped", rep = 0L,
           segments_out = r$n, walk_seconds = r$secs, seconds = r$secs,
           timed_out = r$timed_out, d_order = r$d_order, d_set = r$d_set,
           others_active = others(), measured_utc = now())
      x("DROP TABLE IF EXISTS pg_temp.nf272_streams")
    }
  }
}

DBI::dbDisconnect(conn)
