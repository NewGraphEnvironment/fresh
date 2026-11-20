# Code-check round 1: branch 305 (frs_db_conn timeouts)

## Checklist read

- **code-check-infra.md**: in full.
- **code-check.md**: the index in full; the prose of all 14 H3s under `## Mechanisms` (table rows skipped). Of the 24 headings outside Mechanisms, none named a tool or shape this diff uses, so I read none of them in full.
- **code-check-r.md**: the index in full. I read 8 headings in full: "A `function(...)` mock hides arguments the real callee no longer accepts"; "Verify a float-formatting fix in its consumer, not through `as.numeric()`"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED package"; "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared"; "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words…"; "A `skip_if_not()` skips only its own `test_that()` block"; "`$` on a list partial-matches…"; "testthat counts an uncaught error under `error`, not `failed`". I did not read the other 118.
- **code-check-shell.md**: the index in full. The diff has no shell, so I read 0 of 72 headings in full.
- **code-check-spatial.md**: the index in full. The diff has no spatial code, so I read 0 of 94 headings in full.

## Findings

- **[severity: fragile]** R/frs_db_conn.R:181 (`.frs_conn_bounds()`, default `tcp_user_timeout = 120000L`): libpq accepts the `tcp_user_timeout` keyword only from PostgreSQL 12. An older libpq rejects any keyword it does not know, and the whole connect fails. Measured here: RPostgres 1.4.10 on libpq 16.8 (`RPostgres:::client_version()` = 160008) answers `DBI::dbConnect(RPostgres::Postgres(), ..., bogus_kw = 1L)` with `invalid connection option "bogus_kw"`. The default goes out on every call, so on a source build of RPostgres against a system libpq 10 or 11, every `frs_db_conn()` call errors where it connected before this branch. That covers every `frs_habitat()` worker (via `.frs_conn_params()`) and both test helpers. Examples: RHEL 8 `postgresql-libs` is 10, Debian 10 is 11. The roxygen says libpq "ignores it elsewhere", but that holds only on libpq 12 and later; an older libpq refuses it, it does not ignore it. Nothing in DESCRIPTION or the docs states a libpq floor. The CRAN macOS and Windows binaries and current Ubuntu ship libpq 12 or later, so this machine and CI cannot show the failure. One remedy: add the default only when `RPostgres:::client_version() >= 120000L` (an internal), or only on Linux, the one platform where the keyword does anything. The other: state the floor. I could not run an old libpq to test it. The version fact comes from PostgreSQL 12's release notes, where `tcp_user_timeout` was added.
  - **Rule:** none

No other issues found. Checked and not reported:

- Workers do use the bounds. `frs_habitat()` passes `.frs_conn_params()` straight into `do.call(DBI::dbConnect, ...)` at R/frs_habitat.R:395 and :581.
- Arguments: a keyword in `...` cannot collide with an identity field, because those are all formals. No libpq keyword partial-matches a formal (`hostaddr` and `passfile` are not prefixes of `host` and `password`). A `NULL` in `...` removes the default, as documented.
- Number formatting: RPostgres `unlist()`s the options together with `client_encoding = "utf8"`, so every value reaches libpq as text. `.frs_libpq_whole()` covers each double on that path. `port` comes from `res$params` and is converted by RPostgres's own `as.character(port)`, which is safe for any valid port.
- `connect_timeout` validation refuses NA, logical, character, Inf and fractions. Values above `.Machine$integer.max` become `NA` with a warning and then an error, not a silent unbounded wait.
- Tests: `withr` is in Imports and `mockery` is in Suggests. `fresh:::` resolves under both `load_all()` and an installed package. The silent-host test fails toward hanging, not toward passing, and its guard was proven by removing the bound.
- Public text: no new host names, IPs, ports or private references. The 63333 in `bcfp_conn()` and the roxygen example was there before this branch.
- Not reported, unverified: on Linux kernels where `TCP_USER_TIMEOUT` also governs zero-window probes, a server that stops reading its socket mid-stream for more than 120 s might drop the connection. One case is a `COPY` whose inserts wait on a lock. I have no Linux host to measure it, so it is not a finding.
