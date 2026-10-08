# Phase 3 code-check — enumeration (terminal step)

Round 2 found the round-1 `feature_id` type fix one axis over (`label`
under `label_map`), so the loop ends on an enumeration, not a quiet round.

## Mechanism — one output table, column types decided in several places

Two writers (table path, points path) build `to` by `CREATE TABLE AS`, and
`append` inserts into the DDL in `.frs_feature_find_write()`. Each output
column's type comes from a SQL expression per path plus the DDL; R-side
formatting is a fourth place. Every column × writer:

| column | table path (create) | points path (create) | append DDL | cross-path append |
|---|---|---|---|---|
| blue_line_key | source `col_blk` type | native (int4 FWA / int8 custom; no `as.integer` NA) | integer | assignment cast; out-of-range errors loudly |
| downstream_route_measure | source `col_measure` type | float8 (CEIL of float8) | double precision | assignment cast |
| label | `NULL::text` / quoted literal / `col::text` / CASE `col::text` (fixed) | same expressions on `label_src` | text | text = text |
| source | quoted literal (text) | `'sf'` (text) | text | text = text |
| feature_id | `col_id::text` (fixed round 1) | `::bigint::text` for whole doubles, else `::text` (fixed round 2) | text | text = text |

R-side formatting into SQL: none left — the points path writes native
values to the temp table (`blue_line_key` / measure / id / label), and
literals go through `.frs_quote_string()`. 5 of 5 columns consistent.

Accepted: a table-path `col_id` that is a float8 column with 16+ digit
values renders in exponent form (`float8::text`); the type is unknown
without a catalog lookup and real id columns are integer / text.

## Mechanism — `to` dropped before the statement that reads its inputs

Relations the rebuild reads: table path — `points_table`, `table`
(scoping); points path — temp table (per-call random name), `table`.
`to` is now refused when equal to `table` or `points_table`, and the DROP
moved into `.frs_feature_find_write()` after every check and the snap, so a
failing call leaves an existing `to` in place. 3 of 3 covered.
