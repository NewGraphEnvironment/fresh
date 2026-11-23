# Code-check round 2 for #319 (branch vs merge-base f3e331d)

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (table rows and evidence blocks skipped), plus "An assertion that matches an interpolated value cannot see the claim around it". The other standalone, Security and Spreadsheet/PDF headings name no tool or shape this diff uses: 22 not read.
- code-check-r.md: read "A database driver's value is not a base R type — and it fails twice", "R's `yaml` returns a mixed int/float sequence as a list, not a numeric vector", "A `function(...)` mock hides arguments the real callee no longer accepts", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "Tests that silently do not run", "A library call that dispatches on a global option is not a pure function", "`$` on a list partial-matches, so a longer sibling key answers for a missing one", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words, which Postgres reads as column names", "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it" (9 read). The other 145 not read.
- code-check-shell.md: 0 read. The diff has no shell, sed, git or `gh` code (73 not read).
- code-check-spatial.md: 0 read. The diff has no sf, terra, bcdata or GDAL code; the FWA headings are about measures and edge types, which the diff does not touch (96 not read).

## Clean

No issues found.

What I checked and ran (worktree `wt_r2`, restored after):

- **#251 against link:** loaded all four link `inst/extdata/configs/*/rules.yaml` through the branch loader. `cluster_spawning` is TRUE only for SK (bcfishpass) and SK/KO (default*). In every config the first L/W rear rule for those species declares `lake_ha_min: 200`, so `.frs_connected_waterbody()` gets the same floor as before. link names `fresh:::.frs_connected_waterbody` only in roxygen, so its new `NULL` default reaches no link call.
- **#222 finite ranges:** no `.inf`, `Inf` or `.nan` bound in any link YAML or in fresh's `inst/`. link's `lnk_rules_build()` writes `c(0, 9999)` / `c(0, g)` ranges and stops on an NA `g`.
- **#239 `.frs_query_col_types()`:** `LIMIT 0` stops the executor before it reads the subplan. `sprintf()` takes `from` as an argument, so a `%` in a subquery is safe. A missing column errors before any `ALTER`. A `format_type(oid, NULL)` gives `character` for `bpchar`, so a `char(n)` column read from a subquery would come out as `char(1)`. That matches what the old `information_schema` path did for a table source, and the live database has no `char(n)` column outside `tiger`, so it is not reported.
- **`.frs_habitat_target()` migration:** the flag `ALTER` runs only for a missing column, and runs before classify's `dbBegin()`. Concurrent mirai workers serialise on a no-op `ADD COLUMN IF NOT EXISTS`, which waits but cannot deadlock. The `INSERT` lists its columns, so the order of added columns does not matter.
- **#250:** `.frs_bucket_connected()` and `frs_habitat_overlay()` read the flags, not the polygon tables. The only remaining lakes-only reader is `frs_habitat_species()` (#330).
- **Tests, run with `NOT_CRAN=true`:** test-frs_col_join.R 10/10, test-frs_habitat_predicates.R 38/38, test-frs_params.R 98 with 2 skips (bcfishpass schema). Putting `yaml::read_yaml(path)` back turned both #267 tests red (3 failures and 1).
