# fresh#293 — code-check round 5

Reviewed at `c1d0440` (HEAD at review start: `9228607` plus one `progress.md` commit; no
`R/` or `tests/` change between them). Nothing in the working tree was edited apart from
this file. Probes and mutations ran in `git archive` copies under the session scratchpad.

**Read this first: my test runs may have touched the running sweep.** The brief said every
test's tables are session temp tables. One is not: `test-habitat_partition_293.R`'s
"a custom-AOI classify keeps the group's rows for ground outside the AOI" (`:156`) writes
fixed-name persistent tables, `working.p293_*` and `working.streams_p293{a,b,c}`, and
DROPs them on entry and exit. I ran that file three times between **18:16:26Z and about
18:20:00Z** (one with a mutation, two clean). The first run's copy of that test **errored**
while the unmutated second run passed it, which is what a collision with another session
looks like. The sweep (started 18:09:39Z, filter includes `habitat_partition_293`) runs
the same test in every variant, so any variant that executed it in that window may have
been perturbed, and a spurious red there would credit a guard it should not. Re-run the
variants that overlap that window. After seeing this I ran only `test-frs_connectivity_wsg.R`
and `test-frs_bucket_connected.R`, which use `pg_temp` alone.

## Checklist read

- `code-check-infra.md` — in full (Cloud-Init, OpenTofu, DigitalOcean, Docker/Postgres,
  Tailscale, every evidence block). Applicable: "Two-statement DELETE/INSERT into a persist
  table is not atomic", "Joining on a per-tenant key … is cartesian", "Set
  `statement_timeout` + `lock_timeout` on long DB ops" (incl. the `IF NOT EXISTS` lock
  paragraph, for the new `CREATE INDEX` in `.frs_habitat_target()`), "View vs. real table".
- `code-check.md` — `## Mechanisms`: the prose of all 14 H3s, with `|` table rows and
  `<!-- evidence -->` blocks skipped. From `## Rules that stand alone`: "Documentation
  Staleness". Not read: the other 13 standalone rules, Security (6), Spreadsheets/PDFs (4),
  from the index only.
- `code-check-r.md` — by heading: "Under `R CMD check`, tests run from a temp dir against
  the INSTALLED package", "`deparse(body(f))` excludes formal defaults", "Tests that silently
  do not run", "A `function(...)` mock hides arguments the real callee no longer accepts".
  About 140 other headings from the index only.
- `code-check-shell.md` — index only (0 headings opened); the diff carries no shell.
- `code-check-spatial.md` — index only (0 headings opened); no sf/terra/GDAL in the diff.

## Round 4's findings, checked in the code rather than the records

| R4 finding | state at `c1d0440` |
|---|---|
| 1. `near_river_lfid` required | **fixed in `R/`**: `frs_habitat_predicates.R:169-178` takes `NULL` and errors when a table is given without it; the test is at `test-habitat_partition_293.R:68` |
| 2. three call sites | **fixed**: `test-near_river_inherit.R:299-304` passes the flag. `test-near_river_rules.R:226` calls the internal `.frs_rule_to_sql()`, which still defaults to `FALSE`, so it is unaffected. `data-raw/predicates_fixture_0410.R:28` left as-is, which is correct. **But the population was incomplete. See Finding 1.** |
| 3. `on.exit` comment | **fixed**: `frs_near_river.R:205-225` now states the measured mechanism |
| 4. `try()` on the walk DROP | **fixed**: `frs_near_river.R:157`. Mutation-proved here: with `try()` removed, "a near_river failure in a caller's transaction raises its own error" errors with `current transaction is aborted` (red); restored, it passes |
| 5. stale counts | **fixed**: `findings.md:159` says 20, and `research/id_segment_identity.md:125-126` says 221/114, both matching `summary.csv` |

## Findings

- **[severity: bug]** `R/frs_habitat_predicates.R:157-158` and `:165-166` (rendered at
  `man/frs_habitat_predicates.Rd`, `\examples`). **Both `near_river` examples call
  `frs_habitat_predicates(sp_params, near_river_table = "working.streams_habitat_near_river")`
  without `near_river_lfid`, which has been an error since 142b34d.** Reproduced by
  extracting the Rd's examples (`tools::Rd2ex`) and sourcing them against the branch:
  `Error: near_river_lfid must be given with near_river_table: …`. The block has no
  `\dontrun`, so `R CMD check` fails at "checking examples" (the branch's R-CMD-check workflow)
  and pkgdown's reference build hits the same error. Round 4's enumeration of call sites
  parsed `.R` files only. Roxygen `@examples` are comments to `parse()`, so the one caller
  every user copies was outside its population. The fix is to pass `near_river_lfid = TRUE`
  in both calls (the examples' comments describe a fresh 0.54 table). Re-run
  `devtools::check()` (or `devtools::run_examples()`) before the PR, since no test sees this.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness" ; code-check.md "A proxy is not the property"

- **[severity: fragile]** `R/utils.R:1576-1582` (`.frs_key_match()`),
  `tests/testthat/helper-synthetic.R:31,46-47,105-110`,
  `tests/testthat/test-frs_connectivity_wsg.R:727-732`. **The branch moved every fresh#242
  fixture onto the parent-segment path, and no test can now see the watershed-group arm of
  the habitat join.** `bkt_streams` and `bkt_habitat` both carry `linear_feature_id`, so
  `.frs_lfid_pair()` is `TRUE` in every synthetic fixture. The cross-group decoy
  (`wsg = "OTHR"`, `linear_feature_id` negated) then differs from its target in **both** the
  group and the parent, and either arm alone excludes it. Measured: with
  `"watershed_group_code"` deleted from `.frs_key_match()`'s `parts` (mutant output
  `h.id_segment = s.id_segment AND h.linear_feature_id = s.linear_feature_id`),
  `test-frs_connectivity_wsg.R` passes 16/16 and `test-frs_bucket_connected.R` 16/16, with
  0 skipped. Before the branch, those same tests were the guard on that arm. On the FWA path the arm is
  redundant (no `linear_feature_id` spans a group). On the `lfid = FALSE` path (a network
  that is not the FWA, which `.frs_persist_delete_key()` and the classify test at
  `test-habitat_partition_293.R:261` support) it is the **only** thing that separates two groups'
  colliding `id_segment`s, i.e. fresh#218/#242. A refactor that drops it now ships green.
  The test comment at `:731-732`, *"the first one attributes the group arm on its own"*, is
  false as measured. No sweep row mutates this arm either.
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode" ; code-check.md "Restore the bug and prove the guard fires"

- **[severity: fragile]** `R/utils.R:1486-1488` (`.frs_group_required()` roxygen), with
  `R/frs_cluster.R:146-156`, every `.frs_key_match()` read, and `R/utils.R:567-568`
  (`.frs_near_river_sql()`). **The guard refuses a NULL watershed group on the
  parent-segment path because every read equates the group, then asserts the
  `id_segment`-only path is "unaffected … the group plays no part". It is not.** On that path
  `.frs_key_match(..., FALSE)` still emits `h.watershed_group_code = s.watershed_group_code`.
  The `near_river` EXISTS still equates `n.watershed_group_code = s.watershed_group_code`, and
  `frs_cluster(species = NULL)` resolves species through `s.watershed_group_code =
  h.watershed_group_code` (`part_col`). A NULL-group row on a network that is not the FWA is
  therefore written (the delete and insert now address it, which closes #225) and then never
  read. Its `near_river` rule fails silently, the connectivity passes neither clear nor rescue
  it, and `frs_cluster(species = NULL)` gets an empty species list and does nothing. This is
  the exact condition `.frs_group_required()` was written to refuse, scoped to one of the
  two branches it reaches. The read-side equality predates the branch. What the branch adds
  is the claim that this case is handled, in the guard's roxygen and in 20e59e4's subject
  ("a NULL watershed group is now addressable"). Either extend the refusal to
  `lfid = FALSE` whenever any read path will run, or correct the sentence and leave #225
  open for the reads.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** link#452's body (NewGraphEnvironment/link, open) reads *"fresh's
  own predicate takes `near_river_lfid` (default `FALSE`, so the old text is unchanged)"*.
  Since 142b34d it is required, so link's `.lnk_hv_stage_exprs()`
  (`R/lnk_habitat_validate.R:1092-1093`, `:1105-1106`, both
  `fresh::frs_habitat_predicates(..., near_river_table = near_river_table)` without the flag)
  **errors** at the next fresh pin bump, rather than reading the shorter key as the body
  says. `NEWS.md:16` states the requirement correctly; the peer issue that will drive the
  link change states the opposite. Edit the body when this merges (the
  `/gh-pr-merge` 3b moment). Nothing breaks today: link pins `fresh@v0.52.0`.
  - **Rule:** code-check.md "Written data outlives the fix"

- **[severity: fragile]** `R/frs_habitat_predicates.R:178`. `near_river_lfid <-
  isTRUE(near_river_lfid)` runs after a guard that checks only `is.null()`. So
  `near_river_lfid = NA` and `"TRUE"` silently become `FALSE`, which is the 0.53.0 short key the
  guard exists to stop a caller getting by accident. `.frs_key_match()` validates the same
  flag strictly (`stopifnot(is.logical(lfid), length(lfid) == 1, !is.na(lfid))`), so one
  policy is applied two ways. A `tgt$lfid`-style value read from a list that lacks the field
  is `NULL` and caught, but an `NA` from a failed lookup is not.
  - **Rule:** code-check.md "A guard that fails toward pass"

## Mechanism

**Each enumeration was taken over the population its instrument could reach, not the one
the property quantifies over, and then reported as complete.** The population was set by
the tool, and nothing then checked it against the claim. Every round's misses are one
instance of it:

| round | instrument | population it reached | the claim's population | what sat outside |
|---|---|---|---|---|
| R1 | literal grep `"id_segment = s.id_segment"` | one alias order | every habitat join | three alias-reversed joins |
| R3 | `.frs_key_match()` convergence | one builder | every implementation of the predicate | `.frs_near_river_sql()` |
| R4 | `parse()` of `R/`, `tests/`, `data-raw/` | code in `.R` files | every caller of the exported function | roxygen `@examples` (Finding 1), link's validator (Finding 4) |
| R5 | test 2: argument at each call is symbol `lfid` | the call's argument | that the arm reflects the tables | how `lfid` is bound (correct today, unchecked) |
| R5 | the fresh#242 tests | fixtures, all `lfid = TRUE` | both arms of the key | the group arm on the `lfid = FALSE` path (Finding 2) |
| R5 | `.frs_group_required()` | the parent-segment branch | every path whose reads equate the group | the `id_segment` branch (Finding 3) |

Where the mechanism reaches beyond these findings:
- **The key policy is still written out in two forms.** The count and species-list scope
  is `if (lfid) "linear_feature_id" else "watershed_group_code"`, inline at 5 sites
  (`frs_cluster.R:147`, `frs_habitat.R:1370`, `:1526`, `:1796`, `frs_order_child.R:295`).
  Classify uses `tgt$key`, which can be `"id_segment"`. On a network that is not the FWA the
  two disagree: the inline copy counts by group. That only affects verbose counts and the
  over-inclusive species list, apart from the NULL-group case in Finding 3.
- **Internal defaults vs. the exported rule.** `.frs_near_river_sql(lfid = FALSE)`,
  `.frs_rule_to_sql(near_river_lfid = FALSE)` and `.frs_rules_to_sql(near_river_lfid = FALSE)`
  keep the default the exported function now forbids, and `utils.R:559-560` still argues for
  it (*"a caller that does not pass it is unaffected"*). There is one internal caller per
  function and both R/ sites pass the flag, so nothing is wrong today. The two documents give
  opposite answers to one question.
- **Prose restatements of the read key outside the diff.** `frs_network_segment.R:98-99`
  (rendered example) still says `(id_segment, watershed_group_code)` links habitat back to
  streams. Round 3 cleared it on the unique index of `fresh.streams`, so it is not re-flagged
  here. `CLAUDE.md:98` ("joined to geometry via `id_segment`") predates the branch.

## Enumeration

**A. Test 1, "no habitat-to-streams join is left spelled inline".** Its question: literal
`<a>.id_segment = <b>.id_segment` in deparsed namespace functions.
- All string literals in the namespace containing `id_segment`, by AST walk of bodies and
  formals: **53 literals in 24 functions.** Equalities of two relations on `id_segment`: 8.
  - 6 match the regex and are the allowlist exactly (`frs_habitat_classify` 1,
    `.frs_bucket_connected` 2, `.frs_connected_waterbody` 2, `.frs_near_river_sql` 1). Each is
    a streams-side or temp-table join, or the conditional near_river arm. **Correct.**
  - 2 the regex cannot see (`o.id_segment = p.origin_id` in `.frs_bucket_connected`,
    `s.id_segment = w.origin_id` in `frs_near_river`). Both join streams to a walk table,
    not habitat. **Correct.**
- Every SQL `sprintf()` in the namespace with a habitat-like table among its arguments
  (`habitat`, `near_river_table`, or `to` in classify, overlay or target): **62.**
  - 30 are error messages, 4 DDL/ANALYZE, 1 a whole-table species list (overlay), and 1 a
    streams-side INSERT (classify).
  - **15 match through `.frs_key_match()`.** **Correct.**
  - 1 is the `near_river` EXISTS with the conditional parent arm. **Correct.**
  - **10 are single-key semijoins through the inline `part` policy** (9 counts, plus
    `frs_cluster`'s species list). **Correct on the FWA path.** On `lfid = FALSE` they scope
    by group. Finding 3 for NULL groups; Mechanism for the policy copy.
- Plus 2 deletes built by `.frs_persist_delete_sql()` (classify, near_river). **Correct.**
- Verdict: the test's question is narrower than its property. It cannot see a key spelled
  from parts or a single-column semijoin, and 12 of the 32 habitat-row matchers are of those
  kinds. All 32 are correct on the FWA path. None sits above its source there. On the
  `lfid = FALSE` path, 11 equate a group a NULL row cannot match (Finding 3).

**B. Test 2, "no habitat key is built with the parent segment switched off".** Its
question: the 3rd/`lfid` argument of each `.frs_key_match()` call is the symbol `lfid` or
a `.frs_lfid_pair()` call.
- Calls: **19 in 8 functions** (`.frs_bucket_connected` 1, `.frs_cluster_both` 4,
  `.frs_cluster_downstream` 3, `.frs_cluster_upstream` 3, `.frs_connected_waterbody` 4,
  `.frs_distance_filter` 2, `frs_habitat_overlay` 1, `frs_order_child` 1). This matches the
  test's pinned 19.
- Binding of `lfid`, which the test asserts in a comment and does not check: in 7 functions
  `lfid` is assigned **exactly once**, from `.frs_lfid_pair(conn, habitat, table)`. In
  overlay it is written in place, `.frs_lfid_pair(conn, to, bridge)`. It is a formal in none.
  **All 19 correct.**
- Verdict: correct today. The test cannot see a `lfid <- FALSE` or a swapped-table
  `.frs_lfid_pair()` binding, and it says nothing of the **group** arm (Finding 2).

**C. Callers of the predicate builders.** Parsed `R/`, `tests/testthat/`, `data-raw/`, `dev/`,
every `man/*.Rd` example (via `tools::Rd2ex`) and the vignettes (purled, plus a grep: no use).
**139 call sites** of `frs_habitat_predicates`, `.frs_rule_to_sql`, `.frs_rules_to_sql` and
`.frs_near_river_sql`. 41 pass a table, 32 of them with the flag. Of the 9 without:
- 1 is `data-raw/predicates_fixture_0410.R`, which must stay.
- 1 is the deliberate `expect_error` at `test-habitat_partition_293.R:86`.
- 5 are tests of internal functions whose default is `FALSE`. Intended.
- **2 are `man/frs_habitat_predicates.Rd` examples. Bug, Finding 1.**

**D. Public-repo text.** No host names, ports, tunnels or tailnet details were added. Two
references to machine-local or internal tooling were added: `review-round4.md:6` names an
absolute home-directory path to a sibling worktree, and `findings.md:5` names the internal
`db-newgraph` MCP. Archived planning files already carry home paths throughout, so this
follows existing practice. Recorded here, not flagged.
