# Code-check: Phase 5 (docs) round 2

Scope: the round-1 fixes (`.frs_label_expr()` boolean keys, NEWS / CLAUDE.md wording), one axis over. I re-verified every claim in the NEWS 0.40.0 entry, the CLAUDE.md "Point snap" section and the `exclude_edge_types` line against the code and `ALL_summary.csv`.

## Findings

- **[severity: bug]** NEWS.md (bullet 5), CLAUDE.md ("Point snap", bullet 4), R/frs_point_snap.R:13-14 and man/frs_point_snap.Rd: "The measure is clamped to the segment and rounded down to a whole metre."
  The round-1 rewording made this false in two ways. The SQL is `CEIL(GREATEST(ds, FLOOR(LEAST(us, x))))` (R/frs_point_snap.R, `.frs_point_snap_sql()`).
  - **It rounds up whenever the point projects into the first fractional metre of a segment.** There, `FLOOR(x) < ds`, so `GREATEST` returns `ds` and `CEIL` takes it up. 2,989,828 of the 4,540,721 candidate segments in fwapg (66%) have a fractional `downstream_route_measure`.
    - Reproduced on segment 702112618 (ds 34.645): a point at raw measure 34.745 snaps to **35**.
    - CLAUDE.md's next sentence (two segments at a vertex land 1 m apart) depends on exactly this round-up, so the section contradicts itself.
  - **"Clamped to the segment" fails for sub-metre segments with no whole metre inside.** On these, `CEIL(ds) > us`, so the measure is past the segment's upstream end. fwapg has 246 such candidate segments, e.g. 223015415 (ds 230666.67, us 230666.83), where every snap returns 230667.
  - This is the behaviour bcfishpass follows, so the code is not the problem; the docs misdescribe it. Accurate wording would be: "floored to a whole metre; when that falls below the segment's start, the start rounded up (so the result can exceed the upstream end of a segment shorter than a metre)".
  - Change it in all four places: NEWS, CLAUDE.md, roxygen, and the regenerated man page.

- **[severity: fragile]** R/frs_break.R:385-396, `.frs_label_expr()`. A boolean `label_col` mapped with the PostgreSQL literals that psql displays (`"t"` / `"f"`) silently mislabels. The same applies to the other boolean input literals (`"yes"`, `"on"`, `"1"`, ...).
  - Only `true` / `false` keys (any case) are normalised. `bool::text` is always `'true'` / `'false'`, so a `c("t" = "blocked")` key never matches. The CASE then falls to `ELSE b::text`, and the label comes out as `'true'`, which is not `label_block`, so the feature stops blocking access.
  - On main the same call errored (`invalid input syntax for type boolean: "blocked"`). Both behaviours were checked against local fwapg: main's `WHEN b = 't' ... ELSE b` errors, and the branch's `WHEN b::text = 't' ... ELSE b::text` returns `true` / `false`.
  - Why this is plausible: break sources point at DB tables (bcfishpass boolean columns), and psql prints those booleans as `t` / `f`.
  - Fix options:
    - Look up the column's type, and for a boolean compare `col = key::boolean`.
    - Reject keys that are boolean literals other than true/false.
    - At least document that boolean keys must be `"TRUE"` / `"FALSE"`.

## Type enumeration for `label_col::text` vs an R-written key

I wrote each type with `DBI::dbWriteTable` (RPostgres), so the column types are the ones RPostgres creates. I then compared `col::text` with `as.character()` of the R value, on fwapg with DateStyle `ISO, MDY` and TimeZone UTC.

| PG type (R source) | PG `::text` | R key | Natural key matches? |
|---|---|---|---|
| text / varchar (character, factor) | `A` | `"A"` | yes |
| integer (integer) | `1` | `"1"` | yes |
| bigint (integer64) | `1` | `"1"` | yes |
| smallint (table only) | `1` | `"1"` | yes |
| double precision (double) | `1`, `0.1`, `100000`, `1e+15` | `"1"`, `"0.1"`, `"1e+05"`, `"1e+15"` | Yes for typed keys. `as.character(1e5)` / `setNames(.., 1e5)` gives `"1e+05"`, which fails, but whole-number double codes of 100000 or more as labels are implausible. Not flagged. |
| numeric with scale (table only) | `1.0`, `1.50` | `"1"`, `"1.5"` | No. A numeric categorical label column is implausible. Not flagged. |
| boolean (logical) | `true` / `false` | `"TRUE"` / `"FALSE"` | Yes after the fix (lower()). `"t"` / `"f"` do not match: flagged above. |
| date (Date) | `2020-01-01` | `"2020-01-01"` | yes (ISO DateStyle) |
| timestamptz (POSIXct) | `2020-01-01 00:00:00+00` | `"2020-01-01"` | No (offset suffix, and R drops midnight times). Implausible as a label. Not flagged. |
| enum / bpchar (table only) | label text, trailing blanks stripped | label | yes (main errored for enum) |

On main, every non-text type errored in the CASE (its result type was the column's type), so each non-matching row above is an error turned into a silent fall-through. Only boolean is plausible in real use.

## Re-verified and correct

- **Parity counts** (`ALL_summary.csv`): 19,905 = 18,180 same + 22 tie + 11 link_999 + 1,692 neither. nf1_differ, link_only and fresh_only are all 0, so "no other differences" holds.
- **`exclude_edge_types` line (CLAUDE.md)**: correct. `.frs_snap_guards()` always includes `.frs_stream_guards()` (`localcode IS NOT NULL`, `NOT wscode <@ '999'`). NULL only drops the `edge_type NOT IN` predicate.
- **6010**: `fwa_indexpoint()` (fwapg definition) has `WHERE edge_type != 6010` and no 999, unmapped or 1425 guard. 137 of the 250 type-6010 segments pass fresh's guards.
  - So the NEWS lines are correct: `frs_watershed_split()` now excludes 1425, 999.* and unmapped segments, and can snap to 6010.
  - Main's `frs_watershed_split()` called `frs_point_snap(x =, y =)` with no blk or order arguments, so it took the `fwa_indexpoint` path.
- **`frs_watershed_split()`**: it snaps in one `frs_point_snap()` call, and its measures are integers (CEIL).
- **Migration hint**: `frs_point_snap(conn, x =, y =)` reaches `missing(points)`, and the positional numeric form reaches `is.numeric(points)`; both raise the hint. `frs_point_snap_knn()` was never exported (not in main's NAMESPACE), so its removal needs no NEWS line.
- **`frs_feature_find` NEWS bullets**:
  - Both paths write `feature_id` as text.
  - Integer and logical (`"TRUE"`) maps work, and the live tests pass (test-frs_break.R: FAIL 0 / PASS 79 against local fwapg).
  - "fails its checks or the snap": every check and `frs_point_snap()` run before `.frs_feature_find_write()` drops `to`.
- **CLAUDE.md per-segment claim**: link's `lnk_pipeline_pscis_build()` snaps with `num_features = 5` and scores per candidate row.

## Note (not flagged)

- "1,000 points are one round trip" (NEWS) and "10,000 points cost one round trip" (roxygen): a data frame takes a temp-table write, the snap query and the DROP, and a table input takes a check query plus the snap. That is a constant number of round trips rather than literally one.
