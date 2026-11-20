# Code-check round 3 (#279), branch diff 98e7cf0...HEAD

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of every H3 under `## Mechanisms` (table rows and evidence blocks skipped). No `## Rules that stand alone` or Security heading names a tool or shape this diff uses; 31 headings outside Mechanisms not read.
- code-check-r.md: "An `information_schema` lookup by the literal table name misses what Postgres resolves", "`tempfile()` lives in the session tempdir…", "A `skip_if_not()` skips only its own `test_that()` block", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package", "`strsplit()` drops a trailing empty field…". About 160 headings not read.
- code-check-shell.md: no heading names a tool this diff uses (the diff is R and SQL only); none read.
- code-check-spatial.md: none apply; none read.

Probes run in a detached worktree of HEAD (since removed): the scanner over the whole tree (0 hits), the set of live connectors after the fixpoint, every top-level expression the `"mock"` exemption skips, every `fresh` formal whose default names a schema, and two read-only catalog reads (`pg_get_viewdef('pg_indexes')`, and a `pg_class` count over the `pg_temp%` schemas). Nothing was written to any database.

## Mechanism

The shared assumption is that **"a name two runs share" is the same thing as "a fixed string literal that spells the `working` schema, a literal index name, or a `frs_habitat()` label, inside a block that calls a connector"**. That is a lexical proxy. The property is about the namespace the database resolves at run time. It covers every schema and every object kind with a schema-wide name, names that package code builds from arguments other than `to`, and catalog queries whose match set is wider than this session's objects. The proxy and the property come apart along four axes:

- **where** the name is built: a literal, versus a variable, a fragment, or the package's own body;
- **which namespace** it lands in: `working`, versus `public`, another schema, or a temp schema;
- **which direction** it is used: created, versus matched in a catalog lookup;
- **which blocks count as live**: whether the block calls a connector by name.

Every earlier instance sits on one of these axes. A fixed index name and a name built from `"working."` fragments are on the first. A label passed through a variable and an unqualified name resolved through `search_path` are on the first and second. Bare names in `pg_indexes` and `information_schema` lookups are on the third.

### Scanner (helper-test_names.R)

| place | status |
|---|---|
| `working` in any spelling or quoting, as a whole literal, a fragment, `DBI::Id`, `search_path` | covered |
| a schema other than `working` (`public`, `fresh`, user schemas) | **open, undocumented**. The header and CLAUDE.md describe the guard as finding "names two runs would share", but it looks only at `working`. The migration-trial tests name `public.frs_trial_<run>_x` by hand, and the guard would not have flagged the old `sample()` names or a fixed `public.` name. grep: no live fixed name in another schema today. |
| a bare, unqualified name created live (it resolves through `search_path`, usually to `public`) | **open, undocumented**. The header documents bare names in lookups only. grep: every unqualified live `CREATE` today is `TEMP`. |
| a literal index or constraint name | covered for `CREATE [UNIQUE] INDEX [CONCURRENTLY] [IF NOT EXISTS] <ident> ON` and `CONSTRAINT <ident>`. **Open** for a quoted name (`CREATE INDEX "x" ON`) and for a literal passed in as a `sprintf` argument; the second is documented as "assembled in a variable". None today. |
| a `frs_habitat()` label not built by `frs_test_label()`; wsg mode | covered |
| a `to` formal whose default is in `working` | covered. The 6 functions with such a default all appear in `.frs_test_default_to()`: frs_barriers_minimal, frs_break, frs_break_find, frs_feature_find, frs_feature_index, frs_habitat_access. No other formal in the package defaults to a schema-qualified name. |
| package code that builds a `working` name from a non-`to` argument, or from a NULL default it resolves in the body | **open, undocumented, unreached**. `frs_habitat_partition(label=)` builds `working.streams_<label>` and `working.breaks_{access,habitat}_<label>_*`. `frs_habitat_species(to = NULL)` builds `working.streams_<sp>`, which is fixed per species. `.frs_test_default_to()` reads only literal `to` defaults, and the label rule names only `frs_habitat`. No test calls either live: the only call, to `frs_habitat_access`, is mocked. `frs_habitat()`'s own `working` schema is out of scope (#310). |
| a bare name compared against `information_schema` / `pg_indexes` `table_name` | documented as out of scope. Every migrated lookup uses `frs_test_tbl_parts()` (break:582, col_generate:77, extract:262, habitat:290/324/399, utils:60). |
| a catalog lookup by bare name of a **`pg_temp`** table | **open: finding 1**. CLAUDE.md now calls `pg_temp` "session-local". That holds for name resolution, not for catalog views. |
| a block reaching a database without calling a connector (a connection passed by symbol, `do.call(frs_db_conn, …)`, a top-level `conn`) | open in principle. Measured: no test block does this. The live set after the fixpoint is the base 7 plus `bcfp_conn` and `local_fwapg_indexpoint`. The one symbol-passed connector, `skip_if_no_conn(bcfp_conn)`, sits at top level in a file whose blocks call `bcfp_conn()`. |
| a top-level expression exempted by a `"mock"` string | covered. Measured: the 4 exempted helpers (channel_width:15, fetch_sql:4, network_features:665, order_child:10) all pass `"mock"` as the connection. |
| names a test derives from helper output (`paste0(hab, "_near_river")`, `%s_pkey` from `frs_test_tbl_parts()`) | covered by construction: they carry the run id. |

### Helpers (helper-db.R, setup-run_namespace.R)

| place | status |
|---|---|
| run id = `t` + `tolower()` of the mkdtemp suffix | covered, though only probabilistically. mkdtemp is unique per filesystem, and folding case on a case-sensitive filesystem leaves about a 7e-10 chance that two runs collide. **Open, undocumented**: forked children (`parallel::mclapply`, `mcparallel`) share the parent's `tempdir()` and so its run id. No runner in the repo forks a suite today; each run is its own `Rscript` / `devtools::test()` process. Sequential runs in one session share an id, which is harmless because each run sweeps at its end. |
| length budget (36 for a table, 20 for a label) | covered. The run id leads a `frs_test_tbl()` name and starts at byte 9 of a label table, so truncation at 63 bytes cannot strip it, and cross-run uniqueness survives truncation. Within one run, the longest test name is 28+8 = 36 (`persist_brk_disabled_habitat`), and paired index suffixes such as `_localcode_gist_idx` / `_localcode_btree_idx` stay distinct at that length. |
| sweep: `strpos(relname, '<run>_')`, `working` only, relkind r/p/v/m | covers `frs_test_tbl()` tables and the tables named after a label (`streams_<run>_*`, `barriers_<run>_*_gradient`, `*_acc_*_ovr_*`). Out of scope and documented: a killed run, and the `FRESH_PG*` database. Verified: no test file mixes `local_fwapg` with `frs_test_*`. `public.frs_trial_*` is rolled back by the trial itself. A substring hit on another run's table would need a random 7-character collision, which is negligible. |
| CLAUDE.md's leftover query `relname ~ '(^|_)t[a-z0-9]{6}_'` | documented as human-judged ("drop the ones no running suite owns"). It also matches ordinary 7-letter words after `_` that start with `t`, so it is a lookup, not a drop list. |

### Migrated tests

| place | status |
|---|---|
| the 17 migrated files | covered. The scanner finds 0 hits at HEAD (57 files scanned). |
| `decoy_282` | covered. It moved to `pg_temp.` and was already `TEMPORARY`, and every reference to it resolves in-session. |
| test-frs_migration_trial.R `public.frs_trial_<run>_{a..d}` | covered by hand. The guard does not see the `public` schema (row 2 of the scanner table). |
| test-frs_feature_index.R:84 (not migrated; uses `pg_temp`) | **open: finding 1** |

## Findings

- **[severity: fragile]** tests/testthat/test-frs_feature_index.R:83-86. `SELECT indexdef FROM pg_indexes WHERE tablename = 'fi_dnstr'` filters on the bare name only. `pg_indexes` joins `pg_class` to `pg_namespace` with no namespace filter (read from `pg_get_viewdef('pg_catalog.pg_indexes')` on PostgreSQL 17.5). Another backend's temp relations are visible from this session (a `pg_temp_39` holding 12 relations showed up in `pg_class` while probing). So when two runs execute this file at once, `defs` also holds the other run's `fi_dnstr` index rows. `expect_match(defs, "\\(id_segment, watershed_group_code\\)", all = FALSE)` then passes on the other run's index even when `frs_feature_index()` built none here. The test fails toward pass in exactly the condition #279 exists for. The test predates the branch and is unchanged on it. It is in scope because the branch's CLAUDE.md now recommends `pg_temp` as "session-local" and the guard treats `pg_temp` names as safe. `pg_temp` is session-local for name resolution, but not in catalog views. Fix: filter on `schemaname = pg_my_temp_schema()::regnamespace::text`, or on `indrelid = 'pg_temp.fi_dnstr'::regclass` through `pg_index`. test-frs_network_features-local.R:53 already does this with `relnamespace = pg_my_temp_schema()`. A clause in the CLAUDE.md bullet would keep the next pg_temp test from repeating it: "session-local for name resolution; a catalog lookup by bare name still sees other sessions' temp tables".
  - **Rule:** code-check-r.md "An `information_schema` lookup by the literal table name misses what Postgres resolves" ; code-check.md "A proxy is not the property"

No other real issues. The open rows in the enumeration are latent: no current test reaches them. They are listed so their scope can be stated, not as defects.
