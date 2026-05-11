## Outcome

Shipped `frs_candidates_pick()` as a new exported primitive (fresh v0.31.0). Given a candidates table where multiple rows share the same key, optionally score per row via a caller-supplied SQL expression, optionally filter via a caller-supplied WHERE clause, then keep one row per key via `DISTINCT ON (col_key) ORDER BY ...`. Fourth member of the point-handling family (`frs_point_snap` → `frs_candidates_pick` → `frs_point_match`).

Live byte-identical validation on BULK PSCIS-to-stream dedup using `bcfishpass.pscis_streams_150m` as scored-candidates input at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`: **102 / 102 ref picks identical, 0 missing.** Closes the BULK 5-diff gap from fresh#206 (`frs_point_match`) at the dedup-step level. The 4 "extras" we see are bcfp's downstream `suspect_match` routing filter that lives caller-side, not in this primitive.

Parameter naming follows the `table_<role>` / `col_<role>` / `exp_<role>` conventions: `table_in`, `table_to`, `col_key`, `exp_score`, `exp_filter`, `order_by`. The `exp_<role>` convention is new (codified in link/CLAUDE.md as part of this PR cycle) — covers SQL-expression parameters the caller writes that get embedded into a generated query.

25 mocked tests covering input validation, identifier sanitization, reserved-column collision (when `exp_score` set), and SQL composition (full path + `exp_score=NULL` variant + `exp_filter=NULL` variant). lintr clean; `R CMD check` 0 errors / 4 warnings / 4 notes — identical to main pre-PR.

First consumer: [link#154](https://github.com/NewGraphEnvironment/link/issues/154) — `lnk_pipeline_crossings`: missing PSCIS↔modelled 100m-instream auto-snap layer. With #206 + #207 shipped, link#154 becomes a three-step composition:

```
1. frs_point_snap(num_features = N)      # multi-stream candidates per PSCIS
2. frs_candidates_pick(exp_score, ...)   # pick best stream per PSCIS by name + distance
3. frs_point_match(distance_max, tiebreak)  # match to modelled crossings
```

Closed by: PR TBD (squash + tag v0.31.0). Follow-ups: none filed; link#154 picks up the consumer side.
