# -- .frs_conn_resolve (no DB) -------------------------------------------------

# Clear every env var the resolver reads, then set only what a test needs.
local_pg_env <- function(..., .env = parent.frame()) {
  cols_env <- c("PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
                "PGPASSWORD", "PGSERVICE", "PGCONNECT_TIMEOUT",
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

# -- .frs_conn_bounds (no DB, #305) --------------------------------------------

bounds_idle <- list(keepalives = 1L, keepalives_idle = 60L,
                    keepalives_interval = 10L, keepalives_count = 6L)

test_that("connect_timeout: explicit wins, then PGCONNECT_TIMEOUT, then 10 s", {
  local_pg_env()
  expect_identical(fresh:::.frs_conn_bounds()$connect_timeout, 10L)
  expect_identical(fresh:::.frs_conn_bounds(connect_timeout = 3)$connect_timeout,
                   3L)

  # Set in the environment: nothing is passed, so libpq reads it itself
  local_pg_env(PGCONNECT_TIMEOUT = "30")
  expect_false("connect_timeout" %in% names(fresh:::.frs_conn_bounds()))
  expect_identical(fresh:::.frs_conn_bounds(connect_timeout = 3)$connect_timeout,
                   3L)
})

test_that("connect_timeout = 0 is allowed (libpq: no limit)", {
  local_pg_env()
  expect_identical(fresh:::.frs_conn_bounds(connect_timeout = 0)$connect_timeout,
                   0L)
})

test_that("an invalid connect_timeout is refused", {
  local_pg_env()
  for (bad in list(-1, 2.5, NA_real_, NA, c(5, 10), "10", Inf, TRUE)) {
    expect_error(fresh:::.frs_conn_bounds(connect_timeout = bad),
                 "connect_timeout", info = deparse(bad))
  }
})

test_that("idle-connection bounds default on, and ... overrides them", {
  local_pg_env()
  b <- fresh:::.frs_conn_bounds()
  expect_identical(b[names(bounds_idle)], bounds_idle)
  expect_setequal(names(b), c("connect_timeout", names(bounds_idle)))

  b <- fresh:::.frs_conn_bounds(keepalives = 0L, sslmode = "disable")
  expect_identical(b$keepalives, 0L)
  expect_identical(b$sslmode, "disable")

  # NULL drops a default, leaving the value to libpq / the OS
  b <- fresh:::.frs_conn_bounds(keepalives_idle = NULL)
  expect_false("keepalives_idle" %in% names(b))

  # Positional args bind to connect_timeout first, so unnamed means extra
  expect_error(fresh:::.frs_conn_bounds(NULL, 1L), "named")
})

test_that("whole doubles reach libpq as integers, never in e-notation", {
  local_pg_env()
  b <- fresh:::.frs_conn_bounds(tcp_user_timeout = 300000,
                                keepalives_idle = 1e5)
  expect_identical(b$tcp_user_timeout, 300000L)
  expect_identical(as.character(b$keepalives_idle), "100000")
  big <- fresh:::.frs_conn_bounds(tcp_user_timeout = 3e10)$tcp_user_timeout
  expect_identical(big, "30000000000")
  # Left alone: text and fractional values are libpq's to judge
  expect_identical(fresh:::.frs_conn_bounds(sslmode = "require")$sslmode,
                   "require")
  expect_identical(fresh:::.frs_conn_bounds(x = 2.5)$x, 2.5)
})

test_that("frs_db_conn passes the bounds under every variable group", {
  skip_if_not_installed("mockery")
  f <- frs_db_conn
  mockery::stub(f, "DBI::dbConnect", function(drv, ...) list(...))

  # standard
  local_pg_env(PGHOST = "localhost", PGDATABASE = "fwapg")
  args <- f()
  expect_identical(args[names(bounds_idle)], bounds_idle)
  expect_identical(args$connect_timeout, 10L)
  expect_null(args$host)

  # legacy share
  local_pg_env(PG_HOST_SHARE = "localhost", PG_DB_SHARE = "bcfishpass")
  args <- suppressMessages(f(connect_timeout = 4))
  expect_identical(args[names(bounds_idle)], bounds_idle)
  expect_identical(args$connect_timeout, 4L)
  expect_identical(args$dbname, "bcfishpass")

  # nothing set
  local_pg_env()
  args <- f(keepalives = 0L)
  expect_identical(args$keepalives, 0L)
  expect_identical(args$connect_timeout, 10L)
})

test_that(".frs_conn_params carries the bounds to frs_habitat() workers", {
  skip_if_not_installed("mockery")
  f <- fresh:::.frs_conn_params
  mockery::stub(f, "DBI::dbGetInfo", function(conn) {
    list(dbname = "fwapg", host = "h", port = "5432", username = "u")
  })
  local_pg_env()
  p <- f(conn = NULL, password = "pw")
  expect_identical(p[c("dbname", "host", "port", "user", "password")],
                   list(dbname = "fwapg", host = "h", port = "5432",
                        user = "u", password = "pw"))
  expect_identical(p[names(bounds_idle)], bounds_idle)
  expect_identical(p$connect_timeout, 10L)

  # A worker may not share the parent's environment, so the parent's
  # PGCONNECT_TIMEOUT travels as an explicit value
  local_pg_env(PGCONNECT_TIMEOUT = "30")
  expect_identical(f(conn = NULL)$connect_timeout, "30")
})

# -- silent host (no DB, #305) -------------------------------------------------

# A listening socket that is never accepted: the kernel completes the TCP
# handshake, libpq sends its startup packet and waits for a reply that never
# comes. Without a connect bound that wait has no end.
local_silent_port <- function(env = parent.frame()) {
  for (i in seq_len(50)) {
    port <- sample(49152:65000, 1)
    s <- tryCatch(serverSocket(port), error = function(e) NULL)
    if (!is.null(s)) {
      withr::defer(close(s), envir = env)
      return(port)
    }
  }
  testthat::skip("no free local port for a silent listener")
}

test_that("a silent host fails within connect_timeout, so the gate skips", {
  skip_on_cran()
  local_pg_env()
  port <- local_silent_port()
  connect <- function() {
    frs_db_conn(host = "127.0.0.1", port = port, dbname = "x", user = "x",
                password = "x", connect_timeout = 2)
  }
  t0 <- Sys.time()
  cnd <- expect_condition(skip_if_no_conn(connect), class = "skip")
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  expect_match(conditionMessage(cnd), "timeout expired")
  expect_lt(elapsed, 15)
})

# -- live ----------------------------------------------------------------------

test_that("frs_db_conn returns a DBI connection", {
  skip_if_not(.frs_db_available(), "DB not available")

  conn <- frs_db_conn()
  expect_s4_class(conn, "PqConnection")
  DBI::dbDisconnect(conn)
})
