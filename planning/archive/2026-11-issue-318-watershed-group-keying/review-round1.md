# Code-check review, round 1: branch 318 (#294, #308, #277)

Reviewed `branch.diff` (origin/main merge-base a00ad5d..HEAD bdbcb11) in full, plus the full
current text of R/utils.R (persist helpers, guards), R/frs_habitat.R (both job paths,
`.frs_enrich_breaks()`), R/frs_cluster.R, R/frs_order_child.R, R/frs_habitat_overlay.R,
R/frs_habitat_classify.R, R/frs_near_river.R, R/frs_break.R (multiclass finder), the changed
tests, data-raw/barrier_span_294.R and its logs, research/id_segment_identity.md and CLAUDE.md.

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (tables and evidence skipped).
  Not read: the 15 "Rules that stand alone", 6 Security and 4 Spreadsheets/PDF headings (25).
- code-check-r.md: read in full "A `data-raw/` script must load the source tree, not the installed
  package"; "Postgres row order is never fixed unless the query fixes it, ..."; "A database
  driver's value is not a base R type — and it fails twice"; "`deparse(body(f))` excludes formal
  defaults, so a body scan cannot see a default"; "A `function(...)` mock hides arguments the real
  callee no longer accepts"; "An `information_schema` lookup by the literal table name misses what
  Postgres resolves"; "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later
  one"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED package" (8). The
  other ~140 headings were judged from their index lines only.
- code-check-spatial.md: read in full "FWA `upstream_route_measure` misses the next segment's
  start" and "FWA main flow is not edge type 1000 alone" (2); the rest from index lines only.
- code-check-shell.md: index lines only (the diff has no shell).

## Verification run

- `devtools::test(filter = "persist_barriers_294|frs_habitat_overlay|frs_cluster|frs_order_child|habitat_partition_293|frs_near_river")`
  on the local Docker fwapg: FAIL 0, SKIP 0, PASS 349.
- `devtools::test(filter = "^frs_habitat$")`: FAIL 0, SKIP 0, PASS 91 (includes the to_barriers
  integration test).
- Walked the namespace call graph myself: every exported function reaching `.frs_key_match`,
  `.frs_near_river_sql` or `.frs_lfid_pair` reaches `.frs_group_required`, except the exempt
  `frs_habitat_predicates`; `.frs_run_connectivity` is called only from `frs_habitat`.
- Timed `.frs_group_required`'s query on the persisted `fresh.streams` (5.3M rows): 1-6 ms,
  because the table has a `watershed_group_code` index and a primary key on it. Not a concern.

## Findings

- **[severity: bug]** R/frs_habitat.R:1068 (`.frs_enrich_breaks()`, join top) with
  R/utils.R:1786 / the `owned` INSERT filter in `.frs_persist_barriers()` — a barrier that
  falls in FWA's sub-centimetre gap between one segment's `upstream_route_measure` and the next
  segment's `downstream_route_measure` matches no segment, gets NULL `linear_feature_id`, and is
  now silently left out of `to_barriers`. The old code persisted every row of `grad_tbl`. The
  gap is not rare: the finder rounds a segment's first vertex to 0.01 m
  (`ROUND(... ::numeric, 2)` in `frs_break.R`), and that rounding can push it below its own
  segment's start and into the gap.
  - Measured on the local fwapg with `frs_break_find()` + `.frs_enrich_breaks(parent = TRUE)`,
    classes 0.05 to 0.30: BULK 39 of 104,550 barriers unmatched, MORR 27 of 68,270, LFRA 41 of
    52,430. Example: blk 360404194, barrier at 148.18, between segment 17065309 (`u` =
    148.17940) and 17065119 (`d` = 148.18001). Over all mainstem boundaries, 57,895 of 2.95M are
    ones where a rounded segment start lands in the gap (max gap 7.7 mm).
  - research/id_segment_identity.md:205 says "0 of the sample's barriers fell outside every
    segment". That is the 12-line sample in `data-raw/barrier_span_294.R`, which would expect
    about 0.1 at these rates, so the zero does not show the case is absent. The roxygen sentence
    "A barrier no segment contains has none and is not written" describes the drop as harmless,
    but nobody measured how many barriers it covers.
  - Remedy per the rule: take each segment's top from the next segment's
    `downstream_route_measure` on the same blue line (`lead()`), or from
    `downstream_route_measure + length_metre`, in the `parent = TRUE` join (the ltree columns
    would benefit too). The gap barriers then key to the segment just below, which is the
    accepted neighbour rule, nearly always in the same group.
  - **Rule:** code-check-spatial.md "FWA `upstream_route_measure` misses the next segment's start" ; code-check.md "A fixture that cannot reach the failure mode"

- **[severity: fragile]** tests/testthat/test-frs_habitat_overlay.R:273-274 — the "Upper case
  folds to the same column" assertion never reaches the new #277 guard. `by = "ID_SEGMENT"` is
  refused earlier by the `from` required-columns check (R/frs_habitat_overlay.R, `required <-
  c(by, ...)` against lower-case `from_cols`). Probed with the test's own `.ov_direct()` helper:
  it returns `ERROR: \`from\` table ws.k missing required columns: ID_SEGMENT`. So
  `expect_match(..., "^ERROR:")` stays green with the guard or its `tolower()` (line 247)
  deleted. In practice the `tolower()` arm cannot be reached, so production behaviour is still
  correct. The test only claims coverage it does not have. Match the guard's own message, or drop
  the case.
  - **Rule:** code-check.md "Restore the bug and prove the guard fires" ; code-check.md "A fixture that cannot reach the failure mode"

## Considered, not findings

- Direct-mode #277 lets `by = c("id_segment", "watershed_group_code")` through when `to` carries
  `linear_feature_id` and `from` does not, so two jobs' rows sharing a derived `id_segment` in one
  group would both be updated. The plan states this rule ("when both carry it"), and it matches
  what the bridged path adds via `.frs_lfid_pair()`. Left as a design choice.
- Both `frs_habitat()` job paths (sequential and mirai) were changed identically, and
  test-frs_habitat.R pins both.
- `.frs_persist_columns()` ALTERs an old target before the NULL-key guard refuses it. This is the
  same pattern as `.frs_persist_streams()`, and the refusal repeats on re-run.
- Concurrent `CREATE TABLE IF NOT EXISTS ... AS` from mirai workers on a brand-new target is
  unchanged from the old code.
