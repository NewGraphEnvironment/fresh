# -- .frs_conn_resolve (no DB) -------------------------------------------------

# Clear every env var the resolver reads, then set only what a test needs.
local_pg_env <- function(..., .env = parent.frame()) {
  cols_env <- c("PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
                "PGPASSWORD", "PGSERVICE",
                "PG_DB_SHARE", "PG_HOST_SHARE", "PG_PORT_SHARE",
                "PG_USER_SHARE", "PG_PASS_SHARE")
  vals <- stats::setNames(rep(NA_character_, length(cols_env)), cols_env)
  set <- c(...)
  vals[names(set)] <- set
  withr::local_envvar(vals, .local_envir = .env)
  # Reset the once-per-session message flag for this test
  state <- fresh:::.frs_state
  old <- state$share_msg_shown
  state$share_msg_shown <- FALSE
  withr::defer(state$share_msg_shown <- old, envir = .env)
}

test_that("standard PG* vars are left to libpq", {
  local_pg_env(PGHOST = "localhost", PGPORT = "5432", PGDATABASE = "fwapg",
               PGUSER = "postgres")
  res <- fresh:::.frs_conn_resolve()
  expect_identical(res$source, "standard")
  expect_length(res$params, 0)
})

test_that("standard PG* vars win when both groups are set", {
  local_pg_env(PGHOST = "localhost", PGPORT = "5432", PGDATABASE = "fwapg",
               PG_HOST_SHARE = "localhost", PG_PORT_SHARE = "63333",
               PG_DB_SHARE = "bcfishpass", PG_USER_SHARE = "newgraph",
               PG_PASS_SHARE = "secret")
  expect_silent(res <- fresh:::.frs_conn_resolve())
  expect_identical(res$source, "standard")
  expect_length(res$params, 0)
})

test_that("groups never mix: PGHOST alone blocks PG_DB_SHARE", {
  local_pg_env(PGHOST = "localhost", PG_DB_SHARE = "bcfishpass")
  res <- fresh:::.frs_conn_resolve()
  expect_identical(res$source, "standard")
  expect_null(res$params$dbname)
})

test_that("PGSERVICE or PGHOSTADDR alone count as the standard group", {
  local_pg_env(PGSERVICE = "fwapg", PG_DB_SHARE = "bcfishpass")
  expect_identical(fresh:::.frs_conn_resolve()$source, "standard")

  local_pg_env(PGHOSTADDR = "127.0.0.1", PG_DB_SHARE = "bcfishpass")
  expect_identical(fresh:::.frs_conn_resolve()$source, "standard")
})

test_that("PG_*_SHARE fallback resolves and messages once per session", {
  local_pg_env(PG_HOST_SHARE = "localhost", PG_PORT_SHARE = "63333",
               PG_DB_SHARE = "bcfishpass", PG_USER_SHARE = "newgraph",
               PG_PASS_SHARE = "secret")
  expect_message(res <- fresh:::.frs_conn_resolve(), "PG_\\*_SHARE")
  expect_identical(res$source, "share")
  expected <- list(dbname = "bcfishpass", host = "localhost", port = "63333",
                   user = "newgraph", password = "secret")
  expect_identical(res$params, expected)
  expect_silent(fresh:::.frs_conn_resolve())
})

test_that("empty PG_PASS_SHARE is dropped so libpq can use .pgpass", {
  local_pg_env(PG_HOST_SHARE = "localhost", PG_DB_SHARE = "bcfishpass",
               PG_PASS_SHARE = "")
  res <- suppressMessages(fresh:::.frs_conn_resolve())
  expect_identical(res$source, "share")
  expect_false("password" %in% names(res$params))
})

test_that("explicit args override the environment per field", {
  local_pg_env(PG_HOST_SHARE = "localhost", PG_PORT_SHARE = "63333",
               PG_DB_SHARE = "bcfishpass")
  res <- suppressMessages(fresh:::.frs_conn_resolve(port = 5432,
                                                    dbname = "fwapg"))
  expect_identical(res$params$port, 5432)
  expect_identical(res$params$dbname, "fwapg")
  expect_identical(res$params$host, "localhost")

  local_pg_env(PGHOST = "localhost")
  res <- fresh:::.frs_conn_resolve(dbname = "bcfishpass", password = "pw")
  expect_identical(res$params, list(dbname = "bcfishpass", password = "pw"))
})

test_that("explicit empty-string args are treated as unset", {
  local_pg_env(PGHOST = "localhost")
  res <- fresh:::.frs_conn_resolve(dbname = "", host = "")
  expect_length(res$params, 0)
})

test_that("nothing set leaves everything to libpq defaults", {
  local_pg_env()
  expect_silent(res <- fresh:::.frs_conn_resolve())
  expect_identical(res$source, "default")
  expect_length(res$params, 0)
})

# -- live ----------------------------------------------------------------------

test_that("frs_db_conn returns a DBI connection", {
  skip_if_not(.frs_db_available(), "DB not available")

  conn <- frs_db_conn()
  expect_s4_class(conn, "PqConnection")
  DBI::dbDisconnect(conn)
})
