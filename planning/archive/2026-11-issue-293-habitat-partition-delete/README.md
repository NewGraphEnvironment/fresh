# #293 — custom-AOI jobs deleted whole watershed groups from the shared habitat and `near_river` tables

## Outcome

`frs_habitat_classify()` and `frs_near_river()` took their overwrite scope from
the groups the working table named and deleted those groups **whole**, so a
custom-AOI job removed rows it never put back. Following #282, the owner chose at
the gate to widen both tables with the parent FWA segment `linear_feature_id`
(only when the source carries one, so non-FWA networks keep `id_segment`), to key
the delete on it, to refuse legacy tables with a NULL key and backfill them by
whole-group re-runs, and to scope the custom-AOI delete to the species the job
inserts while `wsg` mode stays a wholesale replace. The plan review found the
consequence that made this more than a delete fix: the whole-group delete was the
only thing that made `(id_segment, watershed_group_code)` a sound **read** key on
these tables, so every habitat-to-streams join had to gain the parent too. They now
go through one helper, `.frs_key_match()`, and two enumeration tests pin that no
join is spelled inline and no helper call switches the parent off.

`/code-check branch` ran six rounds, and every round from 2 to 6 found a defect
inside an earlier round's fix. Round 3 named the first mechanism, one policy
written out in several writers and one fact restated in several places, each fixed
on the copy the finding arrived through. Round 4 found two of round 3's fixes
recorded and never written to `R/`. Rounds 5 and 6 named the second: each round's
enumeration covered only what its tool could reach (parsed `.R` files and not Rd
examples, one spelling of a join, fixtures that all carried the parent so the group
condition was invisible) and was then cited for the whole population. The loop
ended on round 6's enumeration of the 40 quantified claims the branch makes: 35
held and 5 were fixed (`review-verdict.md`).

The first mutation sweep found four sites no test could fail on. The first reading
blamed a narrow test filter, and a 130-test re-run showed that was wrong. Three of
the four were real gaps (the parent-segment arm of the connectivity reads had no
test), and one was a redundant handler ordering that no test can observe. The full
re-run on 2026-11-10 stalled for seven hours: the database host stopped answering,
and `frs_db_conn()` sets no timeout, so the suite blocked instead of skipping
(#305).

Durable findings are in
[`research/id_segment_identity.md`](../../../research/id_segment_identity.md):
why the sibling tables now carry the parent, and what #293 did not fix (#300).

## Measurement

- **The issue overstated the loss.** On the documented AOI the job covers 50,808 of
  the 69,956 segments in the five groups it touches (73%). So the loss was 19,148
  rows per species, 0.38 per row written, not a multiple of the rows written. The
  issue body was corrected to the measured figure.
- **Why the reads needed the key.** Of one run's 275 derived `id_segment` values,
  81 equalled a real `linear_feature_id` in the run's own group (from #282). A
  whole-group run followed by a custom-AOI run inside it, which is the repair path
  this release recommends, puts both jobs' rows in one group.
- **A3, the whole-province delete, measured with `EXPLAIN` and disproved.** One
  semi-join over 3.7M rows cost ~1.03M against 98 group filters at ~80K each
  (~7.9M), so the new form is cheaper for a whole-province run. `wsg_code` exists
  for the one-group case, where it is dearer.
- **Two workers through mirai, one shared table.** 464 rows from the outer AOI;
  the same ground again gave 464 (replaced, not duplicated); an inner AOI of 231
  segments gave 464 (the outer rows outside it survived). The first attempt failed
  because mirai workers load the *installed* package.
- **Mutation sweep, final:** 27 of 27 sites caught in both mutated runs on
  `76fccc1`, baseline 136 tests, 0 red, 0 skipped, before and after; 5 h 37 min.
  The first sweep caught 20 of 24; the four gaps it found are what added the
  read-side tests and the second enumeration test.
- **Full suite at the end:** FAIL 0, WARN 18, SKIP 7, PASS 2643. The skips are
  `main`'s fwapg migration gates, the absent `bcfishpass` schema, and one live test
  whose second database was unreachable.

## Evidence

`data-raw/logs/habitat_293/*`: the mirai two-worker log and the Phase 0 audit
summaries. `tables.csv` is gitignored, because it names every schema on the
instance and this is a public repo.

## Follow-ups filed

#294 (`to_barriers` keyed on `blue_line_key`), #300 (an orphaned species' rows keep
an old `id_segment`), #305 (no connect or keepalive timeout), #308 (NULL-group rows
are written but never read), link#452 (link's `near_river` mirror, and its
validator's call to `frs_habitat_predicates()`, which now requires `near_river_lfid`).

Closed by: PR for branch `293-custom-aoi-jobs-delete-whole-watershed-g` (#293, #225)
