# Code-check round 3: #262 / #263 (branch 263-inherit-near-river-from-the-thresholds-c)

## Checklist read

- `code-check-infra.md`: in full (36,939 bytes).
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, with `|` rows and evidence blocks skipped. The 23 H3s outside Mechanisms were not read.
- `code-check-r.md`: 9 of 111 H3s read: "CSV whitespace", "`nzchar(NA)` is TRUE", "`$` on a list partial-matches", "A database driver's value is not a base R type", "An `information_schema` lookup by the literal table name", "Postgres row order is never fixed", "A value compared as `::text`", "R's `yaml` returns a mixed int/float sequence", "`ifelse()` with an all-NA test". The other 102 were not read.
- `code-check-shell.md`: 0 of 67 read. The diff has no shell.
- `code-check-spatial.md`: 0 of 92 read. Round 2 read the FWA main-flow section, and nothing in the fixes touches it.

## Test runs

These ran from a `git archive HEAD` copy with `NOT_CRAN=true`, reading counts from `as.data.frame(test_file())`:

| file | failed | error | skipped | passed |
|---|---|---|---|---|
| test-near_river_inherit | 0 | 0 | 0 | 187 |
| test-near_river_rules | 0 | 0 | 0 | 76 |
| test-frs_near_river | 0 | 0 | 0 | 54 |
| test-frs_habitat_classify | 0 | 0 | 0 | 59 |

## The mechanism behind (1) to (3)

**The shared assumption:** checking an input in R, before the work starts, guarantees that the later code can consume it. Each guard was a second description of the consumer's input contract, written by hand, and each round found a member of the real contract that the description did not list:

- **(1)** "Unset" meant {NULL, NA}. The reader also produces `""` for a blank cell in a character column.
- **(2) and (3)** "What the walk needs" first meant {`mad_m3s` present}, then {the measure columns and the table shape}. The walk also reads every column in `cols_need`, every number, and the output table's shape.

**Why the gaps cost data.** `frs_habitat_classify()` runs `DELETE FROM <to> WHERE watershed_group_code = ...` and then the walk and the INSERTs, with no transaction around them. A guard that misses any failure the later steps can raise therefore turns that failure into lost habitat rows.

**What fix 2 closed.** It made the two R-level descriptions one function (`.frs_near_river_check()`), so the R `stop()`s now agree by construction.

**What it left open.** The walk is SQL, and Postgres checks its own preconditions when the statement runs: column types, the `FWA_Downstream` function, the `whse_basemapping` polygon tables, and SRIDs. Those are a third description of the contract, and they are still enforced only after the DELETE.

### Where the mechanism reaches in this diff, and whether `findings.md` covers it

| # | Two lists that must agree | State | Covered by the round-2 enumeration? |
|---|---|---|---|
| a | `.frs_build_near_river()`'s `get()` "unset" set against what read.csv / DBI / `as.numeric()` produce for a blank cell | Agree after fix 1. `""`, whitespace, NA, logical-NA columns and DB `''` / NULL are all unset. Also unset, silently: a numeric cell that fails to parse (`"1,000"`, with only the coercion warning) and `"NaN"` (`is.na(NaN)`). Half a pair still stops on the other cell, so this is not a failure. | No. It is a load-time question, and the enumeration covers only post-write stops. |
| b | `char_fields` (two measure names, typed by hand) against `.frs_near_river_csv_cols()` and the columns `.frs_build_near_river()` reads | Agree. If they drifted, the measure would pass through `as.numeric()`, become NA and silently read as `model`. | No. |
| c | classify's pre-write check against `frs_near_river()`'s R checks | One function since fix 2. | Yes. |
| d | classify's pre-write check against the walk's **SQL** preconditions, column types first | **Do not agree.** Reproduced; see the finding below. | **No.** The enumeration's candidate set is R `stop()` calls ("`frs_near_river()`'s body now holds no check of its own"), so it asks the same question the guard asks and cannot see the SQL. |
| e | `.frs_near_river_specs()` against the compiler (`frs_habitat_predicates()`) | One resolver (`.frs_rule_near_river()`), the same `.frs_stage_rules()` / `.frs_stage_inherit()` and the same `pred_models`. | Yes. |
| f | `sp_classify` (`any(params_fresh$species_code == sp)`) against `species_params` (`nrow(fp) == 0`) | Two separately written filters, not "the same filter" as `findings.md` says. They disagree only when `params_fresh` has an NA `species_code`: `any(c(FALSE, NA))` is NA, so `sp_classify` drops the species while `species_params` keeps an all-NA row for it. read.csv gives `""`, not NA, for a blank cell, so this is unreachable from the bundled path, and such a row fails on `access_gradient` anyway. Not a finding. | Claimed, but as identical code. They agree on the reachable inputs. |
| g | `pred_models` against `.frs_preds_by_model()` (which models are applied) | Agree for all-cw, all-mad, mixed and an empty table (round 2 checked these). | Implicitly. |
| h | The root: classify's DELETE and INSERTs are not atomic | Unchanged. While it holds, every guard is a list that has to be complete. | Out of scope by the stated tradeoff. It is still the reason (d) costs data. |

## Findings

- **[severity: fragile]** R/frs_near_river.R:234-250 (`.frs_near_river_check()`) and R/frs_habitat_classify.R:202-216 and 318-324. **The pre-write check tests that each measure column is present, not that it is numeric.** The walk compares the column with a number (`WHERE (mad_m3s IS NULL OR mad_m3s < 3)`, `.frs_near_river_walk_sql()`), and Postgres refuses that comparison on a text column. The refusal comes inside `frs_near_river()`, after classify's per-group DELETE.
  - **Reproduced** on a scratch copy at HEAD, with the round-1 fixture (`.nr_tributary()`):
    - `mad_m3s` was altered to `text`.
    - `pg_temp.nr_hab` was seeded with one row.
    - CH had one inheriting rule (`edge_types_explicit = 1000L`) and an inherited rear pair `measure = "discharge"`, on a `cw` group.
    - classify stops with `ERROR: operator does not exist: text < integer ... WHERE (mad_m3s IS NULL OR mad_m3s < 3)`, and `nr_hab` goes from 1 row to 0.
  - **The documented remedy leads there.** `frs_col_join()` types every column it joins from a subquery as `text` (R/frs_col_join.R:85-86), and does the same for a table that its `search_path` lookup misses. The error that `.frs_near_river_check()` raises for a missing column tells the caller to join `mad_m3s` with `frs_col_join()`.
  - **The bundled pipeline is not affected.** `frs_network_segment()` joins the named table, which resolves to `double precision` on the local fwapg. link adds `mad_m3s` as `double precision` itself.
  - **Why it matters on this branch.** The defect existed in 0.41.0 for explicit discharge mappings. #263 extends it to every group whose species inherits a CSV pair with `measure = discharge`, cw groups included, which before this branch never compared `mad_m3s` at all. #262 adds `channel_width` and `stream_order`, which are also checked only for presence.
  - **Fix:** in `.frs_near_river_check()`, read the column classes from the `LIMIT 0` frame it already fetches, and stop unless each size column `is.numeric()` (RPostgres types `text` as character, and `integer` / `double precision` / `numeric` as numeric). Add one test that alters `mad_m3s` to `text` and asserts that the habitat row survives. The other SQL-level preconditions (`FWA_Downstream`, the polygon tables, SRIDs) are environmental, predate this branch, and are not reached by a caller-built table, so I would leave them out.

No other issues found:

- **Blank versus NA in the new CSV columns:** frs_params() is the only reader in `R/`. A logical all-NA column, `""`, whitespace-only cells, a quoted `"NA"` (read.csv gives NA) and DB `''` / NULL are all unset.
- **The warning for unknown `_river_` columns** catches a misspelt name.
- **Partial matching:** no `$` read on a params row is a prefix of a new `_river_` column. The `$` reads are `rear_edge_types`, `rear_gradient_max`, `spawn_connected`, `spawn_edge_types`, `spawn_gradient_max` and `spawn_gradient_min`. `near_river` is read with `[[`.
- **Other post-write stops:** `.frs_near_river_sql()`'s NULL-table stop cannot fire, by (e). `.frs_near_river_normalize()`'s `stopifnot` and the empty or NULL thresholds from a programmatic `params_sp$near_river` all fail in `.frs_near_river_specs()`, before the DELETE.

/Users/airvine/Projects/repo/fresh/planning/active/review-round3.md
