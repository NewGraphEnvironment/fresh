# Code-check round 4 — #319 branch (e7c1b7b), focus: round-3 fix in `.frs_query_col_types()`

## Checklist read

- `ck1/code-check-infra.index`, `code-check-r.index`, `code-check-shell.index`, `code-check-spatial.index`, `code-check.index`: read in full.
- `code-check-infra.md`: Docker / Postgres section read in full, line by line. The other sections (Cloud-Init, OpenTofu, DigitalOcean, Tailscale) skimmed at 220 characters a line. None of them touches this diff.
- `code-check-r.md`: read in full the sections "A database driver's value is not a base R type — and it fails twice", "An `information_schema` lookup by the literal table name misses what Postgres resolves" and "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's". The diff uses DBI column info, a catalog lookup and SQL text built from R values.
- `code-check-shell.md`, `code-check-spatial.md`: indexes only. No shell, sf, terra or GDAL code is in the round-3 fix. The geometry/geography typmods are covered by the catalog sweep below.
- `code-check.md`: read the prose of all fourteen H3s under `## Mechanisms`, without their evidence blocks.

## The mechanism behind round 3 (a)

The fix assumes that **a type named without its modifier is at least as wide as the modified source type.** `ADD COLUMN x <name>` with no modifier gives `atttypmod = -1`, and for almost every type that means "unconstrained". The SQL standard makes two exceptions. A bare `character` means `char(1)` and a bare `bit` means `bit(1)`, so `format_type(oid, NULL)` gives a name narrower than the type. (`format_type(oid, -1)` would give `bpchar` and `"bit"` instead.) Two other routes could reach the same failure: a domain, which carries its own typmod, and an array of a modified type.

### Enumeration from the catalog (live fwapg, `pg_type WHERE typmodin <> 0`)

Every type in this database that accepts a modifier is in the table below, 24 in all. The list comes from the catalog, not from memory. PostGIS `raster`, pgvector and similar types are not installed here.

| oid | type | `format_type(oid, NULL)` | covered by |
|---|---|---|---|
| 1042 / 1014 | bpchar / _bpchar | `character` / `character[]` (= char(1)) | CASE → `character varying[ ]` |
| 1560 / 1561 | bit / _bit | `bit` / `bit[]` (= bit(1)) | CASE → `bit varying[ ]` |
| 1043 / 1015 | varchar / _varchar | `character varying[ ]` | bare = unconstrained |
| 1562 / 1563 | varbit / _varbit | `bit varying[ ]` | bare = unconstrained |
| 1083 / 1183 | time / _time | `time without time zone[ ]` | bare = precision 6 (max) |
| 1114 / 1115 | timestamp / _timestamp | bare | same |
| 1184 / 1185 | timestamptz / _timestamptz | bare | same |
| 1266 / 1270 | timetz / _timetz | bare | same |
| 1186 / 1187 | interval / _interval | `interval[ ]` | bare = all fields, precision 6 |
| 1700 / 1231 | numeric / _numeric | `numeric[ ]` | bare = unconstrained |
| geometry / _geometry | PostGIS | `geometry[ ]` | bare = any subtype, any SRID |
| geography / _geography | PostGIS | `geography[ ]` | same |

There are 7 domains in the database. The two with a typmod are `information_schema.time_stamp` (`timestamp(2) with time zone`) and `information_schema.yes_or_no` (`varchar(3)`).

### Empirical sweep: `frs_col_join()` at e7c1b7b over a subquery source

Each source value carries a modifier. The created column was read back from `pg_attribute`, and the value was compared as text with the source. Script: `/private/tmp/claude-501/-Users-airvine-Projects-repo-fresh-305/2afc4f62-8ff5-4253-b5e3-53e143af3723/scratchpad/sweep2.R`.

| source | created | atttypmod | value equal |
|---|---|---|---|
| `char(4)`, `char(4)[]`, unconstrained `bpchar` | `character varying`, `character varying[]`, `character varying` | -1 | yes |
| `varchar(4)`, `varchar(4)[]` | `character varying[ ]` | -1 | yes |
| `time(0)`, `timestamp(0)`, `timestamptz(0)`, `timetz(0)`, `interval(0)`, `interval year`, `timestamp(0)[]` | bare | -1 | yes |
| `bit(3)`, `bit(3)[]`, `varbit(5)` | `bit varying`, `bit varying[]`, `bit varying` | -1 | yes |
| `numeric(10,2)`, `numeric(10,2)[]` | `numeric[ ]` | -1 | yes |
| `geometry(Point,3005)`, `geometry(Point,3005)[]`, `geography(Point,4326)` | bare | -1 | yes |
| domain `yes_or_no` (varchar(3)), domain `time_stamp` (timestamptz(2)) | `character varying`, `timestamp with time zone` | -1 | yes / probe artifact* |
| domain over `char(4)`, over `bit(3)`, over `numeric(6,2)` with CHECK | `character varying`, `bit varying`, `numeric` | -1 | yes |
| array of a domain over `char(4)` | `d_c4[]` (the domain keeps its own typmod) | -1 | yes |
| `"char"`, `name`, enum, `numrange`, `ltree` | same type | -1 | yes |

\* The `time_stamp` row compared two `now()` calls run in different autocommit statements, so the mismatch comes from the probe and not from the code.

Domains are covered without any CASE arm of their own. The RowDescription message sends a domain's base type and typmod (`getBaseTypeAndTypmod` in printtup.c), so RPostgres's `.oid` for a domain over `char(n)` is `bpchar`, which the CASE then widens. An array of a domain is reported as the array-of-domain type, and that type keeps the domain's own typmod, so it is exact. Domain constraints are dropped on the new column, which only widens it.

**Result:** in this catalog the mechanism has exactly two narrowing members, bpchar and bit, plus their arrays. The fix covers all four. Every other typmod-bearing type has a bare name that is unconstrained, which matches the code comment "every other type's bare name is its widest form".

### Restore-the-bug check

I replaced the CASE with the old `format_type(o, NULL)` in the review worktree and ran `test-frs_col_join.R`. The new test failed with `test-frs_col_join.R:207:3 ... value too long for type character(1)`. I then restored the file and reran: `[ FAIL 0 | PASS 26 ]`. The worktree is unchanged (`git status` clean).

### Checked and harmless

- **`.oid` type.** RPostgres 1.4.10 returns `.oid` as R `integer`. An OID above 2^31 would arrive negative, and the `int4 → oid` cast in `ARRAY[...]::oid[]` wraps it back. The largest `pg_type` OID here is 278,262,310.
- **Pseudo-type columns.** A subquery column typed `record` (`ROW(...)`) now fails at `ALTER` and leaves the earlier columns added. Before #239 it failed at the `UPDATE` instead, also leaving columns added. Not a regression.
- **char semantics.** `char(n)` → `varchar` drops trailing pad spaces, as `bpchar::text` does. Comparisons are unchanged.
- **Data checked.** No column of type `character` or `bit` exists in the fwapg schemas except two in `tiger`. link's three `frs_col_join()` columns (`double precision`, `text`, `integer`) are untouched.

## Findings

- **[severity: fragile]** NEWS.md:18 and CLAUDE.md:336 — NEWS says "A table source keeps the types it had", and CLAUDE.md says "For a table's scalar built-in columns that is what the `information_schema` lookup it replaced gave". Both are false for `char(n)` and `bit(n)` table columns. The old lookup returned `data_type` = `character` / `bit`, so it created `char(1)` / `bit(1)`. A `char(1)` table column used to come through as `char(1)` and now becomes `character varying`. The roxygen for `.frs_query_col_types()` states this correctly ("except that `char(n)` and `bit(n)` become …"). NEWS contradicts itself within one paragraph, and the CLAUDE.md "that" covers the char/bit clause just before it. Impact is nil for link and for fwapg's non-tiger schemas, which have no such columns. It is still a false claim in two files a reader treats as the contract.
  - **Rule:** none
