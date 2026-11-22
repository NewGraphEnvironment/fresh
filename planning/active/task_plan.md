# Task: Backlog sweep: batch the 52 open issues into moves (#315)

The 52 open issues are grouped into a few moves by the files they edit and the cost they share, in `planning/backlog.md`, with an umbrella issue per move that one `/planning-init` plans and one PR lands. Closures are proposed only with a stated reason.

## Decided at the gate

The owner approved the report below as written, 2026-11-22: the closures, the moves and batches, the models, and the umbrella titles.

## Context

fresh has 52 open issues, ordered only by when they were filed. Several have been overtaken by later work, and four older umbrellas (#231, #232, #233, #236) group issues by topic rather than by the files and cost they share. This pass reads every body and its comments, and checks each premise against `origin/main` (1dcc7a3, v0.55.1). It then groups the issues into **moves**: one umbrella issue each, one `/planning-init`, one PR. The result goes into a new `planning/backlog.md`. Nothing is written, filed or closed until you approve.

**Frozen set:** 53 open issues, the 52 plus #315 itself. **Placed:** 31 in 9 batches carried by 8 moves; 10 closed; 6 singles; 5 in tracks; #315 named in the Verified line. That is 31 + 10 + 6 + 5 + 1 = 53.

Every issue was filed from the owner account, so **each closure below happens only on your go.**

## Proposed closures (10)

| issue | reason | asks, each with its verdict on main |
|---|---|---|
| #64 parallelize Phase 1 across groups | done | parallel break pre-computation per group: done (PR #94; `frs_habitat()` runs each group's job in `mirai::mirai_map`, R/frs_habitat.R:579) |
| #73 MCP setup for local fwapg | done | pick an option: done (the org's database skill registers `db-local` on demand) |
| #243 tests use tibble undeclared | done | tibble in Suggests: done (50f3fa4, DESCRIPTION:38). A guard was offered as an *alternative* ("or") and isn't needed |
| #256 README roadmap lists MAD | superseded by #255 | remove the roadmap line: carried by #255's "Move finished roadmap items out of the roadmap" (README.md:129 still has it) |
| #295 NEWS 0.46.0 / #231 mechanism | done once #231's body is edited | NEWS correction: done (NEWS.md:62). CLAUDE.md: done (:252). Edit #231's "Shared mechanism" paragraph: **done as part of this pass**, before closing |
| #231 scope habitat ops by group (umbrella) | superseded by moves 1 and 5 | #242, #225: done. #277 parts 1–3: done (PR #296, #297). #277 direct mode: placed in batch 1. #218 constraint: placed in batch 2 |
| #232 match link/bcfishpass classification (umbrella) | superseded by move 6 | #219, #189, #178: each placed in batch 6 |
| #233 frs_db_query (umbrella) | superseded by move 3 | #21, #30: placed in batch 5 |
| #235 performance (umbrella) | superseded | #64: closed above. #199, #65, #167: speed track |
| #236 small standalone fixes (umbrella) | superseded | #227: batch 9. #85: batch 8. #105: single. Its own comment says it fails the batching rule |

## Moves and batches

| move | batches | issues | lane / waits on | model, and why |
|---|---|---|---|---|
| 1 | 1. Watershed-group keying fixes | #294, #308, #277 | lanes from `backlog_moves.sh lanes` | opus: multi-file SQL with real design forks |
| 2 | 3. Rules loading and persist validators | #267, #222, #239, #251, #250 | lanes | opus: five independent fixes in shared files |
| 3 | 4. frs_habitat() job plumbing; 5. frs_db_query read path | #310, #312, #311; #21, #30, #244 | lanes | opus: schema and API decisions |
| 4 | 9. Docs, naming and research re-verification | #303, #255, #299, #11, #227, + 2 research issues | lanes | sonnet: well-specified prose and renames |
| 5 | 2. id_segment identity at assignment | #218, #300 | waits on move 1 | fable then opus: a stored-data key design, then a routine build |
| 6 | 6. bcfishpass parity | #219, #189, #178, #258 | lanes | fable then opus: cross-repo semantics with link (link#132 waits on #189) |
| 7 | 7. Docker image and loader rebuild | #253, #68, #304, #306, #302 (+ open PRs #254, #252) | lanes | opus: ops change, one full rebuild verifies all |
| 8 | 8. Gradient breaks | #85, #257 | lanes | fable then opus: a precision vs parity design question |

**Batch details, and the decision each puts to you:**

1. **Watershed-group keying fixes.** Touches `R/frs_habitat.R`, `R/frs_break.R`, `R/utils.R`, `R/frs_cluster.R`, `R/frs_near_river.R`, `R/frs_habitat_classify.R`, `R/frs_habitat_overlay.R`, `research/id_segment_identity.md`.
   - Why here: the same keying family that #282 and #293 hit. #294 is data loss: a job deletes another group's barriers on the 259 blue lines that span groups.
   - Shared cost: the synthetic fixture.
   - Decisions: #308's option 1, 2 or 3; #277, whether direct mode refuses an id_segment-only join or documents it.
2. **id_segment identity at assignment.** Touches `R/utils.R`, `R/frs_break.R`, `R/frs_network_segment.R`, `R/frs_habitat_classify.R`, `R/frs_habitat_overlay.R`, `research/id_segment_identity.md`, `data-raw/`.
   - Decision (stored data): the unique key for persisted habitat tables. It must include `linear_feature_id`, because 81 of 275 derived ids collide inside one group, which makes #218's original index unsafe. Plus a migration or orphan audit for #300.
3. **Rules loading and persist validators.** Touches `R/frs_params.R`, `R/frs_habitat_predicates.R`, `R/frs_col_join.R`, `R/frs_feature_find.R`, `R/utils.R`, `R/frs_habitat.R`.
   - Why here: three of these fail silently. A non-ASCII byte under the C locale empties the rules (#267); reservoirs are dropped from the lake bucket (#250); a hidden 200 ha floor applies (#251).
   - Decisions: #251, no floor or refuse at load; #222, a target missing a flag column is altered or refused.
4. **frs_habitat() job plumbing.** Touches `R/frs_habitat.R`, `R/frs_break.R`, `R/frs_feature_find.R`, `R/frs_feature_index.R`, `R/frs_barriers_minimal.R`, `R/frs_db_conn.R`, `tests/testthat/helper-db.R`, `CLAUDE.md`.
   - Decisions: #310, `options()` or a `schema_working` argument; #312, whether to add `conn_args` at all; #311, which of three fixes.
5. **frs_db_query read path.** Touches `R/frs_db_query.R`, `R/frs_network_features.R`, the fetchers.
   - Decision: `drop_zm = TRUE` as the default, which is a breaking change for link and gradient users.
6. **bcfishpass parity.** Touches `inst/extdata/parameters_fresh.csv`, `data-raw/bcfishpass_params.R`, `R/frs_habitat_overlay.R`, `R/frs_habitat_classify.R`.
   - Shared cost: one parity oracle against bcfishpass.
   - Decisions: what bcfishpass actually uses (#219); known spawning as a trigger only, or rewriting `spawning` (#189); whether #258 is still wanted now link fixed link#349 on its side.
   - In flight elsewhere: link#132 waits on #189; link#452.
7. **Docker image and loader rebuild.** Touches `docker/`, `research/fwa_fetch_determinism.md`, the roxygen in `R/frs_lake_fetch.R`, `R/frs_wetland_fetch.R` and `R/frs_watershed_at_measure.R`, and the header of `tests/testthat/test-frs_network_features-local.R`.
   - Shared cost: one full rebuild on a new image. It verifies the loader fix (PR #254, which closes #253 and #68), the GEOS move (#304), the simplify repeat probe (#306) and the re-derived test counts (#302).
   - Decision: move the image to bookworm. Also refresh or close PR #252 (tuning.md).
8. **Gradient breaks.** Touches `R/frs_break.R` and a new `R/frs_gradient_*.R`.
   - Decision: exit breaks (#85), which diverge from bcfishpass; and whether #257 belongs to the gradient track (knowledge#70) rather than to fresh.
9. **Docs, naming and research re-verification.** Touches `README.md`, `DESCRIPTION`, `_pkgdown.yml`, `data-raw/audit_persist_282.R` and `data-raw/audit_habitat_293.R` (#299 now covers both), `data-raw/pipeline_wsg.R` (#227), `vignettes/`, `research/`.
   - Decision: the README's opening line.

**Singles:**
- #105: feature-code categories. Nothing consumes it today. Keep it or close it on your word.
- #246: upstream area for placeholder segments. Option 1 is already documented; close it or build option 2.
- #265: **waiting** on fwapg#36 (the default downstream walk).
- #44 and #41: spyda and configurable column names, long-term. link#133 waits on #44.

**Tracks:** speed: #65, #167, #199, #275. Package boundaries: #288.

**Research issues to file**, one per file, both into batch 9:
- "re-verify research/fwa_waterbody_key_polygons.md": no `**Verified:**` date, 168 words.
- "re-verify research/fwapg_channel_width.md": no `**Verified:**` date, 350 words.

## Top three

1. **Move 1.** #294 deletes another group's rows; it is the third recurrence of the keying family (#282, #293).
2. **Move 2.** Three habitat-classification errors that never raise.
3. **Move 7.** The loader is broken against current fwapg (#253), so no fresh rebuild is possible, and GEOS 3.9.0 gives wrong answers (#304).

## Umbrella bodies (as filed, one per move)

Each opens with an **If we do it / If we never do** line. Then it points to `planning/backlog.md` with "run `/planning-init <this issue>`", followed by the split sentence naming this move. Then comes one section per batch: why here, touches, decided at the gate (the decisions above), and a members table (`issue | title`). Titles:

1. "Backlog move 1: watershed-group keying fixes (#294, #308, #277)". If: barriers and habitat rows stop crossing groups. Never: a job keeps deleting other groups' barriers on group-spanning lines.
2. "Backlog move 2: rules loading and persist validators". If: a bad rules file or target fails loudly. Never: rules silently empty under the C locale, reservoirs stay out of the lake bucket.
3. "Backlog move 3: frs_habitat() job plumbing and the frs_db_query read path". If: scratch tables follow the caller's schema, workers carry connection options, queries take bound parameters. Never: wsg-mode live tests stay untestable under per-run names.
4. "Backlog move 4: docs, naming and research re-verification". If: the README says what fresh is for and lists what shipped. Never: the website keeps a stale capability list.
5. "Backlog move 5: id_segment identity at assignment". If: persisted habitat tables get a key that cannot collide. Never: orphaned rows keep another run's id_segment.
6. "Backlog move 6: bcfishpass parity in habitat classification". If: fresh's bundled parameters and overlay match bcfishpass, which unblocks link#132. Never: link keeps working around fresh.
7. "Backlog move 7: docker image and loader rebuild". If: a fresh fwapg can be rebuilt, on a GEOS that answers point-on-boundary correctly. Never: no new local database can be built.
8. "Backlog move 8: gradient breaks". If: breaks catch the drop below the lowest threshold. Never: segments that leave a steep class stay merged.

**Public repo:** the file and the umbrella bodies will be scanned before writing, and they name no host, port or private repo.

## Phases (on approval)

### Phase 1: Write the pass
- [x] Write `planning/backlog.md` from the backlog header template, with the Moves table (seven columns), Order, one section per batch with a `**Touches:**` line, Singles, Tracks, and Closed and transferred
- [x] Coverage check against the frozen set (53)

### Phase 2: File and close
- [x] Draft the umbrella bodies to the git dir, run `public_leak_scan`, then file the 8 umbrellas and the 2 research issues
- [x] Write the umbrella numbers into the Moves table; run the tick check on a copy; run `lanes` and fill `lane` / `waits on`; run the model check
- [x] Edit #231's "Shared mechanism" paragraph (it should name the two assignment sites), then close the 10 issues with reason comments

### Phase 3: Land
- [ ] Commit the backlog file on the branch; `/code-check` (the file is read by `backlog_moves.sh`); `/planning-archive`; `/gh-pr-push`

## Validation
- [x] Coverage: every one of the 53 frozen issues is named in the file
- [x] `backlog_moves.sh list`, `next` and `lanes` read the file; every open move ticks cleanly on a copy
- [x] The public scan is clean
- [ ] `/code-check` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

