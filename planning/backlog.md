# fresh backlog: move order

**Verified:** 2026-11-22 against 53 open issues · **Produced by:** a read of every open issue body (`gh issue list --state open`) and its comments, each premise checked against `origin/main` at 1dcc7a3 (v0.55.1), every closure claim probed in the tree · the sweep's own issue, #315

How to use this file: `/backlog-sweep` writes it. Take the first move in **Moves** that is not ticked and not **waiting**; `/planning-init <umbrella>` plans it, one phase per batch, one PR.
A move that waits only on other moves is `open`, with them in `waits on`; `**waiting**` is for a blocker outside this file (the owner, another repo, a PR, a count).
When the plan finds that a batch, or one of its members, is more than one PR's work, it carries the first piece and files each other piece as its own issue, naming the move it was split from, and leaves it out of this file: the next `/backlog-sweep` reads an issue the file does not name as unplaced, and folds it into a move other than the one it was split from.
`/gh-pr-merge` step 9c ticks the move on merge, and opens a move `**waiting** on PR #N` (this repo's PR, and no other condition) when that PR merges; `/compact-prep` names the next, skipping a move whose `waits on` names a move not yet ticked. A plan that defers one of its batches sets that section's first line to `- [ ] Not yet in a move`: the tick leaves it open and says so, and `next` names it once the move is done, for the next pass to place. A `NONE` from `backlog_moves.sh next` that names batch sections means those batches have no move yet, and a plain `NONE` is not the end either while an open issue is named nowhere here (`/compact-prep` counts them): run `/backlog-sweep` again, the backlog is not finished.

## Moves

| move | umbrella | batches | state | lane | waits on | model |
|---|---|---|---|---|---|---|
| - [ ] 1 | #318 | 1: watershed-group keying fixes (3 issues) | open: start here | A | — | opus |
| - [ ] 2 | #319 | 3: rules loading and persist validators (5 issues) | open | A | 1 | opus |
| - [ ] 3 | #320 | 4, 5: frs_habitat() job plumbing, frs_db_query read path (6 issues) | open | A | 1, 2, 7 | opus |
| - [ ] 4 | #321 | 9: docs, naming and research re-verification (7 issues) | open | B | — | sonnet |
| - [ ] 5 | #322 | 2: id_segment identity at assignment (2 issues) | open | A | 1, 3, 4, 6 | fable then opus |
| - [ ] 6 | #323 | 6: bcfishpass parity (4 issues) | open | C | 1 | fable then opus |
| - [ ] 7 | #324 | 7: docker image and loader rebuild (5 issues) | open | D | — | opus |
| - [ ] 8 | #325 | 8: gradient breaks (2 issues) | open | A | 1, 3, 5 | fable then opus |

Lanes: moves sharing a file run one after the other (A, the core habitat code); docs (B), parity (C) and docker (D) can run beside lane A once their `waits on` moves are ticked.

Tracks are separate efforts, not moves: speed (`track:speed`, NewGraphEnvironment/soul#593) carries #65, #167, #199 and #275; package boundaries (`track:package-boundaries`, NewGraphEnvironment/soul#605) carries #288.

## Order

| # | tracking | batch | issues | gate | why here |
|---|---|---|---:|---|---|
| 1 | #318 | watershed-group keying fixes: #294, #308, #277 | 3 | #308's option; #277 refuse or document | the keying family's third recurrence; #294 deletes other groups' rows |
| 2 | #322 | id_segment identity at assignment: #218, #300 | 2 | the persisted key (stored data) | one key design; waits on batch 1 |
| 3 | #319 | rules loading and persist validators: #267, #222, #239, #251, #250 | 5 | #251 floor; #222 missing flag column | three silent misclassifications, one loader |
| 4 | #320 | frs_habitat() job plumbing: #310, #312, #311 | 3 | schema option or argument; `conn_args` | one job-setup path |
| 5 | #320 | frs_db_query read path: #21, #30, #244 | 3 | `drop_zm` default (breaking) | one function |
| 6 | #323 | bcfishpass parity: #219, #189, #178, #258 | 4 | what bcfishpass uses; trigger or rewrite | one parity oracle |
| 7 | #324 | docker image and loader rebuild: #253, #68, #304, #306, #302 | 5 | the image move | one full rebuild verifies all |
| 8 | #325 | gradient breaks: #85, #257 | 2 | exit breaks vs parity | one vertex walk |
| 9 | #321 | docs, naming and research re-verification: #303, #255, #299, #11, #227, #316, #317 | 7 | the README opening line | one writing pass |

### 1. Watershed-group keying fixes

- [ ] Carried by move 1, #318

**Touches:** `R/frs_habitat.R`, `R/frs_break.R`, `R/utils.R`, `R/frs_cluster.R`, `R/frs_near_river.R`, `R/frs_habitat_classify.R`, `R/frs_habitat_overlay.R`, `research/id_segment_identity.md`

#294 keys the `to_barriers` delete on `blue_line_key` alone, so a job removes another group's barriers on the 259 lines that span groups. #308: rows with a NULL `watershed_group_code` are written and never read. #277: direct-mode overlay still accepts an `id_segment`-only join (its parts 1-3 shipped in PR #296 and #297). Gate: #308's option 1, 2 or 3; #277 refuse or document.

### 2. id_segment identity at assignment

- [ ] Carried by move 5, #322

**Touches:** `R/utils.R`, `R/frs_break.R`, `R/frs_network_segment.R`, `R/frs_habitat_classify.R`, `R/frs_habitat_overlay.R`, `research/id_segment_identity.md`, `data-raw/`

#218's docs are mostly done; its unique index is not, and as proposed it is unsafe (81 of 275 derived ids collide inside one group), so the key must include `linear_feature_id`. #300's orphaned rows need the same design, and a migration or audit. Gate: the persisted key (stored data). Waits on batch 1.

### 3. Rules loading and persist validators

- [ ] Carried by move 2, #319

**Touches:** `R/frs_params.R`, `R/frs_habitat_predicates.R`, `R/frs_col_join.R`, `R/frs_feature_find.R`, `R/utils.R`, `R/frs_habitat.R`

#267: the rules YAML read depends on the session locale. #250: the lake bucket ignores reservoirs. #251: a hidden 200 ha floor. #222: five validator gaps left after #114 (the habitat delete and insert are already one transaction, from #293). #239: `frs_col_join()` types a subquery's columns `text`. Gate: #251 no floor or refuse at load; #222 alter or refuse a target missing a flag column.

### 4. frs_habitat() job plumbing

- [ ] Carried by move 3, #320

**Touches:** `R/frs_habitat.R`, `R/frs_break.R`, `R/frs_feature_find.R`, `R/frs_feature_index.R`, `R/frs_barriers_minimal.R`, `R/frs_db_conn.R`, `tests/testthat/helper-db.R`, `CLAUDE.md`

#310: scratch tables hardcode the working schema. #312: workers cannot carry a caller's connection options. #311: `frs_fwapg_conn()` can be redirected by `PGHOSTADDR`. Gate: #310 `options()` or `schema_working`; #312 add `conn_args` at all; #311 which fix.

### 5. frs_db_query read path

- [ ] Carried by move 3, #320

**Touches:** `R/frs_db_query.R`, `R/frs_network_features.R`, `R/frs_stream_fetch.R`, `R/frs_lake_fetch.R`, `R/frs_wetland_fetch.R`

#21: bound parameters. #30: drop Z/M by default. #244: the geometry warning on every `frs_network_features()` call. Gate: `drop_zm = TRUE` as the default, a breaking change.

### 6. bcfishpass parity

- [ ] Carried by move 6, #323

**Touches:** `inst/extdata/parameters_fresh.csv`, `data-raw/bcfishpass_params.R`, `R/frs_habitat_overlay.R`, `R/frs_habitat_classify.R`

#219: bundled parameters disagree with link. #189: known spawning as a rearing trigger. #178: bridge mode from containment to range overlap. #258: a measure tolerance, prompted by a link case link has since fixed on its side. In flight elsewhere: link's own open work waits on #189 (search `repo:NewGraphEnvironment/link is:open fresh#189`). Gate: what bcfishpass uses; trigger or rewrite; #258 still wanted.

### 7. Docker image and loader rebuild

- [ ] Carried by move 7, #324

**Touches:** `docker/`, `research/fwa_fetch_determinism.md`, `R/frs_lake_fetch.R`, `R/frs_wetland_fetch.R`, `R/frs_watershed_at_measure.R`, `tests/testthat/test-frs_network_features-local.R`

One full rebuild verifies all five: the loader fix in the open PR #254 (closes #253 and #68), the GEOS move (#304), the simplify repeat probe (#306) and the re-derived answer-pair counts (#302). The open PR #252 also edits `docker/tuning.md`. Gate: move the image to bookworm.

### 8. Gradient breaks

- [ ] Carried by move 8, #325

**Touches:** `R/frs_break.R`

#85: no break at the drop below the lowest threshold. #257: fixed-window, mouth-reach and lidar gradients, in a new file beside the vertex walk. Gate: exit breaks diverge from bcfishpass; whether #257 belongs to the gradient track.

### 9. Docs, naming and research re-verification

- [ ] Carried by move 4, #321

**Touches:** `README.md`, `DESCRIPTION`, `_pkgdown.yml`, `data-raw/audit_persist_282.R`, `data-raw/audit_habitat_293.R`, `data-raw/pipeline_wsg.R`, `vignettes/`, `research/fwa_waterbody_key_polygons.md`, `research/fwapg_channel_width.md`

#303 and #255: the README's opening and its capability list and roadmap. #299: two verb-first `data-raw/` names now. #11: vignette citations. #227: `pipeline_wsg.R` defaults to BULK. #316 and #317: two research files with no Verified date. Gate: the README opening line.

## Singles

- #105: feature-code categories; nothing consumes them today. Keep, or close on the owner's word.
- #246: upstream area for placeholder segments; option 1 is documented already. Close, or build option 2.
- #265: **waiting** on fwapg's decision on the default downstream walk (NewGraphEnvironment/fwapg#36).
- #44: configurable column names; link's open work waits on it. Long-term.
- #41: spyda design placeholder; closes when that repo exists.

## Closed and transferred

- #64: closed, done: `frs_habitat()` runs each group's job in mirai workers (PR #94).
- #73: closed, done: soul's db-newgraph skill registers a `db-local` MCP on demand.
- #243: closed, done: tibble is in Suggests (50f3fa4).
- #256: closed, superseded by #255's roadmap task.
- #295: closed, done: NEWS and CLAUDE.md were corrected; #231's paragraph was edited in this pass.
- #231: closed, superseded: #242 and #225 done, #277 parts 1-3 done, the rest in batches 1 and 2.
- #232: closed, superseded by batch 6.
- #233: closed, superseded by batch 5.
- #235: closed, superseded: #64 done, #199, #65 and #167 on the speed track.
- #236: closed, superseded: #227 in batch 9, #85 in batch 8, #105 a single.
