# Task: Connectivity passes join a shared habitat table on `id_segment` alone (#242)

## Context

`frs_habitat(to_habitat = )` writes every watershed-group job into one habitat
table. The post-classification connectivity passes then run per job against that
shared table with only the job's own streams table, joining on `id_segment`
alone. `id_segment` is unique only *within* a watershed group — split segments
get `max(id_segment) + row_number()` per working table (`R/frs_break.R:695`) — so
on NATR the next 5,000 ids already belong to 1,451 MIDR and TAKL segments.

Consequence today, with no error raised: a later group's connectivity pass reads
earlier groups' rows as if they were its own.
`.frs_bucket_connected()` (#240, PR #241) already matches
`(id_segment, watershed_group_code)` on every join and has a test with colliding
rows from another group. This brings the four older passes in line.

**Who is affected:** standalone `fresh` callers accumulating several groups in
one `to_habitat`. `link` is not: it passes a per-WSG working schema's
`streams_habitat`, and already requires `watershed_group_code` on both tables
(it pins fresh v0.44.0, so it runs `.frs_bucket_connected()`).

### Two findings from the plan review that change the shape

**The worst site is worse than "reads other groups".** `R/frs_habitat.R:1884`
has no streams join at all:

```sql
UPDATE <habitat> SET spawning = FALSE
WHERE species_code = 'SK' AND spawning IS TRUE
  AND id_segment NOT IN (SELECT id_segment FROM <this job's qual_tbl>)
```

For a shared `to_habitat` that unconditionally clears the species' `spawning`
across **every previously processed group** — no id collision needed. With the
shipped `parameters_habitat_rules.yaml` (SK and KO carry `requires_connected` on
spawn rules and both have a rear `waterbody_type: L` rule) this is the live path.
It lands first.

**`.frs_cluster_both()`'s phase 3 corrupts its own group too.**
`R/frs_cluster.R:516` is a `LEFT JOIN` on `id_segment` alone, so a colliding row
in another group **multiplies rows** in the `downstream` CTE, and
`SUM(st.length_metre) OVER (PARTITION BY cm.cluster_id …)` at `:505` then
double-counts distance. A cluster inside `bridge_distance` can fall outside it.
So this is not only a cross-group leak — it is a wrong answer for the job's own
group, and it says so in NEWS.

**Reachability.** `inst/extdata/parameters_fresh.csv` ships
`cluster_direction = "both"` for all five clustering species (CH, CO, SK, ST,
WCT) and blank `cluster_spawn_direction`, which also defaults to `both`. So
`frs_habitat()` reaches only `.frs_cluster_both()` and
`.frs_connected_waterbody()`; `.frs_cluster_upstream()`,
`.frs_cluster_downstream()` and `.frs_distance_filter()` are reachable through
direct `frs_cluster()` calls or custom params. All four passes get fixed; the
two live ones go first.

## Approach

Add `AND <h>.watershed_group_code = <s>.watershed_group_code` to every
habitat↔streams join in the four passes, and scope the subtractive / additive
UPDATEs to the groups present in `table` by joining `FROM <table> s` on both
keys — the shape `.frs_bucket_connected()` uses. The column name is hardcoded, as
there; these functions already hardcode `wscode_ltree`, `blue_line_key`,
`watershed_key`, `downstream_route_measure`, `gradient`, `length_metre` and
`linear_feature_id`.

**Temp tables keep carrying `id_segment` alone.** `id_segment` is unique within
`table` however many groups the job spans, so once the UPDATE pins `h` to a row
of `table` on both keys, a `NOT EXISTS` on `id_segment` is already exact. That is
why the reference implementation's `spawn_tbl` carries no group
(`R/frs_habitat.R:1393`), and `qual_tbl` will not either. The one exception is
`tmp_clusters` in `.frs_cluster_both()`, whose rows *are* the UPDATE's join
source, so it does carry the group.

### Do not add the group to any partition, ordering or grouping key

A job's `table` can span groups (custom AOI) and a contiguous reach legitimately
crosses a group boundary, so these are behaviour changes, not fixes, and they are
invisible in a single-group test:

| site | why it must stay as it is |
|---|---|
| `ST_ClusterDBSCAN(…) OVER ()` — `frs_cluster.R:203`, `:285`, `:438`; `frs_habitat.R:1858` | partitioning splits a cross-group cluster, moving which row wins `cluster_minimums` — the fresh#186 class |
| `cluster_minimums`' `DISTINCT ON (cluster_id)` — `frs_cluster.R:215`, `:297`, `:455`, `:492` | would give a cross-group cluster two trace origins |
| `downstream` / `downstream_capped` `PARTITION BY cluster_id` — `frs_cluster.R:326`, `:340`, `:507`, `:523` | already keyed on the cluster |
| `cluster_geoms`' `GROUP BY cluster_id` — `frs_habitat.R:1865` | fragments a cluster's geometry, so one touching the lake only on its other-group end stops qualifying |
| `origins_sql`'s `DISTINCT ON (s2.waterbody_key)` — `frs_habitat.R:1789` | a lake can straddle a group boundary; one outlet per polygon is correct |

### `.frs_cluster_both()`'s `phase1_ids`

Today an R-side `SELECT h.id_segment FROM <habitat> WHERE species_code = sp AND
<label_cluster> IS TRUE AND <label_connect> IS TRUE` (`:429`), inlined into the
UPDATE as `AND h.id_segment NOT IN (<ids>)` (`:564`). That reads every group, so
another group's phase-1 id spuriously protects this group's segment.

It is replaced by `AND h.<label_connect> IS NOT TRUE` in the UPDATE. Every target
row joins a `tmp_clusters` row, `tmp_clusters` holds exactly the habitat rows with
`<label_cluster> IS TRUE`, and the only statements in between are a `CREATE INDEX`
and two SELECTs — so for a target row "phase 1" is exactly
`<label_connect> IS TRUE`. Three constraints the review established:

- **`IS NOT TRUE`, never `= FALSE`.** `phase1_ids` requires `IS TRUE`, so a NULL
  `label_connect` is unprotected today and must stay unprotected.
- **Same commit as the join fix.** On today's unscoped join the two formulations
  genuinely differ, so this is not a standalone refactor.
- It rests on `(id_segment, watershed_group_code, species_code)` being unique in
  the habitat table, which no index enforces — stated as an assumption in the
  commit, and added to the follow-up issue.

## Phases

### Phase 1 — Share the synthetic fixture

- [x] Move `.bkt_fixture()` / `.bkt_seg()` / `.bkt_flags()` from
      `tests/testthat/test-frs_bucket_connected.R` to
      `tests/testthat/helper-synthetic.R` (testthat gives each test file its own
      environment, so a new file cannot see them where they are).
- [x] Add what the new tests need, all defaulted so
      `test-frs_bucket_connected.R` behaves identically: per-row `gradient`,
      per-row `watershed_group_code`, `channel_width`, `edge_type`, and a helper
      to insert a second group's habitat rows.
- [x] `test-frs_bucket_connected.R` still green.

### Phase 2 — `.frs_connected_waterbody()` (live, highest severity)

- [x] Test (`lake_adjacent = FALSE`), red first: TEST lake lines with spawning
      downstream inside `distance_max` keep it, spawning on a sibling tributary
      does not; OTHR rows with `spawning = TRUE` survive — today wiped with no
      collision needed — and an OTHR `rearing = TRUE` collision creates no false
      Phase-1 origin.
- [x] Fix, one commit: the `origins_sql` join (`:1795`), the `rearing_segs` and
      `spawn_upstream` joins (`:1826`, `:1832`), and the subtractive UPDATE
      (`:1884`) rewritten as `FROM <table> s` on both keys plus `NOT EXISTS`
      against `qual_tbl`. Commit notes that `NOT IN` → `NOT EXISTS` drops a
      fail-open NULL escape that nothing relies on (`qual_tbl` is fed only from
      `table`).
- [x] Test + fix for the Phase 3 additive UPDATE (`:1919`), separate commit: an
      OTHR row with `accessible = TRUE, spawning = FALSE` colliding on a traced
      `id_segment` must not be promoted.
- [x] Note the gap: Phase 2's `lake_adjacent = TRUE` cluster gate needs a real
      lake polygon within 2 m, so a synthetic fixture leaves `valid_clusters`
      empty and that branch untested. Pure column-carrying once the table above
      is respected; recorded in `findings.md`, not papered over.

### Phase 3 — `.frs_cluster_both()` (live)

- [ ] Test, red first: the OTHR-survives and OTHR-does-not-rescue pair, plus a
      TEST row with both flags TRUE inside an invalid cluster that must stay
      (the `phase1_ids` replacement), a NULL-`spawning` TEST row in an invalid
      cluster that must go (`IS NOT TRUE` vs `= FALSE`), and a cluster inside
      `bridge_distance` that today falls outside it because the `LEFT JOIN`
      doubles the distance.
- [ ] Fix in one commit: `tmp_clusters` carries the group (`:444`), phase 2's
      join (`:466`), phase 3's `LEFT JOIN` (`:516`), both UPDATE branches
      (`:574`, `:583`), and `phase1_ids` deleted (`:429`, `:563`).
- [ ] With `phase1_protect` gone the two UPDATE branches differ only by the
      cluster clause — collapse them only if it falls out cleanly.

### Phase 4 — `.frs_cluster_upstream()` and `.frs_distance_filter()`

- [ ] `.frs_cluster_upstream()`: test, then `clustering` carries
      `s.watershed_group_code` (`:209`), the `valid_clusters` join (`:233`), the
      UPDATE (`:253`).
- [ ] `.frs_distance_filter()`: test, then the outer UPDATE (`:1532`) and the
      inner `NOT EXISTS` join (`:1537`).

### Phase 5 — `.frs_cluster_downstream()`, and `frs_cluster()`'s surface

- [ ] Its fixture is built from real rows on one small `blue_line_key` of
      `whse_basemapping.fwa_stream_networks_sp`, duplicated as TEST and OTHR,
      `skip_if()` on none: `fwa_downstreamtrace()` (`:330`) iterates the real
      network, so with synthetic `blue_line_key`s every cluster is stripped and
      the "keeps a connected cluster" half of the test would be vacuous.
- [ ] Fix: `clustering` (`:291`), the `has_connect` EXISTS (`:320`, matching the
      streams row's group, not `cm`'s — `cm` has none), the UPDATE (`:372`).
- [ ] `frs_cluster()`'s `species = NULL` resolution (`:130`) reads every group in
      the habitat table; scope it to the groups present in `table`.
- [ ] Roxygen on `frs_cluster()`'s `@param table` / `@param habitat`: both must
      carry `watershed_group_code`, and a shared habitat table holding other
      groups is safe. Same note on `.frs_distance_filter()` and
      `.frs_connected_waterbody()`, as `.frs_bucket_connected()` carries.

### Phase 6 — Prove each guard fires, then wrap up

- [ ] In a copy of the tree (`cp -r` to a temp dir, so nothing races a suite
      run), restore the single-key join in each pass one at a time and record
      which test goes red — a mutation table in `findings.md`, one row per site.
      The two where a synthetic test can pass vacuously
      (`.frs_cluster_downstream()`, `lake_adjacent = TRUE`) are the reason this
      is a phase and not an assumption.
- [ ] `Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`
- [ ] `lintr::lint_package()`, `devtools::document()`
- [ ] `NEWS.md`, then the `DESCRIPTION` bump as the final commit
- [ ] `/code-check branch`, `/planning-archive`, `/gh-pr-push`

## Decided at the gate

Owner, 2026-10-28:

- **`frs_cluster()` gains a hard requirement on `watershed_group_code`**, stated
  in roxygen — not a `col_group` parameter. A `NULL` opt-out would reinstate
  exactly this bug, and in practice the requirement is free: anything reaching
  `frs_cluster()` already needs six other FWA columns, so it came from
  `frs_extract()` / `frs_network_segment()`, which carry it.
- **The adjacent persist-path defect gets its own issue**, not this branch.

Agent's calls, from the review:

- Temp tables other than `tmp_clusters` keep carrying `id_segment` alone, per the
  reference implementation, rather than gaining a redundant group column.
- Verbose before/after counts stay unscoped — they aggregate across every group
  in the habitat table, but they are reporting, not data, and
  `.frs_bucket_connected()` leaves its own counts unscoped. Scoping eight count
  queries would add a scan per call for a cosmetic gain.
- No unique index is added to the habitat DDL in this branch; the duplicate-row
  hazard it would close is a pre-existing one for every join here, and it goes in
  the follow-up issue.

## Owed at the end (reported, done after merge)

- [ ] One follow-up issue for the same defect class outside the connectivity
      passes, with three parts: the custom-AOI persist delete
      (`DELETE FROM <to_streams> WHERE id_segment IN (SELECT id_segment FROM
      <streams_tbl>)`, `R/frs_habitat.R:515` and `:675` — data loss from a
      persisted table); the exported `frs_habitat_overlay()`'s bridged join
      (`h.id_segment = s.id_segment`, `R/frs_habitat_overlay.R:251`, feeding an
      additive UPDATE); and whether the habitat table should carry a unique index
      on `(id_segment, watershed_group_code, species_code)`.

## Validation

- [ ] Tests pass
- [ ] `/code-check branch` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved. Per pass: OTHR's colliding rows are bit-identical
before and after; OTHR's flags neither rescue nor condemn TEST's; **both** an
expected keep and an expected strip are asserted on TEST, so neither a no-op nor
a strip-everything mutant passes; and Phase 6 records the mutation that turns
each test red. The existing integration test at `test-frs_cluster.R:148` asserts
only `n_after <= n_before`, so it is not treated as cover. The whole suite runs
against the local fwapg before the PR.
