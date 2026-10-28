# Code check — round 2 (#266 phase 1+2)

## Checklist read

- `code-check-infra.md` (38 KB) — **in full**.
- `code-check-r.md` — read the full text of 40 of 112 H3 sections, selected by the
  shapes this diff uses: `on.exit()` at top level; Tests that silently do not run;
  testthat counts an uncaught error under `error`; A `skip_if_not()` skips only its
  own block; `expect_gt()` takes no `info`; `R CMD build` ships every top-level
  directory; `.Rbuildignore` has no comment syntax; Base name shadowing; Cross-function
  consistency; `$` partial-matches; A database driver's value is not a base R type;
  A value compared as `::text`; Inserting a helper between a roxygen block and its
  function; `nzchar(NA)`; `paste()` with a zero-length argument; `strsplit()` drops a
  trailing empty field; `identical()` on two reader results; Under `R CMD check` tests
  run from a temp dir; A scalar helper called from `glue()`; `vapply(USE.NAMES=FALSE)`;
  `deparse(body(f))`; `tryCatch(warning=)` discards; Do not abort inside a handler;
  `match()` treats NA as a value; `expect_message` first-condition; `as.integer("NaN")`;
  `expect_false(identical())`; `tolerance` is relative; `[[` on a named atomic vector;
  `\<`/`\>` word boundaries; testthat failure snapshots; Postgres row order is never
  fixed; `sprintf("%g")`; `information_schema` lookup by literal name; A `pkg::` call
  in a test; `expect_message()` returns the condition; `tryCatch()` nests its handlers;
  `ifelse()` all-NA; A `function(...)` mock; `expect_message(regexp="...$")`.
  72 sections not read (terra/arrow/duckdb/climr/gdalcubes/readr/ggplot/Rmd-render
  shapes this diff does not touch).
- `code-check.md` — **all 14 H3 sections under `## Mechanisms`, in full prose**
  (tables skipped per the brief). Rules-that-stand-alone and Security read as index only.
- `code-check-spatial.md` — read the full text of 9 sections: FWA `upstream_route_measure`
  misses the next segment's start; FWA main flow is not edge type 1000 alone; A Freshwater
  Atlas main stem's downstream end; A name is not a key (`GNIS_NAME`); `pdist::pdist()`
  loses centimetres; A coordinate stored as an attribute; reproject the polygon for a
  lat/lon bbox; Canonicalize geometry before hashing; close a rotated ring by copying.
  ~60 sections not read (terra/GDAL/raster/STAC/KML shapes absent from this diff).
- `code-check-shell.md` — index only. No shell, sed, git-plumbing or `gh` code in the diff.

Everything below was measured against the working tree, not read off the diff. Probe
scripts are in the session scratchpad (`lex.R`, `lex2.R`, `lex3.R`).

---

## Findings

### 1. [bug] `R/frs_migration_trial.R:228-315` (`.frs_sql_blank()`) — double-quoted identifiers are not a token class, so the lexer can blank real top-level SQL and let a `COMMIT` through

The `while` loop has branches for `--`, `/* */` (nestable), `'...'` (with `''` and `E'\'`)
and `$tag$...$tag$`. It has **no branch for `"..."`**. Inside a quoted identifier
PostgreSQL treats `'`, `--`, `/*` and `$` as ordinary characters; the lexer does not, so
it starts a string or a comment region there and mis-tracks from that point on. Two
measured let-throughs, both of which reach `PASSED-SCREEN` with a live top-level `COMMIT;`
in the body handed to `dbExecute()`:

```r
# measured: PASSED-SCREEN
'ALTER TABLE t RENAME TO "x--y"; COMMIT;'
# the `--` opens a line comment, blanking `--y"; COMMIT;` to end of line

# measured: PASSED-SCREEN
'COMMENT ON COLUMN t."a\'s" IS \'x\';\nCOMMIT;\nCOMMENT ON COLUMN t."b\'s" IS \'z\';'
# six apostrophes pair up (1,2)(3,4)(5,6); pair (3,4) spans `;\nCOMMIT;\nCOMMENT ON COLUMN t."b'`
```

This is `code-check.md`'s "A guard that fails toward pass": the refusal path and the
"nothing to refuse" path produce the same answer, and the consequence is that the
migration **commits on a database the caller believed was protected**.

The `pg_current_xact_id_if_assigned()` check is a real backstop for *detection* —
measured, after an in-body `COMMIT;` it returns NULL, so `now` is `NA_character_`,
`identical(now, xid)` is FALSE and the function raises. But it fires **after** the
commit, so it reports rather than prevents. `code-check.md`, "A second check is a
backstop only if it can fire on the cases the first one catches", is satisfied for
detection and not for prevention, and the roxygen currently calls it "the backstop"
without that distinction.

Odd-count cases fail safe (an unterminated region is a refusal), and
`"x/*y"` refuses. Both let-throughs need a quoted identifier containing `--` or an even
number of apostrophes across the file, which fwapg's corpus does not have today — so this
is low-likelihood, high-impact, and it is the shape the next migration can introduce
without anyone touching this file.

Remedies, cheapest first: add a `"` branch (scan to the next `"`, treating `""` as an
escape, mark it kind 1 so it stays code for both scans) — it is five lines in the same
shape as the `'` branch; and say in the roxygen that the screen is best-effort over
arbitrary SQL and that the xid check detects rather than prevents.

### 2. [fragile] `R/frs_migration_trial.R:110-120` — the own-`BEGIN;`/`COMMIT;` pair detection recognises only `--` comments and only the first/last code line, so valid migrations are refused with a message naming the wrong cause

`code <- which(!grepl("^\\s*(--.*)?$", lines))` counts a `/* ... */` line as code, and
`own` requires `BEGIN;` to be *the first* such line and `COMMIT;` *the last*. Measured
refusals, all of them legitimate migrations:

| input | result |
|---|---|
| `/* header */\nBEGIN;\nSELECT 1;\nCOMMIT;` | REFUSED "controls its own transaction at line 2, 4" |
| `BEGIN;\nSELECT 1;\nCOMMIT;\n/* done */` | REFUSED "… at line 1, 3" |
| `SET search_path TO x;\nBEGIN;\nSELECT 1;\nCOMMIT;` | REFUSED "… at line 2, 4" |
| `BEGIN; SELECT 1; COMMIT;` (one line) | REFUSED "… at line 1" |

It fails safe, but the message points at the migration's own perfectly normal
`BEGIN;`/`COMMIT;` pair and says it "would end the trial's" transaction — so the reader's
next move is to edit the migration, which is the wrong fix. fwapg's only local migration
(`202610131654__watershedatmeasure_drop_exbc.sql`) starts on `BEGIN;` and uses `--`
throughout, so nothing in the corpus hits it yet; `db/schema.sql`, which the roxygen names
as the file this function exists to handle, is not in that shape.

Cheapest fix: run the `code` line filter over `.frs_sql_blank(sql)$code` (which already
blanks both comment kinds) instead of over the raw lines, and name the real cause when
`own` is FALSE but the first/last code lines *do* hold transaction control.

### 3. [fragile] `R/frs_migration_trial.R:174` — `nextval` in the rollback-unsafe list refuses a rollback-safe DDL shape, while `serial` (identical semantics) passes

Round 1 added `nextval` to the refusal regex and a test pins it
(`test-frs_migration_trial.R:524`, `CREATE TABLE t (id integer DEFAULT nextval('s'));`).
Measured on the working tree:

```
CREATE TABLE t (id integer DEFAULT nextval('s'));   REFUSED  "a rollback does not undo"
CREATE TABLE t (id serial);                         PASSED-SCREEN
```

A `DEFAULT nextval(...)` clause is not a call: nothing is drawn from the sequence at DDL
time, and `CREATE SEQUENCE` is itself transactional, so a trial of either statement is
fully undone. `serial` expands to exactly the refused form. So the screen refuses the
explicit spelling of a safe shape and admits the sugar for it — the stated property
("sequence changes (`setval()`, `nextval()`)") is not what the implementation tests, which
is `code-check.md`'s "A proxy is not the property": the condition names a *token* where
the requirement is *a sequence actually advanced*.

This is the axis the brief asked about — a round-1 fix written under the same assumption.
It fails safe, so it is not urgent; but the pinned test makes the over-broad behaviour a
contract, and a real fwapg migration that adds a `serial`-equivalent column by hand will be
refused for a reason that is not true. Either narrow to a *call* position
(`nextval\s*\(` outside a `DEFAULT` clause is still only a proxy) or keep the breadth and
say in the roxygen that it refuses the token, not the effect — and drop or re-word the
test so it is not pinning a claim the code does not make.

### 4. [fragile] `R/frs_migration_trial.R:176-180` + `:216-218` — the "a rollback does not undo this" refusal pairs the *first* match's text with *every* match's line

`.frs_sql_scan()` returns `at = unique(at)` over all matches but `what` as the full vector
of match texts; the caller prints `out$what[[1]]` against `paste(out$at, collapse = ", ")`.
Measured:

```
"SELECT 1;\nSELECT setval('s',1);\nSELECT 3;\nSELECT dblink_exec('a','b');"
#> the migration calls setval at line 2, 4, whose effect a rollback does not undo
```

Line 4 is `dblink_exec`, not `setval`. The reader goes to line 4 looking for a `setval`
that is not there. `code-check.md`, "A guard's scope, escape hatches, and remedies":
"ask what someone would *do* on reading the message". Pair them (`paste0(what, " at line ",
at)` over the matches, deduplicated on the pair) rather than crossing the two vectors.

### 5. [fragile] `tests/testthat/test-frs_point_snap.R:580-606` — the live tie tests pin FWA facts that `skip_unless_tied()` does not cover

`skip_unless_tied()` checks exactly one thing: that both hardcoded `linear_feature_id`s
(703862843, 703862887) are present and that their two `ST_Distance` values are bit-equal.
The assertions that follow it pin three more facts about the same live data that the guard
cannot see:

- `expect_equal(one$downstream_route_measure, 14041)` and
  `expect_equal(tied$downstream_route_measure, c(14041, 14040))` — the clamped measures;
- `expect_identical(as.character(one$localcode_ltree), "100.594120.063640")`;
- `expect_identical(nrow(tied), 2L)` — that **both** tied segments fall inside the 5
  nearest once the `blk` hint is dropped, which depends on the *other* stream's segments
  near 08KD006, nothing the guard looks at.

A vintage that keeps the two ids and the exact tie but moves a measure by a metre, or
brings a third segment nearer, reddens these with no behaviour change — and the comment
above the guard ("A database whose FWA vintage has moved the geometry skips instead of
failing confusingly") promises more than the guard delivers. `code-check-r.md`, "Tests
that silently do not run": pinned values from live data are fine, but say so where they are
pinned and re-pin deliberately. One line each naming them as live pins, and widening the
guard to assert the two measures and the localcode before the block proceeds, closes it.

Not a finding: exact float equality **is** the right comparison here. The SQL tie it tests
is PostgreSQL's own `ORDER BY` equality, so `identical()` tests the precondition the
assertions rest on, and it degrades to a skip rather than a failure. Also not a finding:
`skip_if_not()` inside `skip_unless_tied()` and `skip()` inside `local_fwapg()` do skip the
calling `test_that()` block — testthat's skip is a condition caught at any call depth, and
the suite's single SKIP line confirms it.

### 6. [fragile] `tests/testthat/test-frs_point_snap.R:622-630` — the EXPLAIN test pins planner internals and an fwapg index name, against the shared DB, gated only on availability

```r
expect_match(plan, "Index Scan using fwa_streamnetworks_geom_idx")
expect_match(plan, "Presorted Key: \\(\\(s_1.geom <-> ")
```

`s_1` is a *PostgreSQL-generated* alias, invented only because `.frs_point_snap_sql()`
aliases both the lateral subquery and the network table `s`; `fwa_streamnetworks_geom_idx`
is a name fwapg owns. Either a Postgres major-version change to how EXPLAIN disambiguates
duplicate aliases, a different statistics state that picks an equally valid plan, or an
fwapg index rename reddens this with nothing wrong in fresh. The behaviour it is really
guarding — "the tie key did not replace the index-ordered scan" — is worth guarding; pin it
on the shape (`Index Scan`, `Order By: (geom <->`, a `Presorted Key` naming `geom <->` at
all) and drop the generated alias and the index name, or add a skip when the plan has no
`Index Scan` at all so an environment difference skips rather than fails.

### 7. [fragile] `R/frs_migration_trial.R:131-143` — the trial holds DDL locks for the caller's whole frame with no `lock_timeout` or `statement_timeout`

`DBI::dbBegin()` through the deferred `dbRollback()` spans the caller's function, and a
real fwapg migration's `DROP FUNCTION` / `CREATE OR REPLACE FUNCTION` takes
AccessExclusive locks that are held for that entire window.
`code-check-infra.md`, "Set `statement_timeout` + `lock_timeout` on long DB ops", and
`code-check-r.md`'s `CREATE OR REPLACE VIEW` paragraph are both about exactly this: the
statement waits behind every reader and then blocks every reader after it, and without a
timeout a wedge is indistinguishable from "still working". `local_fwapg()` steers the tests
to a local container, but `frs_migration_trial()` is exported and takes any connection —
and its whole purpose is "measure a pending migration without migrating a database other
people use", i.e. it will be pointed at shared instances. `DBI::dbExecute(conn, "SET LOCAL
lock_timeout = '60s'")` right after `dbBegin()` costs one line and reverts with the
transaction.

---

## Checked and clean (so round 3 need not redo these)

- **`sprintf()` argument alignment in `.frs_point_snap_sql()`.** 16 format specifiers,
  16 arguments, aligned: `pts_sql`, `col_seg`, `col_blk`, `col_ds`, `col_us`, `col_ds`,
  `col_ds` (new, `measure_raw`), wscode, localcode, `tbl_network`, where, `col_ds` (new,
  lateral ORDER BY), `col_seg`, `num_features`, `col_id`, `rank_sql`. Counted by hand and
  confirmed by the `.frs_opt()` test (`fresh.measure_ds_col = "m_start"` reaches both new
  sites).
- **`measure_raw` does not reach the caller and collides with nothing.** The outer `SELECT`
  lists columns explicitly; `ORDER BY c.measure_raw` is legal because `ORDER BY` may
  reference FROM-clause columns in a non-`DISTINCT`, non-set-operation query; the `to =`
  path reuses the same `SELECT` in `CREATE TABLE … AS`. The lateral projects a fixed column
  list, so `s.*` into the `c` CTE cannot pick up a base-table column of that name.
- **All three ordering sites carry the same key and end on a column unique per candidate**
  (`linear_feature_id`) — `code-check-r.md`, "Postgres row order is never fixed… a pick
  whose `ORDER BY` ends on a key that is not unique in the group" (the link#282 instance
  that rule records is this exact shape, now closed).
- **The two line-number fixes are correct.** The txn refusal reads
  `attr(hit, "capture.start")[, "kw"]`, so it names the keyword, not the `;` the match
  starts at: `"SELECT 1; /* a\nb */\nROLLBACK;"` → line 3, and a closed `$$` body followed
  by `COMMIT;` → line 5. The `calls` regex has no `(^|;)` prefix, so its match start is
  already the token and `group = NULL` is right.
- **The deferred rollback does not error after the migration committed.** Measured:
  RPostgres tracks its own transaction state, so after `dbBegin()` + an in-body `COMMIT`,
  `dbRollback()` issues a no-op `ROLLBACK` (server `WARNING: there is no transaction in
  progress`) and returns cleanly — the xid check's diagnostic message survives rather than
  being masked by a deferred error.
- **Lexer edges, all measured as sensible:** lone `'`, `-`, `$`, `E`, single char,
  `--` only, `/*` only, `$$` only, `$$$$` (empty body), `$` at EOF, nested
  `$a$ x $b$ y $b$ z $a$` (one body, ends at the first `$a$`, as PostgreSQL does), CRLF
  throughout (own pair still stripped), a `--` comment ended by a bare `\r`,
  `/* -- */`, `-- don't …` followed by a real string, `--` inside a string literal,
  adjacent-literal continuation across a newline, `E'\\'`, plain `'a\'` under
  `standard_conforming_strings = on`, `U&'\0441'`, `$1`/`$2` positional parameters,
  `a$b` as an identifier, `AS$$` with no space (not treated as a body — same direction as
  PostgreSQL's longest-match identifier rule, and it fails toward refusal either way),
  a `COMMIT;` inside a nested dollar body (left to the server, per the accepted tradeoff).
- **`.frs_sql_blank()` is linear and cheap** — 0.005 s on the real 35 kB migration,
  0.077 s on a 353 kB concatenation. The dollar-body branch skips in bulk, so a large
  `schema.sql` is not a problem.
- **The real fwapg migration passes the screen** (`202610131654__watershedatmeasure_drop_exbc.sql`,
  895 lines, 10 non-blank lines of top-level code after blanking).
- **`withr` Suggests → Imports is correctly wired.** Used via `withr::` in `R/`, so no
  `importFrom` is needed; declared, so the test files' `withr::local_tempfile()` /
  `local_options()` will not trip `R CMD check`'s undeclared-`::` warning
  (`code-check-r.md`, "A `pkg::` call in a test").
- **No roxygen rebind** (`code-check-r.md`): `git diff --cached NAMESPACE` adds
  `export(frs_migration_trial)` and removes nothing; 50 exports.
- **`.Rbuildignore`** already covers `figure` and `pkgdown`, the two new untracked
  top-level directories.
- **`_pkgdown.yml`** has no `reference:` section, so the new topic needs no index entry.
- **`lintr::lint("R/frs_migration_trial.R")`** — no lints.
- **Suite** — `devtools::test(filter = "migration_trial|point_snap")`:
  `FAIL 0 | WARN 0 | SKIP 1 | PASS 241`, with a live DB and a local fwapg both reachable,
  so the tie tests and the trial's DB tests all ran.
