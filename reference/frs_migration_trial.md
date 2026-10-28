# Apply Database Migrations Inside a Transaction That Is Rolled Back

Applies one or more migration files to `conn` inside a single
transaction, and registers the rollback to fire when `env` exits. The
effect of a pending migration can then be measured, or tests run against
it, without migrating a database other people use.

## Usage

``` r
frs_migration_trial(conn, files, env = parent.frame())
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object. Must **not** already be in a transaction —
  [`DBI::dbBegin()`](https://dbi.r-dbi.org/reference/transactions.html)
  errors on one that is.

- files:

  Character. Paths to the migration files, applied in the order given.
  Every file is read and checked before the first one runs, so a refusal
  anywhere leaves the database untouched.

- env:

  An environment. The rollback is deferred to its exit
  ([`withr::defer()`](https://withr.r-lib.org/reference/defer.html)), so
  it fires when the calling function returns. A refusal *after* file `n`
  has run is undone by that deferred rollback, not by the refusal
  itself. The global environment is refused: there its exit is the end
  of the session, so the trial would hold its transaction — and every
  lock the migration's DDL took — open and unannounced until R quits.
  Call it from inside a function, which is also what makes the rollback
  observable.

## Value

The connection, invisibly.

## Details

fwapg's migrations carry their own `BEGIN;` and `COMMIT;`. Left in, that
`COMMIT;` would commit the trial's transaction, so the pair is stripped
and any other transaction control is refused before anything runs. The
backstop is that the session must still hold the transaction it opened,
with the same id, after each file: a migration that committed and began
again would hold another. That check **detects** a commit, after the
fact — it cannot prevent one. Preventing is the screen's job, and the
screen is what the `files` guarantee above is about.

What a rollback cannot undo is covered by neither check, so those calls
are refused too: work committed on another connection (`dblink`,
`pg_background`, a shell through `COPY ... FROM PROGRAM`), sequence
changes (`setval`, `nextval`) and files written on the server
(`lo_export`, `pg_file_write`). The scan reaches inside function bodies,
because the migration may call what it creates.

Those are **token** refusals, not measurements of what a statement would
do: a `DEFAULT nextval('s')` clause draws nothing at DDL time and is
refused anyway, while a `serial` column — identical semantics — is not
named and passes. The list errs toward refusing. Read a migration before
trying it; a refusal is a reason to look, not proof of a hazard.

Transaction control is looked for only where the server would execute
it: comments, string literals and dollar-quoted bodies are blanked
first, with line breaks kept, so a plpgsql body's own `BEGIN` / `END;` /
`END IF;` is not mistaken for the statement that would end the trial's
transaction (fwapg's `db/schema.sql` writes bare `END;` seven times). A
region that never closes — an unterminated comment, string or dollar
quote — is a refusal rather than a guess, because the scan would
otherwise be reading the wrong half of the file. `COMMIT` *inside* a
body is left to the server, which answers
`invalid transaction termination` while the trial holds an explicit
transaction block.

## See also

Other database:
[`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md),
[`frs_db_query()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_query.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# measure a pending migration's effect, then let the rollback fire
measure <- function(migrations) {
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  frs_migration_trial(conn, migrations)
  DBI::dbGetQuery(conn, "SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp")
}
measure(c("~/Projects/repo/fwapg/db/migrations/202610131654__watershedatmeasure_drop_exbc.sql",
          "~/Projects/repo/fwapg/db/migrations/202610240132__indexpoint_tiebreak.sql"))
} # }
```
