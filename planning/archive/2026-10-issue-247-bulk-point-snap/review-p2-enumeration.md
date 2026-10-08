# Phase 2 code-check — enumeration (terminal step)

Round 2 found two defects inside round 1's fixes, one axis over (the
lon/lat drop was keyed on EPSG 4326 only; the `to` guard compared against
the points table only). Per `/code-check`, the loop ends on an enumeration
of the candidate set each mechanism implies, not on a quiet round.

## Mechanism A — `to` is dropped before the statement that reads its inputs

Candidate set = every relation the `CREATE TABLE <to> AS <snap>` reads
(`grep -n "FROM %s" R/frs_point_snap.R`):

| line | relation | guarded |
|---|---|---|
| 187 | temp table `frs_tmp_*` (df / sf input) | name is drawn per call by `tempfile()`; not caller-guessable |
| 365 | table `points` | yes — `to` vs `points`, case-insensitive |
| 442 | `.frs_opt("tbl_network")` | yes — added round 2 |

Line 352 (the id / SRID pre-check) runs before the DROP, so it is not in
the set. 3 of 3 covered.

## Mechanism B — one per-row value fails the whole batched statement

Candidate set = every per-row value written to the temp table and used
in SQL:

| value | failure in SQL | handling |
|---|---|---|
| `id` | none (any written type supports DISTINCT / ORDER BY) | — |
| `x`, `y` geographic CRS | ST_Transform "latitude or longitude exceeded limits" | dropped with message, any geographic CRS (round 2) |
| `x`, `y` NaN / Inf | — | dropped (`IS NOT NULL` / range check); verified round 2 |
| `x`, `y` projected | none observed (1e12 in 26909 ok, round 2) | — |
| `hint` | `::bigint` out of range for Inf / >= 2^63 | rejected up front, ids named (added in this pass) |
| `hint` NaN / NA / all-NA logical | — | NULL → unconstrained (verified rounds 1-2) |

Table-input rows are the caller's data (accepted tradeoff); 6 of 6 R-side
values covered.

## Mechanism C — numeric arguments formatted into SQL

| arg | rendered by | bad input result |
|---|---|---|
| `tolerance` | `.frs_sql_num(as.double())` | NA/NaN rejected; Inf → `'Infinity'`; integer64 fixed round 1 |
| `num_features` | `%d as.integer()` | NA rejected; Inf rejected (this pass) |
| `stream_order_min` | `%d as.integer()` | NA rejected; Inf → `NA` → SQL error (loud) |
| `srid` | `%d` | NA rejected; Inf → `NA` → SQL error (loud) |
| `exclude_edge_types` | `.frs_snap_guards()` `as.integer()` | NA → SQL error (loud) |
| identifiers (`to`, `points`, `col_*`) | validated patterns | rejected |

No silent path remains: each bad value is rejected, rendered correctly, or
fails loudly.
