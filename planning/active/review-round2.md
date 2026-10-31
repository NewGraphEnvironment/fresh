# Code-check round 2: #274 branch (bef83b1, 18452a4 and the rest of the branch vs origin/main)

## Checklist read

- code-check.md: the prose of all 14 H3s under `## Mechanisms`, with table rows and evidence skipped.
  Of the stand-alone rules, read only the index lines (none of them fits this diff).
- code-check-r.md (190 KB): read these headings in full: "Tests that silently do not run";
  "testthat counts an uncaught error under `error`, not `failed`"; "A database driver's value is
  not a base R type"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED
  package"; "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words"; "Verify a
  float-formatting fix in its consumer, not through `as.numeric()`"; "A `function(...)` mock hides
  arguments the real callee no longer accepts"; "A value compared as `::text` in SQL has
  PostgreSQL's spelling"; "Postgres row order is never fixed unless the query fixes it". That is 9
  read; the other ~110 were not read, because their index lines name tools this diff does not use.
- code-check-infra.md (41,794 bytes, just over the in-full threshold): read from the index only.
  No heading names a tool or pattern in this diff (no timeouts or DDL; Postgres appears only as SQL
  text). 0 sections read.
- code-check-shell.md, code-check-spatial.md: index only. The diff has no shell, sed or git
  scripting and no sf/terra/GDAL. 0 sections read.

## What was checked

1. **Enumerated every route-measure interpolation in R/** (grep of
   `route_measure ... %s` and `measure.*%s`).
   - All 8 `downstream_route_measure <= %s` segment picks in frs_network.R now go through
     `.frs_sql_exact()`: direct ×3, waterbody ×3, frs_check_upstream ×2.
   - So do the single picks in frs_network_upstream.R, frs_network_downstream.R,
     frs_network_prune.R and frs_waterbody_network.R, and `fwa_locatealong()` in
     frs_point_locate.R.
   - `.frs_watershedatmeasure_sql()` already used the helper.
   - Remaining `%s` sites:
     - frs_order_child.R:249, frs_cluster.R:261/503 and frs_habitat.R:1555 are distance or
       threshold values (`.frs_sql_num()` or column refs), not positions.
     - frs_wsg_drainage.R:102 is the accepted tradeoff.
   - No traversal measure is left on `%s`.
2. **Callers.** Nothing in R/ calls frs_network_upstream, frs_network_downstream,
   frs_network_prune, frs_waterbody_network or frs_point_locate. frs_network calls
   frs_check_upstream, frs_network_direct and frs_network_waterbody with a measure it has already
   checked to be numeric, length 1 and not NA.
   - Outside this repo: breaks/R/app_server.R:65 passes `snap$downstream_route_measure[1]`
     (numeric scalar). The data-raw scripts and the vignettes pass numeric literals. link has no
     calls.
   - What now errors in R and used to reach the DB: NA, Inf, vectors, and character measures (the
     4 unvalidated functions used to splice `"166030"` as text). None of these comes from a known
     caller, and the intended-behaviour note covers them.
3. **Can the new tests fail?** I copied HEAD into a scratch dir, restored origin/main's 6 R files
   in a second copy, and ran `testthat::test_file()` with NOT_CRAN=true, counting failures and
   errors.
   - Old code: every new precision test goes red. frs_network: 6 failures across its 6 table and
     upstream combinations; upstream, downstream, prune and waterbody: 1 failure each; point_locate:
     1 failure and 1 error.
   - New code: all green. The full files (frs_point_locate, frs_network, frs_network_upstream,
     frs_network_downstream, frs_network_prune, frs_waterbody_network, utils) have 0 failures and
     0 errors. The gate file skips 3 (no trial set).
   - The frs_network test reaches all 8 picks in frs_network.R: the up = NULL case gives 1 pick,
     and the upstream case gives check_upstream's 2 plus the builder's 2, expected as m, um, m, um.
4. **Read-only DB probes** (local fwapg):
   - The (blue_line_key, downstream_route_measure) pair is unique over fwa_stream_networks_sp
     (0 duplicates), so the `ORDER BY ... DESC LIMIT 1` picks are deterministic.
   - `fwa_locatealong` takes `(integer, double precision)`, so the `%d` and the 17-digit literal
     bind as intended.
   - Head blue line 360447231: its top is `1528.8506958829107`. The `%.17g` literal `::float8`
     equals the stored maximum; the `%s` form does not. `skip_unless_head_case()` still sees
     closed = 1 at full precision, and the stale function returns 0 rows at either precision (the
     red side holds).
5. **Research note.** The `format(scientific = FALSE)` claim checks out: with the sweep's mixed
   vector, `4494.61997946051` goes out as `4494.620`. No other text outside planning/ still says
   frs_point_locate or the traversals send 15 digits.

Not a finding, because the diff leaves it as it was: `frs_network(to =, overwrite = TRUE)` drops
the destination tables before it validates finiteness. A non-finite measure used to fail at the DB
after the DROP; it now fails at `.frs_sql_exact()` after the DROP. Same order, same outcome.

## Clean
No issues found.
