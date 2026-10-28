# Progress — Connectivity passes join a shared habitat table on id_segment alone (#242)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user
- Plan review (Plan subagent, synchronous) enumerated the full site list, found
  two things that changed the plan's shape: `R/frs_habitat.R:1884` has no group
  scope at all (so it clears other groups with no id collision needed), and
  `R/frs_cluster.R:516`'s `LEFT JOIN` multiplies rows, double-counting distance
  within the job's own group. Both verified against the source before adoption.
- Created branch `242-connectivity-passes-join-a-shared-habita` off main
- Scaffolded PWF baseline from issue #242 with approved phases
- Next: Phase 1 — move the synthetic fixture to `helper-synthetic.R`

### Phase 1 — synthetic fixture shared (done)

- `tests/testthat/helper-synthetic.R`: `.bkt_seg()` gains `gradient`, `rear`,
  `access`, `cw`, `edge`; `.bkt_fixture()` gains `wsg` and `species_other` and
  writes `channel_width` / `edge_type`; new `.bkt_habitat_add()` inserts a second
  group's colliding habitat rows; `.bkt_flags()` takes `wsg`.
- The flag gating is preserved exactly: `spawning` and `rearing` only on the
  fixture's own species, `accessible` and the two bucket flags on every species.
  Gating the buckets by species instead would have made
  "wetland filter leaves lake_rearing and other species alone" unable to fail.
- `test-frs_bucket_connected.R`: 26 pass, 0 fail, 0 skip — unchanged.

### Phase 2 — `.frs_connected_waterbody()` (done)

- `tests/testthat/test-frs_connectivity_wsg.R`: three tests, all red first, and
  red on exactly the cross-group assertions — the within-TEST keep/strip
  assertions passed before the fix, which is how the fixture is known to reach
  the code paths rather than no-op.
- Fixed: `origins_sql`, `rearing_segs` and `spawn_upstream` joins; the
  subtractive UPDATE rewritten with `FROM <table> s` on both keys; the Phase 3
  additive UPDATE.
- Landed as one commit rather than the planned two: the additive and subtractive
  fixes share one test file and one roxygen note, so splitting them would have
  left a commit whose tests do not pass.
- Settled a fixture question by probing rather than reading docs:
  `fwa_upstream(a, a, b, b)` is TRUE whenever `b <@ a`, **equality included**
  (`pg_get_functiondef`, and a truth-table query). So every `wscode = "100"`
  segment counts as upstream of every other, and a segment that must be
  strippable has to sit on a separate river (`wscode = "200"`).
- Gap recorded, not papered over: Phase 2 with `lake_adjacent = TRUE` needs a
  real lake polygon within 2 m of the cluster, so on a synthetic network
  `valid_clusters` is always empty and that branch is untested. Once the
  do-not-touch table in `task_plan.md` is respected the change there is pure
  join-predicate work, but the test does not cover it.

### Phase 3 — `.frs_cluster_both()` (done)

- Two tests, both red first on their discriminating assertions.
- `phase1_ids` replaced by `h.<label_connect> IS NOT TRUE` as planned, in the
  same commit as the join fix. The two fixture assertions that pin the
  equivalence — an on-spawning segment in an invalid cluster stays, a
  NULL-`spawning` segment in one does not — passed both before and after, which
  is what "equivalent" is supposed to look like.
- The two UPDATE branches collapsed into one with a conditional valid-cluster
  clause; with `phase1_protect` gone that was all that separated them.
- Probed rather than assumed, both load-bearing for the fixture: the 8-arg
  `fwa_upstream()` does **not** treat a segment as upstream of itself (so an
  isolated rear+spawn segment really does sit in an invalid cluster, which is
  what makes the phase-1 assertion able to fail), and `subpath('300', 0, -1)`
  is the empty ltree, of which every ltree is a descendant — so a cluster
  minimum below `confluence_m` can be validated by spawning on an unrelated
  river. Every cluster minimum in the fixture sits at drm >= 1000 for that
  reason.

### Phase 4 — `.frs_cluster_upstream()` and `.frs_distance_filter()` (done)

- Three tests, four red assertions before the fix.
- Each pass needed **two** fixtures rather than one, because the two directions
  mask each other: where another group's row rescues a cluster, nothing is
  stripped, so "the other group's rows survived" passes for the wrong reason.
  The rescue case and the survival case therefore get separate fixtures.

### Phase 5 — `.frs_cluster_downstream()` and `frs_cluster()`'s surface (done)

- The fixture is built from real `fwa_stream_networks_sp` rows, discovered at
  run time rather than hardcoded, because this pass traces the real network.
- Two things went wrong on the way, both caught because a skip and a pass are
  indistinguishable in a summary line:
  1. The first discovery query required two streams with **different level-3
     wscode prefixes**, and both tests skipped. The predicate was wrong, not the
     database: what matters is that neither wscode is an ltree **ancestor** of
     the other, since a downstream trace follows the wscode hierarchy. Siblings
     under one sub-basin are exactly what the test wants. Rewritten as a
     self-join on `NOT a.wscode_ltree <@ b.wscode_ltree` both ways.
  2. Real FWA geometry is LineStringZM and the shared table is 2D, so the insert
     raised `Geometry has Z dimension but column does not`. Fixed with
     `ST_Force2D()` on insert rather than by widening the shared DDL, which the
     synthetic fixtures depend on.
- `bridge_gradient = 1` in these tests, so real gradients cannot invalidate a
  cluster through the barrier check — a different behaviour, not the one here.
- 79 pass, 0 skip across the three connectivity test files.

### Phase 6 — mutation sweep and code-check round 1

- Mutation sweep: 19 sites, 15 pinned by a named test, 4 unobservable by
  construction. The table and the reasoning for the four are in `findings.md`.
  The unmutated copy was verified 0 red / 0 skipped first, so the results mean
  something.
- Round 1 of `/code-check branch` returned three findings. Two fixed here, one
  deferred, plus two of its notes:
  1. **Fixed, and it changed a gate decision.** The new roxygen claimed other
     groups' rows are "never read", which the functions' own verbose counts
     disproved: they filter on `species_code` only, so a serial multi-WSG run
     with a shared `to_habitat` printed the whole table's numbers as the job's
     (measured by the reviewer: `2 disconnected removed (4 rearing remaining)`
     where the job's group had 1). The plan had left the counts unscoped as
     cosmetic — that was my call, not the owner's, and a wrong number printed to
     the user is not cosmetic. All seven count sites now take one shared
     `.frs_wsg_in()` clause, `.frs_bucket_connected()`'s included, so the claim is
     true and the family does not drift.
  2. **Fixed.** The downstream fixture picked its watershed group with an
     unordered `LIMIT 1`, so a failure could not be re-run against the pair that
     produced it, and `.cds_fixture()`'s insert dropped the group and mainstem
     predicates `.cds_pick()` applied — one population defined twice. Both
     closed.
  3. **Deferred to the follow-up issue, verified first.** `frs_order_child()`
     (exported) has the same defect: `R/frs_order_child.R:271` joins
     `h.id_segment = s.id_segment` with no group and writes **additively**, so it
     inflates a habitat set in a group the job never segmented. Same reason as
     `frs_habitat_overlay()` — a separate exported function, not one of the four
     connectivity passes, needing its own test.
  - Note taken: `test-frs_cluster.R`'s mocks stubbed on
    `grepl("DISTINCT species_code", ...)`, which no longer matches the scoped
    query. Dead today (both tests pass `species`), fixed so it cannot rot into a
    silently empty species list.
  - Note confirmed independently: the `OTHR3` assertion in the cluster-both test
    passes against pre-branch code too, because the old bug validated that
    cluster so the strip never reached the row. Already recorded above.
- Caught in my own work, not by a reviewer: every test in the file passes
  `verbose = FALSE`, so the newly scoped count queries were never executed by the
  suite at all. Hand-ran all four with `verbose = TRUE` (no ambiguity error, and
  the numbers are the job's own where unscoped they would read 4, 2, 3->2 and
  2->1), then wrote the test that covers them, because verifying a path by hand
  once is not coverage. Neutering `.frs_wsg_in()` to `""` in a copy reddens that
  test with four failed assertions, one per call site.
  Two of the file's own wrappers hardcoded `verbose = FALSE` and so printed
  nothing; they take a `verbose` argument now.

### Round 2 — a defect inside round 1's fix, and a conclusion of mine disproved

Round 2 is why the loop does not stop at three. It found a defect **inside** the
previous round's fix, which by `code-check.md`'s rule means only an enumeration
ends the loop, not a quiet round.

1. **Inside round 1's fix.** Round 1 scoped the seven count sites in the passes
   that *read* the shared habitat table and missed the eighth, in
   `frs_habitat_classify()` — the function that *writes* it. Textbook "a fix
   lands in one of two callers that share a harness".
2. **A conclusion of mine, disproved by measurement.** I had written that four
   sites were defence in depth whose removal "cannot change the final habitat
   state". Three were load-bearing. My reasoning assumed the phantom row from
   another group is a *duplicate*; it is only a duplicate when the two groups
   agree on the flag, which is the axis every fixture in the file happened to
   hold fixed. Reproduced before accepting it: shipped `FALSE`, predicate
   deleted `TRUE`. The fourth failed differently — my argument was sound for
   `lake_adjacent = FALSE` and the default is `TRUE`, where a cluster is credited
   for touching a lake, so the added stream lends its adjacency to its cluster.
   That is the reassuring-direction error `planning.md` warns about: a sentence
   saying there is nothing left to test is what licenses a later refactor to drop
   a predicate while the suite stays green.
3. **`.frs_wsg_in()`'s inner column was unqualified**, so it resolved outward to
   the habitat row for a `table` without the column — a correlated no-op that
   matches every row and reads as applied. One token.
4. **Round 1's own mock fix was inert** (0 calls; both tests pass `species`), and
   nothing anywhere called `frs_cluster(species = NULL)` — the one site where
   silence means a whole pass skipped rather than a number misreported.

All four addressed. Four new tests pin the four previously-uncatchable sites,
each verified red with only its own predicate removed; two more pin the
`.frs_wsg_in()` qualification and the classifier's count.

Two fixtures were wrong before they were right, and both failed in the direction
that looks like success:
- The upstream one asserted the wrong thing, because with
  `localcode_ltree = wscode_ltree` the 8-arg `FWA_Upstream` takes its simple
  branch and ignores measures, so a tributary counts as upstream of a position
  above its mouth. Rebuilt on the same-blue-line measure.
- The lake one placed a segment 500 m out from a boundary vertex, which sat back
  inside the polygon. It now measures its own geometry against every qualifying
  lake and skips rather than assert something it has not established.
