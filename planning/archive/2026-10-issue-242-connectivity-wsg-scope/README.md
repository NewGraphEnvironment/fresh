## Outcome

`frs_habitat(to_habitat = )` writes every watershed-group job into one habitat
table, and the four post-classification connectivity passes joined it on
`id_segment` alone — a key unique only *within* a group, so one group's pass read
and cleared another's. All of them now match `watershed_group_code`, and every
subtractive or additive UPDATE is confined to the groups present in `table`,
following `.frs_bucket_connected()`'s pattern from #240.

Two things were worse than the issue described, both found by measurement rather
than reading. `.frs_connected_waterbody()`'s subtractive step named **no**
watershed group at all, so on a shared table it cleared the species' `spawning`
across every group already written, with no `id_segment` collision needed — and
SK and KO are exactly the species the shipped parameters route to it, making it
the live path. And `frs_cluster(direction = "both")` was returning wrong answers
*for the group it was processing*: a `LEFT JOIN` on `id_segment` duplicated
traced segments, so the running `SUM(length_metre)` double-counted and a cluster
inside `bridge_distance` could read as beyond it.

What this work is most worth remembering for is how the defect class kept
escaping its enumeration. One fact — the habitat key is `(id_segment,
watershed_group_code)` — and five rounds of review each found the class one axis
over from where the previous fix had drawn its boundary: statement kind
(aggregates have no join to carry the group), function role (the classifier
*writes* the shared table and its count was missed when the seven readers were
scoped), predicate placement (an unqualified inner column resolves outward and
becomes a correlated no-op that reads as applied), fixture axis (every fixture
here held "the two groups agree on the flag" fixed, which is the one case where
a phantom row is a harmless duplicate), and artifact kind (the published
`frs_habitat_classify()` example taught the single-key join, five lines above its
own note that both tables accumulate). Two of the findings were against this
branch's own written claims rather than its code — a sweep's "these four
predicates are unobservable", false for three of them, and a test-file header
claiming every block asserts a keep and a strip, false for 6 of 16. Both are the
same shape, and the dangerous one: a sentence asserting there is nothing left to
test is what licenses a later refactor to drop a predicate while the suite stays
green.

## Measurement

- **19 of 19 predicates pinned.** Each was restored alone against a baseline
  confirmed green and skip-free: `sites with no test catching them: 0 of 19`.
  The first sweep read 15 of 19, and the conclusion drawn from that gap — that
  the four were defence in depth — was wrong for three of them; they are now
  covered by four tests written for the axis the earlier fixtures held fixed.
  Four further mutations outside that list each redden their own test.
- **Trace distance double-counted by exactly one duplicate per colliding row.**
  Spawning 2000 m below a cluster, two intermediate segments each carrying one
  extra habitat row in another group, cap 2500 m: the trace measured 4000 m and
  invalidated a cluster that sits inside the cap. This is what established that
  the defect was not only a cross-group leak.
- **A progress line reported another group's numbers as the job's**:
  `2 disconnected removed (4 rearing remaining)` where the job's own group had 1.
  That changed a decision — the plan had ruled the verbose counts cosmetic and
  left them unscoped; they are all scoped now, eight sites through one helper.
- **Suite: 2090 pass, 0 fail, 6 skips**, all pre-existing (`bcfishpass`-schema
  and `FRESH_FWAPG_TRIAL` gates). `lintr` delta in `R/` is −5.
- The fwapg predicate semantics these fixtures turn on are written up in
  [`research/fwa_upstream_predicate.md`](../../../research/fwa_upstream_predicate.md),
  because each cost a wrong test before it was measured.
- Two fixtures were wrong before they were right, both failing in the direction
  that looks like success: one asserted the wrong thing because
  `localcode_ltree = wscode_ltree` makes the 8-arg `FWA_Upstream` ignore measures
  entirely, and one placed a segment 500 m out from a lake's boundary vertex that
  sat back inside the polygon. Kept here because a fixture that cannot fail is
  the failure this work was about.

## Evidence

No run logs: every measurement is a test or a mutation reproducible from
`tests/testthat/test-frs_connectivity_wsg.R` and the mutation table in
`findings.md`.

Closed by: PR for #242 on branch `242-connectivity-passes-join-a-shared-habita`.
Spawned #277 (four more places keyed on `id_segment` alone, including two
exported functions and one output with no group column at all).
