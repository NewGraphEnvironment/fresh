# Code check — round 2 (branch `282-custom-aoi-persist-deletes-other-watersh`)

## Checklist read

- `code-check-infra.md` — in full for `## Docker / Postgres` (lines 234-394, every heading);
  index only for Cloud-Init, OpenTofu, DigitalOcean, Tailscale (nothing in the diff provisions
  infrastructure). 4 sections not read in full.
- `code-check.md` — full prose of all 14 H3s under `## Mechanisms` was consulted; read in full:
  "A fixture that cannot reach the failure mode", "A proxy is not the property", "A guard that
  fails toward pass", "One fact derived twice", "Test the cold/create path of idempotent code,
  not just the warm no-op", "Restore the bug and prove the guard fires", "An assertion that
  matches an interpolated value cannot see the claim around it". Index only for the Security,
  Spreadsheets/PDF and remaining stand-alone rules (~20 headings not read in full).
- `code-check-r.md` — read in full the headings naming shapes this diff uses: `on.exit()` at a
  script's top level; a `data-raw/` script must load the source tree; Postgres row order is never
  fixed; `sprintf("%g", …)` writes Inf/NA as bare words; an `information_schema` lookup by the
  literal table name; a database driver's value is not a base R type; a value compared as `::text`;
  `expect_gt()` and friends take no `info`; tests that silently do not run; testthat counts an
  uncaught error under `error`; `expect_false(identical(x, y))` cannot fail; a `pkg::` call in a
  test; `[[` on a named atomic vector; `tempfile()`. Index only for the rest (~75 headings).
- `code-check-shell.md` — index only. The diff adds no shell; the one `Rscript` entry point is
  `data-raw/audit_persist_282.R`, checked against the `Rscript -e`/`--args` and
  "Rscript reads a script as it runs" rules in `code-check-r.md`.
- `code-check-spatial.md` — index only. No terra/sf/GDAL/bcdata call is added or changed; the
  only geometry contact is carrying a `geom` column through an `INSERT … SELECT`.

## Findings

### 1. [bug] R/utils.R:1354-1356 — the single-statement overwrite fails with a duplicate-key violation on any target that has a unique index over the inserted columns, which `fresh.streams` has

Round 1's fix 3 replaced the DELETE/INSERT pair with a data-modifying CTE:

```r
.frs_db_execute(conn, sprintf(
  "WITH del AS (%s) INSERT INTO %s (%s) SELECT %s FROM %s",
  sql_delete, to, cols$cols_sql, cols$cols_sql, from))
```

A data-modifying CTE and the main query run under **one snapshot and one command id**, so
the INSERT's uniqueness check still sees the rows the same statement's DELETE is removing
(`HeapTupleSatisfiesDirty` treats `cmax >= curcid` as live). The DELETE does run to
completion — that part of the comment is right — but it cannot free a key for the INSERT.

Measured on the project database (PostgreSQL 17.5), calling the shipped helper against a
target shaped exactly like `fresh.streams`:

```
run 1 (empty target, custom-AOI key): OK          rows: 2
run 2 (re-run same ground, custom-AOI key): ERROR duplicate key value violates unique
    constraint "zzrev2p_dst_pkey"  DETAIL: Key (id_segment, watershed_group_code)=(11, BULK)
run 3 (whole-group key BULK):               ERROR  same violation
```

The old two-statement form on the same tables: `OK`. So both keys regress, and the
whole-group key regresses too — which is the path the new `@param to_streams` text and the
NEWS entry both name as *the repair* for a table damaged by an earlier release ("Re-running
an affected group with `wsg` repairs it, the whole-group overwrite being self-healing").
On a populated `fresh.streams` that repair now aborts instead of running.

The target is not hypothetical:

```
CREATE UNIQUE INDEX streams_pkey ON fresh.streams USING btree (id_segment, watershed_group_code)
```

(`fresh.streams`, 3,802,814 rows, plus the same `streams_pkey` on 17 sibling schemas'
`streams`). And a re-run collides by construction — the branch's own integration test
asserts `expect_setequal(ids2, ids1)`, i.e. that the second run produces the same
`id_segment` set, which is precisely the set the INSERT must re-insert while the DELETE
holds the old copies.

Why nothing on the branch catches it: `.frs_persist_streams()` creates an absent target with
`CREATE TABLE IF NOT EXISTS … AS SELECT * FROM <from> LIMIT 0`, which copies **no**
constraints or indexes. Every fixture on the branch — the three new `.frs_persist_streams()`
integration tests, the `working.persist_282_streams` target in
`test-frs_habitat.R`, and the "scratch pair" `findings.md` cites as verification
("replaces rather than duplicates … and is idempotent across runs") — is therefore
structurally incapable of carrying a unique key. Verified directly: on an unkeyed target the
helper is idempotent across three runs (2, 2, 2 rows); on a keyed one it fails from run 2.
The mutation sweep inherits the same blind axis, since it mutates the guards and not the
statement form.

`code-check-infra.md`'s own remedy for the non-atomicity this fix is addressing is
`BEGIN; … ; COMMIT`, not a CTE. `findings.md` rejects that on the grounds that "RPostgres
refuses a nested `dbBegin()`" — a real constraint, but one a savepoint (or checking the
connection's transaction state first) answers, whereas the CTE answers it by changing the
visibility semantics the two statements relied on.

- **Rule:** code-check.md "A fixture that cannot reach the failure mode" ; code-check-infra.md "Two-statement DELETE/INSERT into a persist table is not atomic"

### 2. [fragile] R/utils.R:1141-1153 — `.frs_same_relation()` compares name strings, and its roxygen claims that is exact

```r
#' A plain case-insensitive comparison is therefore exact for the names fresh accepts.
.frs_same_relation <- function(a, b) identical(tolower(a), tolower(b))
```

`.frs_validate_identifier()` admits `^[A-Za-z_][A-Za-z0-9_.]*$`, which includes
**unqualified** names. So `to_streams = "streams_bulk"` against the working table
`working.streams_bulk` is one relation whenever `working` is on the `search_path`, and the
two strings compare unequal — the guard passes and the self-delete the guard exists to
refuse goes through, emptying the target. The condition is a proxy for relation identity;
`%s::regclass` (already used by `.frs_persist_columns()`) is the property.

Not reachable on this database as configured (`search_path = public, whse_basemapping, usgs,
hydrosheds`, measured), and `search_path` is database state rather than config
(`code-check-infra.md`), so this is a latent hole rather than a live one. Flagged because the
roxygen states exactness, which is what a later reader will rely on.

- **Rule:** code-check.md "A proxy is not the property"

### 3. [fragile] data-raw/audit_persist_282.R:71 — the shortfall is a difference of two counts, not a set difference, so it can read clean while rows are missing

```sql
(f.n_fwa - coalesce(p.n_present, 0))::bigint AS n_missing
```

`present` counts `DISTINCT linear_feature_id` in the table with **no** guard predicate, while
`fwa` counts guarded FWA segments. Any `linear_feature_id` in the table that is not in the
guarded FWA set for that group (a placeholder/unmapped segment, a row written under different
guards, a mislabelled group) inflates `n_present` and cancels an equal number of genuinely
absent segments, so the script's verdict on whether production data is damaged can be a false
"clean". `NOT EXISTS` against the guarded set answers the question the header asks
("whose `linear_feature_id` is absent from the table") directly.

Measured on one group (`LKEL`): `n_fwa` 2218, `n_tbl` 2218, true set difference 0 in both
directions — so the counts agree there; the masking is possible, not observed. Also:
`FROM fwa f LEFT JOIN present p USING (wsg)` drops a group that is in the table but has no
guarded FWA rows, so `cat("Groups in table:", nrow(res))` is really groups in FWA ∩ table.

- **Rule:** code-check.md "A proxy is not the property"

## Checked and clean

Verified against the round-1 fixes, for the record:

- **Fix 1 (NULL-key guard).** Correct for all three keys and both paths. The key is taken from
  the one chooser the DELETE was built from, so guard and statement cannot name different
  columns. Cold path: a target created by the helper's `CREATE TABLE AS … LIMIT 0` has every
  source column and no rows, so `count(*) WHERE key IS NULL` is 0 and the guard stays quiet
  (confirmed by the new "allows an empty target gaining the key" test). Warm path: the
  condition is a property of the target, so a re-run after the error still raises — the test
  asserts three consecutive failures, and the message switches from "was missing … just been
  added" to "holds rows with no …" exactly when `cols_added` empties. `cols_to` is the
  post-`ALTER` union, so a key the call just added is still a legal key and the guard, not the
  chooser, is what stops the run.
- **Fix 2 (`.frs_partition_wsg()`).** Reached on every persisting path. `wsg_code` appears at
  exactly four sites in `R/frs_habitat.R` (401, 531, 583, 676) and feeds nothing but
  `.frs_persist_streams()`, so narrowing it to the partition decision cannot change what
  `frs_extract()` or `frs_network_segment()` see. `aoi` is never reassigned between the formals
  and the spec build (only `job_aoi` is), so the spec reads the caller's argument. The mirai
  closure is lexically inside `frs_habitat`'s body and reads `spec$partition_wsg` from the spec
  built in the parent — both copies updated.
- **Fix 3** — see finding 1. The CTE does execute its DELETE exactly once and to completion
  (measured: 2, 2, 2 rows over three runs on an unkeyed target), and it is correct Postgres for
  all three keys; the defect is the uniqueness interaction, not the syntax.
- **Fix 4 (`withr::defer(envir = globalenv())`)**. Correct replacement for the top-level
  `on.exit()`. `withr` is not in `Suggests`, but `data-raw/` is `.Rbuildignore`d and not
  checked, and the deferred call only closes a connection the exiting process closes anyway.
- **New tests can fail.** The atomicity test forces the INSERT half to violate a `NOT NULL`
  the source carries, and the two-statement form leaves `nrow(res)` at 0 against 1. The
  integration test asserts the collision is live (step 4) before asserting survival (step 5),
  so a no-op delete cannot satisfy it, and the old `id_segment` key deletes the decoy and
  reddens step 5. The `deparse(body(frs_habitat))` enumeration is sound: `DELETE FROM` occurs
  exactly twice in that file (543, 686), both `blue_line_key`, so pinning the count to 2 is a
  real tripwire; and the positive controls mean a renamed helper fails loudly rather than
  passing on absent text.
- No injection surface added: `wsg_code` goes through `.frs_quote_string()` in the one
  remaining place it is interpolated (the mirai path's raw `'%s'` is gone, and a unit test pins
  `O'HARA` → `'O''HARA'`), every table name through `.frs_validate_identifier()`, and the key
  column through `DBI::dbQuoteIdentifier()`. No route measure or threshold is written by this
  diff, so the `.frs_sql_exact()`/`.frs_sql_num()` rule is not engaged.
- Planning docs: no claim contradicting the code was found beyond `findings.md`'s
  "Verified on a scratch pair … idempotent across runs", which is the fixture gap in finding 1,
  and the `@param to_streams` / NEWS sentence "overwrites its own partition of the table
  **before** inserting, in one statement" — in a data-modifying CTE the order is explicitly
  unpredictable and in practice the main INSERT runs first, which is why finding 1 bites.
