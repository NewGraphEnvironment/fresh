# Plan review — #282 baseline

Plan agent, spawned 2026-10-28 19:38 PDT, synchronous gate before the parked
baseline commit. Findings below are the agent's; each carries **my verdict** from
a probe run after the report landed. Verdicts matter more than the findings here,
because the review's headline conclusion is partly disproved by the production
table it did not reach.

## Verdict summary

| # | Finding | Verdict |
|---|---|---|
| B1 | `id_segment` does not restart per job — base rows get `linear_feature_id` | **CONFIRMED in code** |
| B1b | …therefore #218's and the issue's premise are impossible | **DISPROVED on the production table** |
| B2/B3 | Same-group collision dominates; the pair key creates duplicate key pairs | **UNRESOLVED — both measurements stand, on different table generations** |
| B4 | `frs_habitat_classify()` / `frs_near_river()` delete whole groups in custom-AOI mode | **CONFIRMED, and larger than #282** |
| G1 | `to` lacking the column → duplicates, not replacement | Adopted (mechanism read, not executed) |
| G2 | Fallback is one-sided; error beats fallback | Adopted |
| G3 | `.frs_persist_columns()` returns only a pasted string | **CONFIRMED** (`R/utils.R:1021`) |
| G4 | Nothing the plan proposes runs on CI | **CONFIRMED** — no Postgres service in `.github/workflows/` |
| G5 | No `to_streams != working.streams_<label>` guard | Adopted |
| G6 | No repair/detection for already-damaged tables | Adopted |
| G7 | mirai daemon gets the *installed* package → hard error, not a skip | Adopted |
| — | Enumeration test can't fire (cwd is `tests/testthat`) | **CONFIRMED** by R convention; replacement adopted |
| — | "259 spanning blue lines" unverified by the agent (query timed out) | **Stands** — measured twice on this connection |

## B1 — confirmed in the code, and it invalidates the stated mechanism

`R/utils.R:571-577`, `.frs_add_id_segment()`:

```r
"ALTER TABLE %s ADD COLUMN IF NOT EXISTS id_segment integer"
"UPDATE %s SET id_segment = linear_feature_id WHERE id_segment IS NULL"
```

Its own roxygen says it: *"Uses `linear_feature_id` as the starting value (so
original FWA segments keep their ID), then generates new IDs for any rows added
later by `frs_break_apply()`."* Only broken segments get
`max(id_segment) + row_number()` (`R/frs_break.R:697-701`). `git log -L` on those
lines shows it has been this way since it was introduced (`0995567`, #84) — never
changed.

So **"each working table numbers its segments independently / restarts at 1" is
wrong as a description of current code**, and it is wrong in four places: issue
#282's body, `task_plan.md`, `findings.md`, and shipped `NEWS.md` 0.46.0. There
are exactly two `id_segment` assignment sites in `R/` (`R/utils.R:576`,
`R/frs_break.R:699`), so this is an enumeration, not an impression.

## B1b — but the production table is the opposite, which the review could not see

The agent reported it could reach no `fresh` schema and concluded #218's
measurement was "impossible". The default `frs_db_conn()` does reach it. Measured
2026-10-28, `statement_timeout = 240s`:

```sql
SELECT count(*) n_rows, count(DISTINCT watershed_group_code) n_groups,
       sum((id_segment =  linear_feature_id)::int) n_base,
       sum((id_segment <> linear_feature_id)::int) n_derived
FROM fresh.streams;
--> 3,802,814 rows | 98 groups | n_base = 0 | n_derived = 3,802,814
```

```sql
SELECT watershed_group_code, count(*) n, min(id_segment), max(id_segment),
       min(linear_feature_id), max(linear_feature_id)
FROM fresh.streams WHERE watershed_group_code IN ('BULK','COTR') GROUP BY 1;
--> BULK  87,639 rows  id 1..87,639   lfid 17,000,014..868,144,543
--> COTR  36,815 rows  id 1..36,815   lfid 700,821,184..868,144,477
```

`id_segment` in the persisted table is a **per-group 1..n sequence**, with **no**
row equal to its `linear_feature_id`. Collisions are therefore total, not
incidental:

```sql
SELECT count(*) FROM (SELECT id_segment FROM fresh.streams
  GROUP BY id_segment HAVING count(DISTINCT watershed_group_code) > 1) z;
--> 113,305 id_segment values appear in more than one group

-- every COTR id also exists in another group:
--> 36,815 of 36,815
```

That reconciles #218 exactly (187 Naver Creek segments matching 22 groups) and
vindicates the issue's premise *for the table the examples target*. It also
confirms the pair is currently a valid key: **0** duplicate
`(id_segment, watershed_group_code)` pairs in 3.8M rows.

**So the two sides measured different artifacts.** Current `main` cannot produce
a per-group 1..n sequence, so `fresh.streams` was built by an older pipeline (the
`frs_habitat_partition` / `frs_habitat_species` era, now removed). Which means:

- Persisting into **`fresh.streams` as it exists**: collisions are cross-group and
  total → the pair key fixes the loss, and keeps a key that currently holds.
- Persisting into a **freshly built** `to_streams` under current code: base ids are
  `linear_feature_id`, and the agent's measurement on `working.streams_dbg122`
  (434 rows, 189 base / 245 derived, 76 derived ids colliding with real ADMS
  lfids outside the AOI) says the residual collisions are *same-group*, where the
  pair key does nothing and would introduce duplicate pairs.

Neither measurement is wrong. **The key decision is re-opened** and belongs to
Phase 0, which must take both measurements on the table actually being written.
I have not flipped the owner's decision on a review finding; I have recorded that
its premise moved.

## B4 — confirmed, and it is bigger than #282

`R/frs_habitat_classify.R:170-172` derives the delete scope from the working
table and then deletes whole groups from the shared habitat table (`:249-255`):

```r
wsg_codes <- DBI::dbGetQuery(conn, "SELECT DISTINCT watershed_group_code FROM <table>")
# … per code:
DELETE FROM <to_habitat> WHERE watershed_group_code = <wsg>
```

In custom-AOI mode that removes **every row of every group the AOI touches**, then
inserts only the AOI's. `R/frs_near_river.R:155-158` has the identical shape, and
its comment states the intent outright — *"A custom AOI need not be one group, so
delete every group the table holds"* — against a target that
`R/frs_habitat_classify.R:208` makes shared (`paste0(to, "_near_river")`).

My `findings.md` had both of these in a "checked, no change needed" list. That
was wrong, and wrong in the reassuring direction: I classified them by *whether
the DELETE names `watershed_group_code`* when the question is *whether the group
set is the right scope*. Corrected in `findings.md`; filed as its own issue in
Phase 0 rather than Phase 4, because if it is the dominant loss then this
branch's NEWS has to be written around it. Adjacent to #225 (open) and #163
(closed — literally "are `frs_break_apply` / `frs_habitat_classify` /
`frs_cluster` fully per-AOI?").

Correctly classified in that same list, verified: `R/utils.R:468-487`
(`.frs_near_river_sql()`) and `R/frs_network_segment.R:199-206`.

## Adopted without independent execution

G1 (ALTER-before-DELETE leaves NULL-group rows that `IS NOT DISTINCT FROM` will
not match, so the job's own prior rows duplicate rather than replace), G2 (error
on column mismatch instead of a silent fallback to the key just shown to be
wrong), G5, G6, G7, O4 and the six-step Phase 1 assertion list are mechanism
reads of code I have also read, and they are consistent with it. They are folded
into `task_plan.md` as written. The `deparse(body(frs_habitat))` enumeration
replacement is adopted because the mirai closure is lexically inside
`frs_habitat`'s body, so one assertion covers both paths with no DB and no file
paths — and it carries a positive control, which the file-parsing version did not.

Two corrections the agent made to my own citations, both accepted: the
`to_barriers` projection is `R/frs_break.R:350-357` (multiclass — the arm
`frs_habitat()` actually reaches), not `:225-231`; and `#225` is the filed
precedent for the NULL-group shape.

G1 is recorded above as the review stated it, which is history and stays. What
shipped differs on both halves: the predicate is `=`, and the hazard is caught
by a guard that refuses a target holding NULL-key rows for **any** of the three
keys. The first version of that guard asked whether this call had added the key
column, which round 1 of `/code-check branch` measured to be a one-shot proxy;
it now asks the target directly. `findings.md` carries the reasoning.

## What the review did not change

Decision 2 stands — `to_barriers` is a separate issue. The agent found nothing
against it, and the "259 blue lines spanning more than one watershed group"
figure it could not reproduce (timeout) is measured on this connection and holds.
