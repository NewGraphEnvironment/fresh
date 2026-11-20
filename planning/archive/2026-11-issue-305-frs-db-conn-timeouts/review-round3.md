# Code-check round 3 (#305): branch vs origin/main 98e7cf0

## Checklist read

- code-check-infra.md: in full.
- code-check.md: every H3 under `## Mechanisms`, prose only, table rows skipped (all 14). None of the 17 headings under "Rules that stand alone", "Security" or "Spreadsheets and PDFs" read in full; their index lines name nothing this diff uses.
- code-check-r.md: read in full: "Tests that silently do not run", "testthat counts an uncaught error under `error`, not `failed`", "`expect_gt()` and friends take no `info` argument", "`$` on a list partial-matches…", "A database driver's value is not a base R type…", "A value compared as `::text`…", "`nzchar(NA)` is TRUE…", "Under `R CMD check`, tests run from a temp dir…", "`expect_message(expr, regexp)` checks only the FIRST condition…", "`as.integer(\"NaN\")` is `0`…", "`[[` on a named ATOMIC vector…", "`sprintf(\"%g\", x)` writes `Inf`…", "Verify a float-formatting fix in its consumer…", "A `pkg::` call in a test…", "A `function(...)` mock hides arguments…" (15). Not read: the other ~175 headings, whose index lines name no tool or shape in this diff.
- code-check-shell.md: 0 headings read in full. The diff has no shell.
- code-check-spatial.md: 0 headings read in full. The diff has no spatial code.

## Mechanism

Both earlier findings come from one assumption: **if a value passes R's checks, libpq reads it the way fresh means it.** fresh validates in R: R types, numeric ranges, and a keyword list it chose itself. But libpq judges the value as text, at whatever libpq version is linked. It wants a keyword in that version's table and an integer that `strtol` reads within C `int` range. Between the two sits a lossy chain: `as.integer()` in fresh, then RPostgres's `unlist(list(..., client_encoding = "utf8", ...))`, which coerces every value with `as.character()`. NA becomes the text `"NA"`, a whole double from 1e5 up can become `"1e+05"`, and a vector gets suffixed keyword names. The two sides agree on small integers and a modern libpq. They part at the edges. `tcp_user_timeout` is a keyword in libpq 12 and later, not before. `connect_timeout` above INT_MAX was a valid number in R and became NA after `as.integer()`.

Every value fresh hands to libpq, checked against libpq's text rules. Measured: RPostgres 1.4.10, linked libpq 16.8 (`client_version()` 160008), R `unlist` coercion run directly.

1. **`frs_db_conn()`: `res$params` (dbname, host, port, user, password).** These predate this branch and do not pass through `.frs_libpq_whole()`. The only numeric one is `port`. RPostgres applies `as.character(port)`, and no whole double from 0 to 65535 prints in e-notation (counted: 0 of 65,536). The first that does is 1e5. **Sound.**
2. **`frs_db_conn(connect_timeout = n)`.** The check accepts a whole number from 0 to `.Machine$integer.max`, and the value is then made integer. libpq's `parse_int_param` accepts exactly the C `int` range. The check refuses non-numeric, logical, `difftime` (`is.numeric()` FALSE), NA and Inf. `bit64::integer64` passes and converts correctly. **Sound.**
3. **Default `connect_timeout = 10L`** (when `PGCONNECT_TIMEOUT` is empty or unset). The text is `"10"`. **Sound.**
4. **`PGCONNECT_TIMEOUT` set, nothing passed.** libpq reads and parses the variable itself, as it did before this branch. **Sound.**
5. **Keepalive defaults 1/60/10/6** (integers). The text is `"1"`, `"60"`, `"10"`, `"6"`. libpq has known all four keywords since 9.0, so a system libpq on Linux has them. **Sound.** Dropping `tcp_user_timeout` closed the version-dependent keyword, and no other default depends on the libpq version.
6. **Values in `...` (`frs_db_conn()` and the helpers' `.frs_conn_bounds()`).**
   - A whole double becomes an integer up to INT_MAX, else fixed-notation text, which libpq refuses loudly for every integer keyword.
   - `integer64` goes through bit64's methods to an integer (probed: 90 became `90L`).
   - NA reaches libpq as `"NA"`: probed, it gives `invalid integer value "NA"` for `keepalives_idle`.
   - Logical becomes `"TRUE"` (refused), a vector of length > 1 becomes suffixed keyword names (refused), and a fraction becomes `"60.5"` (refused).
   - Only a text keyword can take NA silently (`application_name = NA` becomes `"NA"`), and only when the caller wrote NA. That is the accepted tradeoff.
   - `-0` becomes `0L`.
   - Partial matching: no libpq keyword is a prefix of a formal of `frs_db_conn()` or RPostgres's `dbConnect`.
   - **Sound.**
7. **`.frs_conn_params()` for `frs_habitat()` workers.** dbname, host, port and user are text from `dbGetInfo()`, and the password is given. The bounds are the integers from item 5. A parent `PGCONNECT_TIMEOUT` goes as its raw string, so libpq parses the same text it would have read from the environment, surrounding whitespace included. A set-but-empty variable falls to the explicit 10, which overrides the environment. The workers pass the list through `do.call(DBI::dbConnect, c(list(drv = ...), conn_params))`, so every bound reaches them (`R/frs_habitat.R:395` and `:581`). **Sound.**
8. **`frs_fwapg_conn()` (`helper-db.R`).** `port = as.integer(Sys.getenv("FRESH_PGPORT", "5432"))` predates this branch: a non-numeric value becomes NA, then `"NA"`, which libpq refuses loudly. The bounds are as in item 5, and under `PGCONNECT_TIMEOUT` libpq reads the variable, which is harmless. **Sound.**
9. **`bcfp_conn()` (`test-frs_network_features-live.R`).** `port = 63333` (double) becomes `"63333"`. The bounds are as in item 5. **Sound.**
10. **Every other caller of `frs_db_conn()`** (`skip_if_no_schema()`, `skip_if_no_conn()`'s default, vignettes) goes through items 1 to 6. No caller passes a sixth positional argument, so adding `connect_timeout` before `...` breaks no call (checked by grep). **Sound.**

Other checks:
- The mock stub `function(drv, ...) list(...)` is safe: the real `dbConnect` method also takes `...`.
- `mockery` and `withr` are declared.
- `test-frs_db_conn.R` gave 18 blocks, 0 failed, 0 errors, 0 skipped, in a detached worktree with `NOT_CRAN=true`.
- Public-repo text: the diff adds no host, IP, port or private reference. `localhost:63333`, `db_newgraph` and the `"newgraph"` default user were all there before this branch.

## Clean

No issues found in the diff.

### Outside the diff (predates this branch, not a finding)

`frs_fwapg_conn()` passes `host` but not `hostaddr`. libpq fills a missing `hostaddr` from `PGHOSTADDR`, and `hostaddr` decides where it connects. Probed: with `PGHOSTADDR=127.0.0.1`, `host = "nonexistent.invalid"` connected. So a `PGHOSTADDR` in `.Renviron` sends this connection wherever that variable points. `PGSERVICE` does the same if its entry defines `hostaddr`, and the helper's comment says it must not reach that instance. In practice this is unlikely to cause harm: the explicit port (5432) and the `postgres`/`postgres` credentials still apply, so a shared host would probably refuse it. The issue predates this branch. Recorded here so the decision is the owner's.
