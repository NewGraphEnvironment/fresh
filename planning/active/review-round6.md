# Code check, round 6: #259 near_river (b616b44, whole branch at f849739)

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms`, with the table rows skipped (from the extracted `mech_prose.txt`). I did not read its other headings, about 30 of them.
- code-check-r.md: I read 11 sections:
  - "Postgres row order is never fixed…"
  - "`sprintf("%g", x)` writes `Inf` and `NA`…"
  - "An `information_schema` lookup…"
  - "R's `yaml` returns a mixed int/float sequence…"
  - "A database driver's value is not a base R type…"
  - "A value compared as `::text`…"
  - "Under `R CMD check`, tests run from a temp dir…"
  - "Tests that silently do not run"
  - "`paste()` with a zero-length argument…"
  - "`data.frame()` recycles a scalar…"
  - "A `data-raw/` script must load the source tree…"

  I did not read the other 105 or so.
- code-check-spatial.md, code-check-shell.md: none read. b616b44 adds no spatial call, and the diff has no shell code. Earlier rounds read the FWA sections of the spatial file.

## How I tested

- The tests ran in an rsync copy of the repo. `test-frs_near_river.R` passes 42, `test-near_river_rules.R` passes 64 and `test-frs_habitat_classify.R` passes 52, with 0 failed, 0 errors and 0 skipped (`NOT_CRAN=true`).
- The probes ran in `pg_temp` on the test fixture (`.nr_tributary()`). I created no schema.
- **Process note.** I ran `roxygen2::roxygenise()` once in the repo by mistake, to check that the Rd files were current. It rewrote only `man/fresh-package.Rd`, where the author and funder lines came out differently. That is drift unrelated to this branch. I restored the file with `git restore`, and `git status` again shows only the pre-existing untracked `docker/docker-compose.override.yml`. Nothing near_river-related in `man/` changed, so the Rd files are current with b616b44.

## (a) b616b44

- **The pair loop.** Each iteration drops `walk_tbl`, walks a single `(q, d)` and inserts the result stamped `.frs_sql_num(d)::double precision`. The `DELETE` runs once, before the loop, over the table's groups. Every pair's walk covers those same groups, so the rows can neither duplicate nor go missing.
  - A probe of classify with CH rearing at (3, 500) and CO at (3, 1000) on one table gave:
    - CH rearing on 11 and 12, and CO on 11, 12 and 13;
    - `<to>_near_river` holding 3 rows at d = 500 and 4 at d = 1000.

    That is right.
- **Literal matching.** Both sides go through `.frs_sql_num()`. The stored value is `'<lit>'::double precision`. The predicate compares a float8 column with a numeric or int4 literal, and Postgres resolves that through the implicit cast to float8.
  - I tested equality for 12 awkward values: 1/3, 2/3, 1e-5, 1e-10, 123456.7891234, 0.1, 1000, 1e12, 9999.99999999 (stored as "10000"), 7.000000000049 (stored as "7"), 2^-30 and 2.1e-6. All were TRUE.
  - Pairs that differ only past 10 significant digits stay distinct in R, so they are walked twice and stored under the same text. The `EXISTS` is unaffected.
- **`.frs_near_river_specs()`.** The loader stores `near_river` as `as.numeric` and the specs re-apply `as.numeric`, so YAML integer and double values both dedupe. `unique()` on the data frame, then `order()` on both columns, is correct.
- **Validation.** `anyDuplicated(data.frame(discharge_min, distance_max))` runs after the length check, so the data frame cannot fail to build.
- **Verbose output.** For a single pair, `count(*)` over the walk table is one row per origin. The `nocode` count matches the origin filter.
- **An old-shape table.** No release has created one, `link` has no reference to `near_river`, and the local database holds no `*near_river*` table. A table from an earlier commit of this branch fails loudly at the `INSERT` (`column "distance_max" does not exist`, probed). That is not a real failure.

## (b) Spec independence

**The invariant holds by construction.** Each walk's inputs are:
- `table`, `walk_tbl`, `q` and `d`;
- `conn_max` and `entry_max`, both read from `table` before the loop;
- `VALUES` holding that single pair.

Nothing reads `to` or the previous pair's walk table, which is dropped before every walk. One caveat: the internal function can still be called with several pairs, and its documentation still promises independence there (Finding 2).

## Findings

### Finding 1

- **[severity: fragile]** R/utils.R:396-403 (`n.distance_max = D`), with the docs at R/frs_habitat_predicates.R:89-92 (`@param near_river_table`, "as written by frs_near_river()") and R/frs_near_river.R:66-76 (`@param to` / `distance_max`).
- **The new contract.** Since b616b44 a rule matches only rows from a walk of exactly its own `(discharge_min, distance_max)`. Neither exported function says so.
- **What goes wrong.** A caller builds the table directly with `frs_near_river()` at a covering distance, which until b616b44 was the documented model ("each rule's own distance is applied in its predicate"). They then test rules at shorter distances with the exported `frs_habitat_predicates(near_river_table =)`. Every `EXISTS` is FALSE. There is no error, and the result reads exactly like "no river near".
- **Probe.** `frs_near_river(..., 3, 2000)`, then `.frs_near_river_sql(list(discharge_min = 3, distance_max = 500), …)`, counted 0 segments on the fixture. Three segments lie within 500 m at q = 3.
- **Why it matters.** `frs_habitat_classify()` is unaffected, because it builds the exact pairs. The direct `frs_near_river()` → `frs_habitat_predicates()` route, which the docs present as the way to inspect or re-test, now fails silently on any distance mismatch.
- **Fix.** State the exact-pair requirement in both `@param` entries and in `frs_near_river()`'s description: a walk at one distance answers only rules at that distance.

### Finding 2

- **[severity: fragile]** R/frs_near_river.R:229-284 (doc) and :287-406 (`.frs_near_river_walk_sql()`).
- **Stale docs.** The internal walk still takes vectors, and its docs still say:
  - "One walk serves every discharge";
  - "one discharge and distance gets the same answer whatever else is asked";
  - "no answer depends on the other discharges and distances in the call";
  - "The prefilter is an optimisation that must not change an answer".

  Round 5's repros A, F and G disprove all four in multi-pair mode, and the last is contradicted by the residual short read now documented in `frs_near_river()`.
- **A multi-pair call also loses the pair.** The output is `GROUP BY origin_id, watershed_group_code, discharge_min` and has no `distance_max`. Two pairs at one discharge therefore merge into one row per origin.
  - Probe: `c(3, 3)` and `c(500, 1000)` wrote one q = 3 row per origin, including origin 13 at 1,000 m, which is beyond the 500 m pair.
- **Not live today.** No caller passes more than one pair: `frs_near_river()`, the test at test-frs_near_river.R:245 and `data-raw/near_river_check.R` all pass scalars.
- **Why fix it.** The function's signature and docs invite a caller to batch pairs again, which would bring back exactly the dependence b616b44 removed.
- **Fix.** `stopifnot(length(discharge_min) == 1L, length(distance_max) == 1L)` and reword the doc, or carry `distance_max` through the output and `GROUP BY`.

## Not findings (recorded)

- **The `DELETE` now precedes the walks.** Before b616b44 the walk ran first. Now a walk that errors on pair k leaves the group's rows for pairs 1 to k-1 only.
  - The table is derived and rebuilt on every call.
  - The error propagates, and classify has already deleted the habitat rows by then.
  - So it is not the persist-table data loss that code-check-infra's "Two-statement DELETE/INSERT" rule covers.
- **NEWS timings.** NEWS says "16.5 s at 1 km and 72 s at 20 km". The committed artifact it describes (`data-raw/logs/near_river_259/bulk_stamp.txt`, @ b616b44) says 16.3 s and 72.9 s, and 72.9 rounds to 73. The other NEWS numbers match the logs: 2,462 starts, and the classes agree / bank / beyond / entry / nested_code.
- **The loosened check-script classifier** (`entry` now takes any positive residual with a jump). I re-applied the old bound to the committed `bulk_compare.csv`: 223 of 225 `entry` rows fall within it. The other 2 are the near-reach rows the new `ref_m + ref_gap > d_far` arm admits legitimately. Positive residuals are at most 1.48× `jumps_m`, so the loosening hides nothing in this data.
