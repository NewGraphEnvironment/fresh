# `FWA_Upstream()`: what each arity actually compares

**Verified:** 2026-10-28 · **Issues:** #242 · **Produced by:** `pg_get_functiondef('whse_basemapping.fwa_upstream')` on the 4-arg form, plus truth-table queries against a local fwapg; the fixtures that depend on it are in `tests/testthat/test-frs_connectivity_wsg.R` · **Status:** OPEN — measured on the arities fresh calls; the 8-arg body was not read, only probed.

Three facts that are easy to assume wrongly and that quietly decide what a
synthetic fixture can prove. Each cost a wrong test before it was measured.

## The 4-arg form admits equality

`fwa_upstream(wscode_a, localcode_a, wscode_b, localcode_b)` has a "simple case"
branch that fires when `wscode_ltree_a = localcode_ltree_a`, and it reduces to

```sql
wscode_ltree_b <@ wscode_ltree_a AND localcode_ltree_b <@ localcode_ltree_a
```

`<@` is descendant-**or-equal**, so the predicate is TRUE when the two codes are
the same. Measured:

| a | b | result |
|---|---|---|
| `100` / `100` | `100` / `100` | TRUE |
| `100` / `100` | `100.300000` / `100.300000` | TRUE |
| `100` / `100` | `200` / `200` | FALSE |

**Consequence for a fixture.** Any set of segments built with
`localcode_ltree = wscode_ltree` on one wscode is mutually "upstream", with no
reference to position at all. So a segment that must be *excluded* by a
4-arg-based predicate has to sit on a code that is not a descendant — a separate
river — not merely further downstream. A fixture relying on downstream position
within one wscode cannot fail.

This is also why `.frs_distance_filter()` carries a separate
`r.blue_line_key = s.blue_line_key AND s.drm >= r.drm` clause beside its
4-arg call: the ltree test alone says nothing about where on the stream either
segment is.

## The 8-arg form uses measures, and excludes self

Probed rather than read. On one blue line it compares
`downstream_route_measure`, and a segment is **not** upstream of itself:

| from | to | result |
|---|---|---|
| blk 1 @ 1000 | blk 1 @ 1000 | FALSE |
| blk 1 @ 1000 | blk 1 @ 2000 | TRUE |
| blk 1 @ 1000 | blk 1 @ 0 | FALSE |

So a single segment carrying both a cluster label and its connect label sits in
a cluster that the upstream check finds invalid — which is what makes
`frs_cluster(direction = "both")`'s on-spawning protection observable, and so
testable, at all.

Across blue lines the 8-arg form falls back to the ltree rule above, equality
included. A tributary therefore counts as upstream of a mainstem position
*below its own mouth*, whenever the mainstem row has `localcode = wscode`.

## `subpath(wscode, 0, -1)` on a one-label code is the empty ltree

And every ltree is a descendant of the empty one. `frs_cluster()`'s confluence
boost reads

```sql
cm.downstream_route_measure < confluence_m
AND FWA_Upstream(subpath(cm.wscode_ltree, 0, -1), cm.wscode_ltree,
                 st.wscode_ltree, st.localcode_ltree)
```

With a one-label `cm.wscode_ltree` the first argument is `''`, so
`wscode_a != localcode_a` and the second branch applies, where
`st.wscode_ltree <@ ''` is TRUE for everything. What remains is a string
comparison (`st.wscode > localcode_a`), which admits `label_connect` on **any
river sorting above this one**.

Real FWA codes have several labels, so this is reachable in a synthetic fixture
rather than in production. The practical rule when writing one: either use a
multi-label wscode, or keep every cluster minimum at or above `confluence_m`,
or the boost will validate clusters from unrelated rivers and the test will
pass for a reason that has nothing to do with its subject.

Not fixed in #242 — out of scope there, and worth its own look before anyone
writes a fixture with single-label wscodes below the confluence tolerance.
