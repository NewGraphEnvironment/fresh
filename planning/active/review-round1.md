# Code check — round 1: `frs_migration_trial()` (#266 branch)

## Checklist read

- `code-check-infra.md` (38 KB) — **in full**.
- `code-check-r.md` (179 KB) — index in full, then the full text of 24 headings:
  `on.exit()` at top level; Tests that silently do not run; testthat counts an uncaught
  error under `error`; `skip_if_not()` scope; `expect_gt()` takes no `info`; `R CMD build`
  ships every top-level directory; Cross-function consistency for normalization; `$` on a
  list partial-matches; A database driver's value is not a base R type; A value compared as
  `::text`; `paste()` with a zero-length argument; `strsplit()` drops a trailing empty
  field; Under `R CMD check`, tests run against the INSTALLED package; `vapply(USE.NAMES =
  FALSE)` strips dimnames; `tryCatch(warning =)` DISCARDS the value; Do not abort inside a
  handler for a warning raised from C++; `[[` on a named ATOMIC vector; `\<`/`\>` are word
  boundaries; testthat's failure snapshots land in `tests/`; Postgres row order is never
  fixed; `sprintf("%g")` writes `Inf`/`NA` into SQL; An `information_schema` lookup by the
  literal table name; A `pkg::` call in a test fails `R CMD check` if undeclared;
  `tryCatch()` nests its handlers. Roughly 100 headings not read (terra/sf/arrow/ggplot/
  readr/climr/duckdb/paged.js/etc. — nothing this diff touches).
- `code-check-shell.md` (125 KB) — index only; **0 sections read**. The diff contains no
  shell, `sed`, `git` or `gh` invocation.
- `code-check-spatial.md` (155 KB) — index only; **0 sections read**. Scanned the index for
  DBI/Postgres: the only DB-adjacent entries are the GeoPackage-is-SQLite family and FWA
  semantics rules, none of which this diff reaches.
- `code-check.md` (330 KB) — all 14 H3 sections under `## Mechanisms` in full, plus the
  standalone rules "An assertion that matches an interpolated value cannot see the claim
  around it" and Security → "Credentials". Remaining standalone/Spreadsheet rules: index
  lines only.

All findings below were **measured**, not read off the page. Probes in
`/private/tmp/claude-501/-Users-airvine-Projects-repo-fresh/84b882b6-a966-4eb4-a354-a761ace90b2e/scratchpad/probe*.R`,
run against `R/frs_migration_trial.R` and the local docker `fresh-db`
(`imresamu/postgis:17-3.5-bullseye`, PostgreSQL 17.5).

## Findings

### 1. **[bug]** `R/frs_migration_trial.R:119` (+ roxygen `:17-19`) — `nextval` is documented as refused and is not screened

The roxygen says the trial refuses "sequence changes (`setval()`, and `nextval()` however it
is called)". The regex screens only `setval`:

```r
"(?i)\\b(dblink\\w*|pg_background\\w*|program|setval|lo_export|pg_file_write)\\b"
```

`\bsetval\b` cannot match inside `nextval` — there is no word boundary between `next` and
`val`. Measured:

```
SELECT nextval('s');          -> ALLOWED
CREATE TABLE t (id serial);   -> ALLOWED
SELECT setval('s',1);         -> REFUSED
```

Sequence advancement is the one sequence effect a rollback genuinely does not undo, so this
is the exact case the clause exists for, and the docs are the only place a caller learns the
guard's scope. A guard whose stated scope is wider than its predicate (`code-check.md`, "A
guard's scope, escape hatches, and remedies": *a rule stated in a comment is not an enforced
rule — where a comment says "never X", grep the file for X before believing it*).

Fix: add `nextval` to the alternation. Note that `serial` / `GENERATED … AS IDENTITY` DDL
reaches `nextval` implicitly and **no** word-level screen can see that, so the doc should say
what the screen actually covers rather than promising "however it is called".

### 2. **[bug]** `R/frs_migration_trial.R:107` — the three standard plpgsql terminators are refused, and the message says something false about them

`END` is in the keyword alternation, so a plpgsql `END;` matches. Measured against the
screen:

| input | result |
|---|---|
| `… AS $$\nBEGIN\n  RETURN 1;\nEND;\n$$;` | REFUSED — "controls its own transaction at line 4" |
| nested `BEGIN … END;` block inside a body | REFUSED — "… at line 5" |
| `EXCEPTION WHEN others THEN … END;` | REFUSED — "… at line 6" |

`END;` closing a function body, a nested `BEGIN … END;` block and an `EXCEPTION … END;`
handler are the ordinary way plpgsql is written, and **fwapg's own corpus uses that style**:
`~/Projects/repo/fwapg/db/schema.sql` has bare `END;` lines at 455, 768, 862, 908, 2575. The
one migration currently on disk
(`202610131654__watershedatmeasure_drop_exbc.sql`) is ALLOWED only because it happens to
write `end` with no semicolon at line 452 — one character away from being refused.

Two separate problems:

- The function cannot trial a large and common class of the migrations it exists to trial.
  Fail-closed, so nothing is corrupted — but the stated purpose is defeated, and the
  refusal arrives after a correct migration has been read.
- The message makes a **claim**, not just a name: "the migration controls its own
  transaction at line N" is false of a plpgsql `END;`, and it points the reader at a fix
  (remove the transaction control) that would break the function being created.
  `code-check.md`, "An assertion that matches an interpolated value cannot see the claim
  around it" — and `tests/testthat/test-frs_migration_trial.R:22` pins only
  `"controls its own transaction"`, so the suite asserts the predicate and is structurally
  blind to the false sentence.

The comment at `:82` says "a bare `END;` is, on purpose" — so the behaviour is deliberate;
what review surfaces is that the intent and the real corpus disagree, and that the test
fixture was written around the limitation. `test-frs_migration_trial.R:5` writes `"END"`
with no semicolon, which is why no test sees any of this
(`code-check.md`, "A fixture that cannot reach the failure mode").

If the refusal stays, the message should name a plpgsql `END;` as a possible cause and the
`@details` should say that a migration whose plpgsql bodies end `END;` is not trialable.

### 3. **[fragile]** `R/frs_migration_trial.R:63` (+ roxygen `:26-29`) — at top level the rollback is deferred to **session end**, and the transaction sits open holding every lock the DDL took

`env = parent.frame()` is `globalenv()` whenever the function is called from the console or
a script top level. `withr::defer()` on the global environment registers a session-end
finalizer, so the roxygen's "it fires when the calling function returns" is not true there —
there is no calling function. Measured (`probe4.R`): after a top-level
`frs_migration_trial(conn, f)` returned, `pg_current_xact_id_if_assigned()` still reported
the trial's xid; the backend stays `idle in transaction`. For the documented use — trialling
a migration that `CREATE OR REPLACE`s fwapg functions — that means an AccessExclusiveLock on
each target held for the rest of the R session, with no message from withr. That is the
`code-check-infra.md` "silent hangs" shape: any other session's DDL or dependent read on
those objects blocks indefinitely and looks like a slow query.

Second-order, same probe: the natural top-level sequence is
`frs_migration_trial(); …; dbDisconnect()`, and the deferred rollback then fires against a
closed handle at session end and prints

```
Error: Invalid connection
Ran 0/1 deferred expressions
```

The server rolls back on disconnect, so nothing is lost — but the only evidence the user has
about the rollback is a line saying it did not run.

Worth either refusing `globalenv()` outright (`env` is then a required argument — "Defaults
that decide"), or saying in `@param env` that a top-level call holds the transaction until
the session ends and the caller should wrap the trial in a function or `local()`.

Note the `withr::defer()` ordering **is** correct and I confirmed it: `defer` prepends
(`after = FALSE`), so the rollback runs before an `on.exit(dbDisconnect(conn))` registered
either side of it, and `local()` does create a frame the defer fires on (probes 9 and 10 in
`probe.R`).

### 4. **[fragile]** `R/frs_migration_trial.R:59-61, 68` — an empty or comment-only migration file is a silent success

`file.exists()` catches absence; nothing catches emptiness. `readLines()` on a zero-byte file
gives `character(0)`, `paste(collapse = "\n")` gives `""`, the screen returns `""`, and
`DBI::dbExecute(conn, "", immediate = TRUE)` returns without error — measured against
`fresh-db` (`probe3.R`, case A: "ok"). Same for a file that is nothing but comments.

So a truncated file, a half-written migration, or a path that resolves to the wrong (empty)
file reports a successful trial of nothing, and whatever is measured next is measured against
an unmigrated database — the "A guard that fails toward pass" shape, where the error path and
the nothing-to-do path are indistinguishable. A `nzchar(trimws(body))` check per file in the
pre-flight loop (where the refusal is still free) closes it.

### 5. **[fragile]** `R/frs_migration_trial.R:119` — `\bprogram\b` matches the English word, so an ordinary comment refuses the migration

Measured: `"-- this program loads data\nSELECT 1;"` is REFUSED as "the migration calls
program, whose effect a rollback does not undo". `COPY … PROGRAM` is the only thing meant;
anchoring to the statement (`(FROM|TO)\s+PROGRAM`) keeps the check and drops the false
refusal. Fail-closed, so the cost is a confusing refusal of a correct 1,369-line migration
rather than a bad trial. (No current fwapg migration contains the word — checked.)

## Checked and clear

Recording these because the brief asked, and because an un-recorded negative is
indistinguishable from an un-run check.

- **Refuse-before-anything-runs, multi-file.** Holds. Every file is read and screened in the
  `vapply()` at `:59-61`, which is strictly before `DBI::dbBegin()` at `:62`. `readLines()`
  errors are not caught, so an unreadable file also aborts pre-`dbBegin`. The `code[0]`
  degenerate case (`:90`) is unreachable because `length(code) > 1` short-circuits first.
- **The `pg_current_xact_id()` backstop.** Sound and fail-closed in every degenerate case:
  `pg_current_xact_id()` forces assignment, so `_if_assigned()` returns the same text while
  the transaction holds; if the transaction ended it returns NULL → `NA_character_`, and a
  0-row result gives `character(0)` — `identical()` is FALSE for both, so the function stops.
  `$x` is not a partial-match risk (single-column frame, exact name). Requires PG 13+;
  on an older server the call errors after `dbBegin()`, which the deferred rollback covers.
- **Does the PCRE grammar let a real `COMMIT` through?** I could not construct one. Top-level
  statements are `;`-separated, so a transaction-ending command is always preceded by a
  literal `;` or input start, which `(^|;)` matches unconditionally; only whitespace and
  comments can intervene, and `ws` covers both (including `\r`). All of
  COMMIT/END/ROLLBACK/ABORT/PREPARE TRANSACTION with every option spelling I tried are
  caught. Consumption cannot hide a second one, because any match at all is a refusal.
  `START TRANSACTION ISOLATION LEVEL SERIALIZABLE, READ ONLY;` **is** missed (the option list
  is comma-separated and `opt` requires whitespace between options) — harmless, since
  `BEGIN`/`START TRANSACTION` inside an open transaction is a warning and a no-op.
  `ROLLBACK TO SAVEPOINT x;` is also missed, and is likewise safe.
- **`COMMIT` inside a plpgsql body or a DO/CALL block.** The one-line forms
  `DO $$ BEGIN COMMIT; END $$;` and `CREATE PROCEDURE … $$ BEGIN COMMIT; END $$; CALL p();`
  do escape the regex (the keyword is preceded by neither `;` nor a line start). **Not
  exploitable**: PostgreSQL rejects transaction control inside a DO/CALL when an explicit
  transaction block is already open, which the trial always has. Measured — the server
  answered `ERROR: invalid transaction termination`, and a second connection confirmed the
  table was not committed. Multi-line DO bodies are caught by `(?m)^` anyway.
- **Dollar-quoted strings, `E''` escapes, `;` inside string literals.** All produce false
  refusals, never false passes (measured: `$tag$a;\nCOMMIT;$tag$;`,
  `E'x\';\nCOMMIT;'`, `'a;\nCOMMIT;'` — all REFUSED). Fail-closed, consistent with the
  function's stated bias.
- **Warning handling.** `withCallingHandlers()` + record-flag + `invokeRestart` + raise after
  the call returns is exactly the remedy `code-check-r.md` prescribes ("Do not abort inside a
  handler for a warning raised from C++"), and treating the warning as a refusal is the
  correct direction for a `gregexpr()` that gives up. The second screen (`:119`) is
  unprotected, but its pattern has no backtracking exposure.
- **Second trial on the same connection.** `DBI::dbBegin()` errors on a connection already in
  a transaction, and it errors *before* the second `withr::defer()` registers, so there is no
  double rollback.
- **`local_fwapg()` hardcoded credentials** (`tests/testthat/helper-db.R:38-47`). Judged **not
  a problem**. `postgres/postgres` on `localhost:5432/fwapg` is the published default of this
  repo's own container (`docker/README.md`, `docker/load.sh:142`), not a secret, and the
  shared instance is reached on port **63333** per `docker/README.md:93` — so the default
  cannot land on it by accident. `FRESH_PG*` overrides are available for any other target.
- **Does the test suite leak tables into `public.`?** No. Every `CREATE TABLE` is inside the
  trial transaction; the deferred rollback fires at the end of the `local()` / `test_that()`
  frame, and if the process is killed first the connection drops and the server rolls back.
  Names are randomised, so a stuck table could not collide either.
- **DESCRIPTION / declared dependencies.** `withr` moved Suggests → Imports is correct —
  `R/frs_migration_trial.R:63` is runtime use. Tests reach `withr::local_tempfile()` and
  `fresh:::`, both now declared, so the `R CMD check` "'::' import not declared" trap does
  not fire.
- **lintr.** No line over the repo's 120-char limit in any of the three changed files.
