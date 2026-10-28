# Review round 3 — #266

## Checklist read

- `code-check-infra.md` (38,115 B) — read in full.
- `code-check.md` — read the prose of all 14 H3s under `## Mechanisms`, plus the
  `## Rules that stand alone` and `## Security` index lines.
- `code-check-r.md` — read in full the sections for: `on.exit()` at a script's top
  level; a `data-raw/` script must load the source tree; `lintr` resolves against the
  installed package; testthat counts an uncaught error under `error`; `skip_if_not()`
  skips only its own block; `R CMD build` ships every top-level directory; under
  `R CMD check` tests run against the installed package; base-name shadowing in formal
  args; **a database driver's value is not a base R type**; a value compared as `::text`;
  `nzchar(NA)`; `paste()` with a zero-length argument; `strsplit()` drops a trailing
  empty field; `expect_false(identical())`; **Postgres row order is never fixed**;
  `sprintf("%g")` writes `Inf`/`NA` as bare words; `information_schema` lookup by literal
  name; Rscript reads a script as it runs; `tryCatch(warning =)` discards the value;
  `match()` treats NA as a value; a `pkg::` call in a test; `ifelse()` with an all-NA test.
- `code-check-shell.md`, `code-check-spatial.md` — index lines; no section in either
  names a tool or shape this diff uses (no shell, no sf/terra/GDAL call changed).

Everything in the ACCEPTED TRADEOFFS list was left alone.

---

## Mechanism and enumeration

### The mechanism

Confirmed as stated in the brief, with one refinement that makes it enumerable.

`.frs_sql_blank()` is a hand-written reimplementation of PostgreSQL's scanner, so its
correctness is the claim *"my token classes equal PostgreSQL's token classes."* Round 2's
bug was one missing class (`"..."`). But the two defects found *inside* round 2's fixes
were not missing classes — they were **character classes inside a class that is narrower
than PostgreSQL's**. That is the sharper statement, and it is where the remaining gap is:

> Every place the lexer decides *"is this character part of an identifier?"* uses
> `[A-Za-z0-9_]`. PostgreSQL's scanner uses `ident_start [A-Za-z\200-\377_]` and
> `ident_cont [A-Za-z\200-\377_0-9$]` — **every byte ≥ 0x80 is a letter, and `$`
> continues an identifier.** The two lists look like they agree because every file
> anyone has fed the lexer is ASCII.

Three sites read that class, and all three are the same `[A-Za-z0-9_]`:

| site | `R/frs_migration_trial.R` | what it decides |
|---|---|---|
| `ident()` | :211 | whether a `$` opens a dollar quote (:293) |
| `ident()` | :211 | whether a leading `E` makes `'…'` a backslash-escape string (:267) |
| the tag scan | :297 | which characters may appear in a dollar-quote tag |

A class *narrower* than PostgreSQL's cuts both ways, and only one way is safe:

- Narrower **tag** class → a `$tág$` body is not recognised, so its contents are read as
  top-level code. Reading *more* as code can only add refusals — **fail-closed** — unless
  a `'` in the body re-pairs the quotes and blanks real SQL beyond it.
- Narrower **preceding-character** class → `té$a$` looks to fresh like an identifier
  followed by a dollar quote, while PostgreSQL's longest match makes it **one identifier**.
  fresh then blanks a region PostgreSQL executes — **fail-open**.

### Why most of the unhandled set is fail-closed: PostgreSQL's whole-string raw parse

Measured on the local docker fwapg:

```
CREATE TABLE public.frs_r3_probe (x int); \echo oops
-> ERROR: syntax error at or near "\"
   table created despite the later syntax error?  FALSE
```

`exec_simple_query()` raw-parses the entire multi-statement string before executing any
of it, so **any** construct the lexer mishandles in a way that yields invalid SQL executes
nothing at all. That is the backstop that makes "psql meta-command", "`COPY FROM stdin`
inline data", "`$1$`", "last character is `-` / `/` / `$`" all fail-closed rather than
partially-applied.

### The enumeration

Every lexical construct PostgreSQL's scanner recognises at the top level of a SQL file
that can contain a character which, taken literally, moves where the lexer thinks code is
(`'`, `"`, `-`, `/`, `*`, `$`). Derived from
`https://www.postgresql.org/docs/current/sql-syntax-lexical.html` §4.1.1–§4.1.5 and
`src/backend/parser/scan.l`'s token list (`xb`, `xh`, `xq`, `xe`, `xdolq`, `xui`, `xuiend`,
`xus`, `xusend`, `xc`, `xd`, `{param}`, `{operator}`, `{identifier}`).

Every row below was **constructed and run** through `fresh:::.frs_migration_trial_sql()`;
where the screen passed, the body it returned was handed to `DBI::dbExecute(immediate =
TRUE)` inside an explicit transaction whose id was forced with `pg_current_xact_id()`, and
`pg_current_xact_id_if_assigned()` was read afterwards. "FAIL-OPEN" means the screen
passed it, the server ran it without error, and the trial's transaction was gone.
Harness: `.../scratchpad/lex_enum3.R`, `.../scratchpad/h2.R`.

| # | construct | handled? | screen | server | direction |
|---|---|---|---|---|---|
| A1 | `'…'` plain | yes, blanked | PASS | ran, txn intact | ok |
| A2 | `''` escape over a `COMMIT` | yes | PASS | ran, txn intact | ok |
| A3 | `COMMIT` inside a string | yes | PASS | ran, txn intact | ok |
| B1 | `E'a\'; COMMIT; --'` | yes (:267) | PASS | ran, txn intact | ok |
| B2 | `e'…'` lowercase | yes | PASS | ran, txn intact | ok |
| B3 | `aE'…'` (ASCII ident before `E`) | yes — not an E-string | REFUSE | — | fail-closed |
| B4 | `téE'…'` (**non-ASCII** ident before `E`) | **NO** (`ident()` too narrow) | PASS | server refused, nothing ran | fail-closed *here* — see note | 
| C1 | `B'1001'` bit string | yes (plain `'…'` is correct) | PASS | ran, txn intact | ok |
| C2 | `X'1f'` hex string | yes | PASS | ran, txn intact | ok |
| D1 | `U&'\0441'` | yes (`''` is still the quote escape) | PASS | ran, txn intact | ok |
| D2 | `U&'…' UESCAPE '!'` | yes (the escape string is a plain literal) | PASS | ran, txn intact | ok |
| D3 | `U&"\0441"` ident | yes (plain `"…"` is correct) | PASS | ran, txn intact | ok |
| D4 | `U&"x--y"; COMMIT;` | yes | REFUSE | — | fail-closed |
| E1 | adjacent literals across a newline | yes, each blanked | PASS | ran, txn intact | ok |
| E2 | 2nd half of a continued literal holds a `COMMIT` | yes | PASS | ran, txn intact | ok |
| F1 | `"x--y"; COMMIT;` | yes (round 2) | REFUSE | — | fail-closed |
| F2 | `"a""--b"` escape | yes | REFUSE | — | fail-closed |
| F3 | `"a's"` | yes | PASS | ran, txn intact | ok |
| G1 | `$$…$$` empty tag | yes | PASS | ran, txn intact | ok |
| G2 | `$b$…$b$` | yes | PASS | ran, txn intact | ok |
| G3 | `$_$…$_$` underscore tag | yes | PASS | ran, txn intact | ok |
| G4 | nested `$a$…$b$x$b$…$a$` | yes (first close of the *outer* tag) | PASS | ran, txn intact | ok |
| G5 | `$1$` digit-leading tag (not a tag) | yes (:301 guard) | PASS | server refused, nothing ran | fail-closed |
| G6 | **non-ASCII tag** `$tág$`, body has `'it''s'`, `COMMIT;` after | **NO** (tag scan too narrow) | REFUSE | — | fail-closed |
| G6b | non-ASCII tag, one `'a'` in body, `COMMIT;` after | **NO** | REFUSE | — | fail-closed |
| G7 | non-ASCII tag, plain body | **NO** | REFUSE | — | fail-closed |
| H1 | `ta$a$` — ASCII ident char before `$tag$` | yes — not a dollar quote | REFUSE | — | fail-closed |
| H2 | `té$a$` — **non-ASCII** ident char before `$tag$` | **NO** | **PASS** | **ran clean, xid gone** | **FAIL-OPEN** |
| I1 | `--` to newline | yes | PASS | ran, txn intact | ok |
| I2 | `--` ended by a lone `\r` | yes (:217 stops at `\n` **or** `\r`, as PG's `non_newline`) | REFUSE | — | fail-closed |
| I3 | `--` at end of input | yes | PASS | ran, txn intact | ok |
| J1 | nested `/* a /* COMMIT; */ b */` | yes (depth counter) | PASS | ran, txn intact | ok |
| J2 | unterminated `/*` | yes, refusal | REFUSE | — | fail-closed |
| J3 | `/*/` (unterminated in PG too) | yes, refusal | REFUSE | — | fail-closed |
| K1–K8 | `@-@`, `?-`, `#-#`, `|/`, `||/`, `!~*`, `->>`, `#>>` | yes — operator chars are ordinary; none can hide code | PASS | ran (K3 refused on operator resolution) | ok |
| K9 | `@--@` — PG truncates the operator at `--` | yes, same rule | PASS | server refused, nothing ran | fail-closed |
| K10 | `2*/* c */1` — `/*` always wins | yes, same rule | PASS | ran, txn intact | ok |
| K11 | `-|-` range adjacency | yes | PASS | ran, txn intact | ok |
| L1 | `$` inside an identifier (`a$b`) | yes (:293 prev-char guard) | PASS | ran, txn intact | ok |
| L2 | `$1` positional parameter in a body | yes | PASS | ran, txn intact | ok |
| M1 | `COPY … FROM stdin;` + inline data + `\.` | no (not a server-lexer construct) | PASS | server refused, nothing ran | fail-closed |
| N1 | psql `\echo` | no (psql, not the server) | PASS | server refused, nothing ran | fail-closed |
| N2 | psql `\i` | no | PASS | server refused, nothing ran | fail-closed |
| O1 | UTF-8 BOM before `BEGIN;` | the own-pair strip misses it, the txn scan catches it | REFUSE | — | fail-closed |
| O2 | CRLF endings | yes (`\r` is `\s` in the own-pair regex; `readLines()` strips it anyway) | PASS | ran, txn intact | ok |
| O3 | lone-CR endings | one giant "line", pair not stripped | REFUSE | — | fail-closed |
| O4 | non-ASCII in a plain identifier (`café`) | yes (no `$` or quote follows) | PASS | ran, txn intact | ok |
| O5 | last char `'` | refusal | REFUSE | — | fail-closed |
| O6 | last char `$` | `j <= n` guard; `$` left ordinary | PASS | server refused, nothing ran | fail-closed |
| O7 | last char `-` | `c2 = ""` at `i == n` | PASS | server refused, nothing ran | fail-closed |
| O8 | last char `/` | `c2 = ""` at `i == n` | PASS | server refused, nothing ran | fail-closed |
| O9 | empty input | "no statements" refusal | REFUSE | — | fail-closed |
| O10 | first char `'` | handled at `i == 1` | REFUSE | — | fail-closed |
| O11 | first char `$` | handled at `i == 1` | REFUSE | — | fail-closed |
| P | both real fwapg migrations (35 KB + 49 KB) | — | PASS, and apply + roll back as one transaction (84 tests green with `FRESH_FWAPG_TRIAL` set) | — | ok |

**Note on B4 / G6 / G7 (same root cause as H2, measured fail-closed).** Reading a region
as code instead of as a string cannot hide anything by itself; it can only hide something
if a `'` inside the misread region re-pairs the file's quotes so that a later real
`COMMIT` lands *inside* a fresh-invented string. That shift is always **+1 quote**, and
valid SQL has an even number of top-level quotes — so the shift leaves a trailing
unterminated string, which is a refusal. I tried five constructions of B4/G6 to defeat the
parity (adding literals, a `"a's"` quoted identifier to contribute an odd quote, a `\\`
instead of `\'`); every one cascaded into an "unterminated region" refusal. The only way to
restore parity is a *second* misread in the same file, or a typed-literal position
(`sometype 'value'`) where `téE'…'` is grammatical. I did not find a working instance.
H2 fails open because the misread region is a dollar quote for which fresh *does* find a
proper close, so there is no parity cascade at all.

### Terminal result

The set above is the whole set, and **one member sits above its source of truth**: the
`[A-Za-z0-9_]` identifier class at `R/frs_migration_trial.R:211` and `:297`, against
PostgreSQL's `[A-Za-z\200-\377_0-9$]`. Everything else is either handled, or unhandled in
the fail-closed direction with the whole-string raw parse as the backstop. Reported as
finding 1 below.

---

## Findings

- **[severity: bug]** `R/frs_migration_trial.R:211` (and `:297`) — `ident()` is
  `[A-Za-z0-9_]`, but PostgreSQL's identifier-continuation class is
  `[A-Za-z\200-\377_0-9$]`: every byte ≥ 0x80 is a letter, and `$` continues an
  identifier. So where PostgreSQL reads `té$a$` as a **single identifier**, the `$` branch
  at `:293` sees a non-identifier predecessor, opens a dollar quote, finds its close, and
  blanks everything between — including a top-level `COMMIT`. Measured through the
  exported function on the local docker fwapg:

  ```
  CREATE TABLE public.té$a$ (x integer);
  CREATE TABLE public.frs_r3_victim (x integer);
  COMMIT;
  SELECT 1 AS té$a$;
  ```
  ```
  screen verdict:  PASS (the screen let it through)
  trial error: ... the session no longer holds transaction 716416, so the migration
               may have been committed: check the database
  AFTER the deferred rollback, on a fresh connection, frs_r3_victim exists: TRUE
  AFTER, te-dollar table exists: TRUE
  ```

  Both tables were **committed** and survived the deferred rollback; a second connection
  could see them. This is precisely the failure the screen exists to prevent, and the
  roxygen at `:13` states the xid check "**detects** a commit, after the fact — it cannot
  prevent one. Preventing is the screen's job." The backstop did fire loudly, which is the
  mitigation, and the exploit needs a non-ASCII letter immediately before a `$tag$` — not
  something fwapg's ASCII migrations contain. But the screen is the guarantee the `files`
  parameter documents, and here it is wrong rather than conservative.

  Fix is one character class in two places, matching PostgreSQL's:
  `ident <- function(x) grepl("^[A-Za-z0-9_$]$", x) || grepl("^[^\\x01-\\x7f]$", x, perl = TRUE)`
  for `:211`, and the same high-bit range added to the tag scan at `:297` (PostgreSQL's
  `dolq_start`/`dolq_cont` include `\200-\377`). Widening the tag scan also turns G6/G7
  from false refusals into correct handling. Pin it with H2 as a regression test — it is
  the one input in the enumeration that goes from FAIL-OPEN to refused.

- **[severity: bug]** `data-raw/point_snap_tie_sweep.R:367-371` (`answers()`), consumed at
  `:427`, `:466-467` and `:493` — `out <- rep(NA, nrow(d))` is a **logical** vector, and
  `out[got$rows$ord] <- got$rows[[answer]]` assigns an `integer64` into it for the
  `fwa_downstreamtrace` column. RPostgres defaults to `bigint = "integer64"`, so
  `count(w.linear_feature_id) AS n` arrives as `integer64` — a double carrying the int64
  bit pattern. `[<-` on a logical target coerces the target to double and copies the raw
  doubles, dropping the class, so every non-zero trace length becomes a denormal.
  Measured on the sweep's exact query shape (`LEFT JOIN LATERAL` + `count()` +
  `GROUP BY v.ord`), with ordinal 4 left NA to stand for an errored position:

  ```
  DB answer  : ord 1 -> 0,  ord 2 -> 3,  ord 3 -> 12      class(n): integer64
  answers()  : 0.000000e+00 | 1.482197e-323 | 5.928788e-323 | NA     class: numeric
  as.character (what sweep_changed.csv's was/now hold):
               0 | 1.48219693752374e-323 | 5.92878775009496e-323 | NA
  ```

  `trace_empty` and `trace_error` survive by accident (`as.integer64(0)`'s bit pattern is
  `+0.0`, and a non-zero count is a non-zero denormal), and `moved_between()`'s `a != b`
  still *detects* a change because distinct int64s have distinct bit patterns. What is lost
  is the evidence: `sweep_changed.csv`'s `was` / `now` columns for `fwa_downstreamtrace`
  hold denormal doubles instead of trace lengths, so a reader cannot tell a trace that
  went 12 → 0 from one that went 12 → 13 — and that attribution is what the file is for.
  The report is also the artifact the issue is written from, so the wrong number outlives
  the run (`code-check.md`, "Written data outlives the fix"); `code-check-r.md`,
  "A database driver's value is not a base R type — and it fails twice" is the class.
  Fix: `out <- rep(NA_real_, nrow(d))` and `as.numeric(got$rows[[answer]])` (or
  `SELECT count(...)::int`). The `hit` boolean columns are unaffected — verified.

- **[severity: fragile]** `data-raw/point_snap_tie_sweep.R:513` and `:528` — the script
  header claims "A second run must be byte-identical in the body", and `:567` repeats it
  ("a second run must be byte-identical from here"). Both the body's `moved` table
  (`moved[order(moved$state, moved$call, …, moved$src, moved$id), ]`, printed at `:593`)
  and the `base_md5` fingerprint (`sort(…)` at `:528`) order **character** vectors with
  `order()` / `sort()`, which collate by `LC_COLLATE`. Measured here:

  ```
  C      : A_b a_B a_b crossings_10 crossings_2
  default: a_b a_B A_b crossings_10 crossings_2     (LC_COLLATE = en_US.UTF-8)
  ```

  So the same data produces a different body and a different fingerprint on a host or
  session with a different locale, and the comparison the fingerprint exists for silently
  reports a difference that is not in the data (`code-check-r.md`, "`sort()` and `order()`
  collate by `LC_COLLATE`, so a canonical form is locale-dependent"). `method = "radix"`
  on both calls pins it.

- **[severity: fragile]** `data-raw/point_snap_tie_sweep.R:548-549` — the provenance line
  is `sprintf("fresh: %s (%s)", <version>, system("git rev-parse --short HEAD", intern =
  TRUE))`. With `intern = TRUE`, a failing `git` warns and returns `character(0)`; measured,
  `length(sprintf("a %s b", character(0)))` is **0**, so the whole element evaluates to
  `character(0)` and `c()` drops it — the report loses its commit stamp with no error and
  no gap in the file. That is the provenance half of `code-check.md`, "A guard that fails
  toward pass" ("capture a provenance stamp … and write the captured value"): a report
  whose fingerprint line is simply absent reads as an older format rather than as a failed
  capture. Assign first and check: `sha <- system(…, intern = TRUE); stopifnot(length(sha)
  == 1L)`.

- **[severity: fragile]** `data-raw/point_snap_tie_sweep.R:539` — `vapply(strsplit(s$errors,
  "\t", fixed = TRUE), function(x) x[[4]], "")` takes the message as the 4th tab field of
  a record built by `sprintf("%s\t%s\t%s\t%s", …)` at `:345`. Two ways that misreads:
  `strsplit()` drops a **trailing** empty field, so an empty `conditionMessage()` yields
  three fields and `x[[4]]` raises *subscript out of bounds*; and a message containing a
  tab splits into five, so `x[[4]]` is a truncated prefix. Both land at `:589`, i.e. after
  the ~10-minute sweep has finished but **before** `writeLines()` at `:609` — the raise
  loses the whole run's report. (`code-check-r.md`, "`strsplit()` drops a trailing empty
  field".) Cheap fix: build `errs` as a list of records, or split with `n`-field padding
  and read the message as `paste(x[4:length(x)], collapse = "\t")` with a `length(x) >= 4`
  guard.

---

## Checked and clean (so the next round need not redo it)

**`frs_point_snap()` / `.frs_point_snap_sql()`**

- Generated SQL printed for `num_features = 1` and `5`. `c AS (SELECT p.id, s.*)` exposes
  `measure_raw`; the outer `SELECT` enumerates its columns and omits it, so the alias
  cannot reach a caller, and the lateral enumerates its columns too, so a user network
  table carrying its own `measure_raw` cannot collide. All three ordering sites carry
  `distance_to_stream, measure_raw DESC, linear_feature_id`, and each ends on
  `linear_feature_id`, which is unique within a point's candidate set — `code-check-r.md`,
  "Postgres row order is never fixed", satisfied at all three.
- `tests/testthat/test-frs_point_snap.R`: 172 pass, 0 skip against the local docker fwapg,
  including the three live tie tests and the EXPLAIN shape test, so `skip_unless_tied()`
  and `skip_unless_both_in_five()` are **not** vacuous on this host (`code-check.md`,
  "Make vacuity visible").

**`frs_migration_trial()`**

- Transaction-control regex: `SAVEPOINT` / `RELEASE SAVEPOINT` are deliberately not in the
  keyword list and cannot end the outer transaction — checked; `ROLLBACK TO SAVEPOINT`
  *is* matched (a conservative false refusal, consistent with the stated token-refusal
  tradeoff). A top-level `CASE … END;` is not matched, because the `END` is not preceded by
  `;` — checked.
- `withr::defer()` ordering in the `sweep_state()` shape: `defer` has `priority = "first"`,
  so the rollback runs **before** the `on.exit()` disconnect registered ahead of it —
  verified by running the shape.
- `SET LOCAL lock_timeout` is issued inside the transaction and before the xid capture
  (`:100` then `:101`), and `SAVEPOINT` / `RELEASE SAVEPOINT` / `ROLLBACK TO SAVEPOINT` all
  work through `DBI::dbExecute()` — verified. `RELEASE` correctly fails in an aborted
  transaction, and the script only calls it on the success path.
- Both real migrations pass the screen and apply as one transaction; 84 tests green with
  `FRESH_FWAPG_TRIAL` set. Full suite: `FAIL 0 | WARN 3 | SKIP 3 | PASS 1965`.
- `withr` Suggests → Imports: used namespace-qualified in `R/frs_migration_trial.R:95`
  only, so no `importFrom` is needed and no `R CMD check` "not imported from" NOTE.

**Sweep script, the items the brief named**

- **`on.exit()` at a script top level.** The claim at `:140` is right, and the cited
  reference `data-raw/point_snap_parity_check.R:46-49` resolves to the same comment and
  `drop_all()` call. The script does **not** depend on it: both `on.exit()` calls are
  inside functions (`sweep_state()` `:375`, `md5_of()` `:524`), and the scratch tables are
  dropped explicitly at `:144` and `:615`.
- **Ordinal join-back is order-independent.** `vals` is built over `seq_len(nrow(d))`, so
  `ord` is the *global* row index and stays global through `vals[at]` and through the
  row-by-row `ask(vals[[j]])`; `answers()` indexes `out[got$rows$ord]` directly. The
  `order(rows$ord)` at `:361` is redundant, not load-bearing.
- **Savepoints on an aborted transaction.** `ROLLBACK TO SAVEPOINT` is one of the few
  commands PostgreSQL allows in an aborted transaction — measured ok; `RELEASE` is not —
  measured to fail — and is only reached on the success path. The `"current transaction is
  aborted"` guard at `:353` fires after at most one chunk's worth of rows, which is the
  documented behaviour.
- **The drift guard does not fail toward pass, and is not decoration.** Every `one()` query
  is a `count(*)` that cannot return NULL, a missing relation raises, and `any(drift != 0)`
  aborts. Measured against the local docker fwapg: all seven figures match
  `research/fwa_point_snap.md` exactly, drift 0 — so the guard is live on the host the
  script is meant to run on, rather than always-firing or always-silent.
- **The `moved` comparison does distinguish NA from FALSE.**
  `xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & a != b)` flags value→NA and
  NA→value, leaves NA→NA alone, and the summary table counts `*_miss` (with `na.rm`) and
  `*_error` separately — three outcomes preserved, as the comment claims.
- **The final drop runs on a live connection.** `drop_all()` closes over the global `conn`
  by lexical scope, and `:614` reassigns `conn <- fwapg_conn()` on the line before
  `drop_all()` at `:615`, so the `dbDisconnect()` at `:304` is not the connection it uses.
- **`sprintf`-interpolated numerics do not produce malformed SQL.** `format(…, scientific =
  FALSE)` over the real `crossings.csv` (533,291 rows, `max(m) = 1,933,382`,
  `max(blue_line_key) = 380,887,829`): every `blue_line_key` round-trips exactly, and
  although 298,179 measures do not round-trip bit-for-bit, the **worst absolute drift is
  2.3e-10 m** — `format()` on a vector picks the decimal count the widest element needs,
  not `getOption("digits")`, so there is no scientific notation and no material loss.
  `format()`'s left-pad does put leading spaces inside the `VALUES` tuple
  (`(2,360717957,    321.12369915930)`), which is legal whitespace. No `Inf`/`NA` can reach
  it (`csv_measures()` filters NA at `:259`), so `code-check-r.md`'s `sprintf("%g")` trap
  does not apply.
- **Three-state frames line up row-for-row.** Each state re-reads `positions` ordered by
  `(src, id, candidate_rank)`, `measures` by `(src, id)` and `expensive` by
  `(blue_line_key, m)`; all three keys are unique in their tables (`expensive` is a
  `UNION`, so `(blk, m)` is distinct), and `moved_between()`'s `stopifnot(length(a) ==
  length(b))` is a real premise rather than decoration.
- **Not flagged, noted:** `chunked()` with a zero-row frame computes `seq.int(1, 0)` =
  `1:0`, a descending index into a length-0 `vals`, and would build `(1,NA,NA)`. All three
  frames are non-empty with real data, and the drift guard aborts before that on an empty
  database, so it is unreachable rather than a defect.
- `lintr` on all six changed files: only `indentation_linter`, `brace_linter` and the
  known `object_usage_linter`-against-the-installed-package artifact — all accepted
  tradeoffs.

**Incidental observation (not a finding)**

All eight `working.tie266_*` scratch tables are currently present on the local docker
fwapg. I never ran the sweep script, so they are residue from an earlier run that did not
reach its final `drop_all()` at `:615`. That is the case the drop-at-the-start at `:144`
exists for, so the design holds — but it does mean the abort path is live, and a reader
who finds those tables should not take them as a completed run's output. Nothing I ran
left anything behind: the `frs_r3_victim`, `public."té$a$"` and `frs_r3_probe` tables my
fail-open probe committed were dropped, and `pg_tables` / `pg_proc` confirm no residue.
