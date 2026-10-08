# Review round 4: Phase 1 diff (#247)

## Clean

No issues found.

## The round-3 fix

The round-3 bug was assertions run against a superset of the text that should hold the property. A column or predicate name that appeared anywhere in the SQL satisfied `expect_match()`, so the tests could not see whether it sat in the outer projection or before the lateral's `LIMIT`. The fix slices the SQL with `sql_lateral()` / `sql_select()` and asserts against the slice.

### Where each positive assertion now looks

Every positive `expect_match()` in the `.frs_point_snap_sql()` section now runs against a slice:

- `ST_DWithin`, `ORDER BY ... <->`, the tie-break, `LIMIT n`, the table, the 3 guards, the hint, `stream_order >=`, the clamp, the `.frs_opt()` table and columns, and the locale-safe tolerance are all checked against `sql_lateral()`.
- The output columns (`"  c.<col>,?\n"`), `c.id AS "id_point"` and `candidate_rank` are checked against `sql_select()`.

The assertions that still use the whole string are all `expect_no_match()`: `fwa_indexpoint`, `edge_type` when `NULL`, `p.hint`, `stream_order >=`, and `candidate_rank` when `num_features = 1`. For an absence check the superset is the stricter direction, so none of these can pass vacuously.

### Whether the slice regexes isolate the right region

- **`sql_lateral()`**: TRE's `.` matches newlines and `.*` is greedy, so the slice runs to the *last* `) s\n`. I confirmed this on a toy string. Today `) s\n` occurs exactly once (counted in all four combinations of `num_features` 1/3 and `has_hint` FALSE/TRUE, with `stream_order_min` set), and it is the lateral's own close. The slice therefore ends before the `c` CTE's tail and the final query. If `) s\n` disappears, `expect_length(out, 1L)` fails loudly.
- **`sql_select()`**: `regexpr()` takes the leftmost `\nSELECT\n`. The inner `SELECT`s are either indented (`  SELECT p.id`, `    SELECT\n`) or not followed by a newline (the test's one-line `pts_sql`), so there is exactly one match and it is the final query. Even when I forced an overrun (unindented `c` CTE `SELECT\n`), the column assertions still bound correctly. That is because the `c.` prefix exists only in the outer query.

### Mutations (each one fails the slice tests; baseline is 43/43 pass)

| Mutation | Result |
|---|---|
| Dropped `c.watershed_group_code`, `c.distance_to_stream`, `c.linear_feature_id` or `c.geom` from the final SELECT | Fails |
| Moved the hint, `stream_order`, `edge_type`, 999 guard or `ST_DWithin` from the lateral WHERE to the `c` CTE `WHERE` | Fails |
| Moved the hint to the final query `WHERE` | Fails |
| Moved `LIMIT` to the final query | Fails |
| Moved `row_number()` into the lateral | Fails |
| Dropped the tie-break from the lateral `ORDER BY` | Fails |
| Dropped the tie-break from the `candidate_rank` window | Fails |
| Unindented the `c` CTE `SELECT` (`sql_select` overrun) and dropped `watershed_group_code` | Fails |

The only mutation that went unnoticed was dropping the tie-break from the final `ORDER BY c.id, ...`. That only changes row order in the output. Candidate choice comes from the lateral and the rank comes from `candidate_rank`, so it is not a correctness gap.

The full file passes: `test-frs_point_snap.R` gives `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 96 ]`.
