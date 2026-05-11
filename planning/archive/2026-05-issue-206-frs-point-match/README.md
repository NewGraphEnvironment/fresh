## Outcome

Shipped `frs_point_match()` as a new exported primitive (fresh v0.30.0). Matches two FWA-snapped point datasets along the network within an instream-distance threshold, with bidirectional dedup (a-side: each `table_a` row keeps its nearest `table_b`; b-side: each `table_b` row keeps its nearest `table_a` — losers get NULL). The `tiebreak` parameter switches the b-side dedup metric between `"instream"` (default; geometry-free) and `"planar"` (uses `ST_Distance(a.geom, b.geom)`, mirrors bcfp's tiebreak).

Live byte-identical validation against `bcfishpass.pscis.modelled_crossing_id` at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c` (tunnel `model_run_id=121` rebuilt 2026-05-05):
- **ADMS: 60 / 60 pairs byte-identical.**
- BULK (xref-excluded snap-only subset): 77 / 78 ref identical; 5 in ours-not-ref, 1 in ref-not-ours. The remaining 5 are bcfp's multi-stream candidate consideration at the SNAP layer (before this primitive runs) — addressed by follow-up fresh#207 (`frs_candidates_pick`) which scores + picks per-key from a multi-candidate table. With #206 + #207 composed, BULK becomes byte-identical too.

Parameter naming follows the `table_<role>` / `col_<role>` conventions established in this PR cycle: `table_a`, `table_b`, `table_to`, `col_a_id`, `col_b_id`, `tiebreak`, `distance_max`. Convention codified in link/CLAUDE.md.

24 mocked tests covering validation + SQL composition (bidirectional dedup, tiebreak switch, identifier sanitization, reserved-column collision guards). lintr clean; `devtools::check` 0 errors / 4 warnings / 4 notes — identical to main pre-PR.

First consumer is [link#154](https://github.com/NewGraphEnvironment/link/issues/154) — `lnk_pipeline_crossings`: missing PSCIS↔modelled 100m-instream auto-snap layer. Wires this primitive into link's per-WSG crossings build.

Closed by: PR TBD (squash + tag v0.30.0). Follow-ups: [fresh#207 frs_candidates_pick](https://github.com/NewGraphEnvironment/fresh/issues/207).
