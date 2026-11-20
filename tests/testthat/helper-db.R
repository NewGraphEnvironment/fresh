# Skip when the connected DB lacks a schema. The default connection may be
# a local fwapg (whse_basemapping, bcfishobs, working) without the
# bcfishpass schema, which lives on the shared tunnel DB.
skip_if_no_schema <- function(schema) {
  has <- tryCatch({
    conn <- frs_db_conn()
    on.exit(DBI::dbDisconnect(conn))
    nrow(DBI::dbGetQuery(conn, sprintf(
      "SELECT 1 FROM pg_namespace WHERE nspname = %s",
      DBI::dbQuoteString(conn, schema)))) > 0L
  }, error = function(e) FALSE)
  testthat::skip_if_not(has, sprintf("schema %s not in DB", schema))
}

# Skip when a connection can't actually be made. A set credential env var
# doesn't mean the server is reachable, so gate on a real connect +
# SELECT 1. `connect` is any zero-arg function returning a DBI connection,
# so live tests against a non-default DB (e.g. the bcfishpass tunnel) can
# pass their own connector. Any error skips — including bad credentials or
# a broken connector — so the error text goes into the skip message.
skip_if_no_conn <- function(connect = frs_db_conn) {
  err <- tryCatch({
    conn <- connect()
    on.exit(DBI::dbDisconnect(conn))
    DBI::dbGetQuery(conn, "SELECT 1")
    NULL
  }, error = function(e) conditionMessage(e))
  if (!is.null(err)) {
    testthat::skip(paste("DB connection failed:", err))
  }
}

# A connection to a local fwapg, or a skip. `FRESH_PG*` env vars, defaulting to
# the `docker/` container, because these tests must not reach the shared
# instance the `PG*` vars name: a trial DROPs and recreates fwapg's functions
# inside its transaction, and a rollback there is not a full undo (`dblink` is
# installed on the shared host). Never on CI: they need the database.
frs_fwapg_conn <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("FRESH_PGHOST", "localhost"),
    port = as.integer(Sys.getenv("FRESH_PGPORT", "5432")),
    dbname = Sys.getenv("FRESH_PGDATABASE", "fwapg"),
    user = Sys.getenv("FRESH_PGUSER", "postgres"),
    password = Sys.getenv("FRESH_PGPASSWORD", "postgres")
  )
}

local_fwapg <- function(env = parent.frame()) {
  testthat::skip_on_ci()
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("RPostgres")
  conn <- tryCatch(frs_fwapg_conn(), error = function(e) NULL)
  if (is.null(conn)) testthat::skip("no local fwapg database")
  withr::defer(DBI::dbDisconnect(conn), envir = env)
  conn
}

# Does this database's fwa_indexpoint() have fwapg#41's rework? The reworked
# one is the one with the include_disconnected filter. '…'::regproc THROWS
# when the function is absent or ambiguous, so the skip path catches that — an
# error there would be a test error, not a skip. The gate test in
# test-frs_fwapg_gate.R deliberately does not catch it.
frs_indexpoint_current <- function(conn) {
  a <- tryCatch(
    DBI::dbGetQuery(conn,
      "SELECT pg_get_function_arguments('whse_basemapping.fwa_indexpoint'::regproc) AS a")$a,
    error = function(e) NA_character_)
  isTRUE(any(grepl("include_disconnected", a)))
}

# FRESH_FWAPG_CURRENT=true (or 1) says this database should already have the
# rework. Then a stale one does not skip: the assertions run and fail, and so
# does the gate test, which reads committed state on its own connection.
# A value this does not recognise must not read as "not set": everything else
# here is built so a stale database cannot hide, and this is the one input that
# would turn the gate off quietly. A trailing space is easy to acquire from a
# Makefile variable or a YAML `env:` block.
frs_fwapg_current_wanted <- function() {
  v <- tolower(trimws(Sys.getenv("FRESH_FWAPG_CURRENT")))
  if (v %in% c("true", "1", "yes", "y", "t", "on")) {
    return(TRUE)
  }
  if (!v %in% c("", "false", "0", "no", "n", "f", "off")) {
    stop("FRESH_FWAPG_CURRENT is set to ", sQuote(Sys.getenv("FRESH_FWAPG_CURRENT")),
         ", which is neither true nor false: refusing to guess, because guessing ",
         "false would let a stale database skip instead of fail")
  }
  FALSE
}

# FRESH_FWAPG_TRIAL names the migration file(s) to apply inside a transaction
# rolled back when the test ends, so the tests below can run against a
# migration no database has yet. Several files are separated by
# .Platform$path.sep, applied in the order given.
frs_fwapg_trial_files <- function() {
  v <- Sys.getenv("FRESH_FWAPG_TRIAL")
  if (!nzchar(v)) {
    return(character())
  }
  strsplit(v, .Platform$path.sep, fixed = TRUE)[[1]]
}

# A connection whose fwa_indexpoint() has the rework, or a skip naming the
# migration that is missing.
local_fwapg_indexpoint <- function(env = parent.frame()) {
  conn <- local_fwapg(env)
  files <- frs_fwapg_trial_files()
  if (length(files)) {
    # testthat runs from tests/testthat, so a relative path names another file
    absent <- files[!file.exists(files)]
    if (length(absent)) {
      stop("FRESH_FWAPG_TRIAL names no such file: ", paste(absent, collapse = ", "),
           " (give an absolute path)")
    }
    # `env` passed through, or the rollback fires before the test body runs —
    # and before the disconnect local_fwapg() deferred, since defer() prepends
    frs_migration_trial(conn, files, env = env)
  }
  if (!frs_indexpoint_current(conn) && !frs_fwapg_current_wanted()) {
    testthat::skip(paste(
      "fwapg's fwa_indexpoint() predates migration 202610240132__indexpoint_tiebreak",
      "(NewGraphEnvironment/fwapg#41); set FRESH_FWAPG_TRIAL to trial it"))
  }
  conn
}

# --- Per-run table names (#279) ---------------------------------------------
#
# Integration tests write scratch tables into the shared `working` schema. A
# fixed name there is shared by every run against the same database, so two
# runs (a suite, a mutation sweep, a reviewer's probe) create, drop and
# truncate each other's tables, and the run that loses fails in a way nobody
# can reproduce. Every table a live test creates is therefore named through
# frs_test_tbl(), and every frs_habitat() label through frs_test_label(): the
# label names frs_habitat()'s own working.streams_<label> and
# working.barriers_<label>_gradient tables, which no `to_*` argument reaches.
# test-test_table_names.R fails on a fixed `working` name in a live block.
#
# The run id comes from the session's tempdir (RtmpXXXXXX), which mkdtemp
# makes unique on this machine and random across machines, and is computed
# once, when the helpers load. Lower case, because Postgres folds unquoted
# identifiers.
frs_test_run_id <- local({
  s <- tolower(sub("^Rtmp", "", basename(tempdir())))
  if (!grepl("^[a-z0-9]{6}$", s)) {
    stop("unexpected tempdir name ", sQuote(basename(tempdir())),
         ": cannot derive a per-run table prefix from it")
  }
  paste0("t", s)
})

# "working.<run>_<name>". `name` keeps its case: one test is about how
# Postgres folds a mixed-case unquoted name.
frs_test_tbl <- function(name) {
  stopifnot(is.character(name), length(name) == 1L,
            grepl("^[A-Za-z_][A-Za-z0-9_]*$", name))
  paste0("working.", frs_test_run_id, "_", name)
}

# "<run>_<label>", for frs_habitat(label =).
frs_test_label <- function(label) {
  stopifnot(is.character(label), length(label) == 1L,
            grepl("^[A-Za-z0-9_]+$", label))
  paste0(frs_test_run_id, "_", label)
}

# Schema and table of a frs_test_tbl() name, folded to lower case as Postgres
# stores an unquoted identifier, for information_schema / pg_catalog lookups.
frs_test_tbl_parts <- function(tbl) {
  p <- strsplit(tolower(tbl), ".", fixed = TRUE)[[1]]
  stopifnot(length(p) == 2L)
  list(schema = p[[1]], table = p[[2]])
}

# Drop every relation in `working` that this run named, and return the names
# found. Run at the end of the suite (setup-run_namespace.R); a name it finds
# is a test that did not clean up after itself.
frs_test_sweep <- function(conn, run_id = frs_test_run_id) {
  rel <- DBI::dbGetQuery(conn, sprintf(
    "SELECT c.relname, c.relkind
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'working' AND c.relkind IN ('r', 'p', 'v', 'm')
        AND left(c.relname, %d) = %s",
    nchar(run_id) + 1L, DBI::dbQuoteString(conn, paste0(run_id, "_"))))
  for (i in seq_len(nrow(rel))) {
    kind <- switch(rel$relkind[i], v = "VIEW", m = "MATERIALIZED VIEW", "TABLE")
    DBI::dbExecute(conn, sprintf("DROP %s IF EXISTS working.%s CASCADE", kind,
                                 DBI::dbQuoteIdentifier(conn, rel$relname[i])))
  }
  rel$relname
}
