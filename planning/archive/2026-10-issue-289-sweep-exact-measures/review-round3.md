# Code-check round 3: branch 289 (git diff 7bfd156...HEAD, HEAD 9e3e455)

## Checklist read

- code-check.md: I read the prose of all 14 H3s under `## Mechanisms` and skipped the table rows. The 23 other headings I read in the index only.
- code-check-r.md, -shell.md, -spatial.md, -infra.md: I read the indexes only. I relied on the full text of the R sections that rounds 1 and 2 had already read: `sprintf("%g")`, driver types, `::text` spelling, Postgres row order and `on.exit()`. In spatial, "FWA `upstream_route_measure` misses the next segment's start" bears on the 957 case, and I checked it against the database directly.
- Scripts are in `/private/tmp/claude-501/-Users-airvine-Projects-repo-fresh/1131ec99-e8dc-43f4-be62-8dad0c8e2dd8/scratchpad/round3/`. `fmt_check.R` only reads. Every psql query was a SELECT against the local docker fwapg (PostgreSQL 17.5). Every text-to-double parse was done by PostgreSQL. I used R's parse only where the sweep itself uses it (`read.csv`), and checked that it equals PostgreSQL's.

## Mechanism

Each earlier defect is a claim about a population, or about a mechanism, that was derived from something other than the population or the consumer it describes:

- **"7 significant digits"** came from `format()` on one short vector.
- **"exactly the top"** came from comparing decimal text.
- **"14 to 16 digits"** was a reviewer's wording.
- **"every fresh code path"** came from #274's headline.
- **The Phase 2 plan text** described the design before it was built.

The assumption they share is that a sentence describing the right members, or the reasoning an earlier reader gave, holds for the whole population and for what fwapg actually does. No query was run against either. The mechanism reaches every quantifier and every causal "so" in the prose this branch adds. Round 3 finds five more instances of it:

- "not reachable", reasoned from "can round up".
- "and so in the gap", round 1's unexecuted explanation, adopted.
- "rounded them", extended from the CSV frame to every measure.
- "fresh's own code paths", the #274 headline. The sibling `chunked()` comment was narrowed in round 2; this one was not.
- "every element shows 7", the leftover of round 1's premise.

## Enumeration

| # | where | claim | source that settles it | verdict |
|---|---|---|---|---|
| 1 | script:41-42 | "Measures reach SQL at 17 significant digits ... and keys through %d, as on fresh's own code paths since #274" | R/frs_wsg_drainage.R:101 sends `dbQuoteLiteral(as.numeric(m))`, which is `957.704854270249::float8` (15 digits, run here). NEWS.md:9 says the same. | **false** (an unqualified universal) |
| 2 | script:42-43 | "the two CSVs of positions carry each measure as that same text" | `exact_m()` applies `.frs_sql_exact()` to the same double; chunked() errors keep `d$m[[j]]` | holds |
| 3 | script:43-46 | one `format()` over the whole frame; "11 decimals for the CSV measures"; "rounded at about 1e-11 m" | fmt_check.R: decimals = 11 over the 23,540 | holds |
| 4 | script:108-109 | head case "Before #289 this was an unscripted query" | findings / research | unverifiable (accepted) |
| 5 | script:289-290 | read-back "compared bit for bit" | `identical()` on m and blue_line_key at :294-296 | holds |
| 6 | script:317-323 | top = max over EVERY segment, because fwa_locatealong() has no guards | prosrc before the migration, and the migration file: the only predicates are blue_line_key and the rounded measures | holds |
| 7 | script:385-387 | ".frs_sql_exact() (%.17g), as frs_point_locate() and the network traversals send one since #274" | grep R/: frs_point_locate.R:33 and frs_network*.R use .frs_sql_exact | holds |
| 8 | script:387 | "format() ... rounds most measures" | 12,260 of 23,540 CSV measures (52%, measured). It rounded none of the 49,725 snapped positions or the 970 expensive positions, so 12,260 of about 74,200 over the sweep. | holds for the CSV frame only |
| 9 | script:461-463 | sent_exact: "Every row must join, and none may differ" | code at :476 | holds |
| 10 | script:513-514 | snapped positions are whole metres, "which every step writes exactly" | the guard at :515; %.17g of a whole number is exact | holds |
| 11 | script:534-535 | "covers the read, the format and the parse in one check" | `sent` is chunked()'s own `m_sent`, the vector `vals` is built from; PG `numeric -> float8` is correctly rounded | holds |
| 12 | script:683 | print() and write.csv() use 7 and 15 significant digits | R defaults | holds |
| 13 | test:64-66 | "Of 400 streams ... each sent at its own exact top, 0 resolve it before the migration and 383 after" | sweep.txt head-case table (base 0/400, tiebreak 383) | holds |
| 14 | test:68-69 | 360447231's candidate top is also its top over every segment | sweep_tops.csv row 311: m = m_guarded = 1528.8506958829107 | holds |
| 15 | research:3 | Verified line, Issues | none | holds |
| 16 | research:9 | before #274, `sprintf("%s")` "can round a stream's top *up*, past its last segment's end" | PG `extra_float_digits=0` (%.15g) over the 400 sampled tops: 188 round up | holds |
| 17 | research:9 | "so the head case below was not reachable through it" | Same query: **30 of 400** tops (25 of the 341 candidate tops) round-trip at 15 digits exactly. R `sprintf("%s")` on 654.973882925399 and 815.522245413245 gives the stored bits (`%a` matches `float8send`). | **false** |
| 18 | research:11 | 11 decimals; "moved 12,260 of the 23,540 by up to 5e-12 m" | fmt_check.R, parsed by PG: moved 12,260, max 5.002e-12 | holds |
| 19 | research:11 | "each state checks in SQL that the text parses back to the stored double" | sent_exact() is called per state for csv and tops | holds (not for snapped positions, which the whole-metre guard covers) |
| 20 | research:11 | "Only the CSV-measure counts moved; the snapped positions ... reproduce byte for byte" | log diff: only csv_locatealong_miss and the moved list changed; base md5 f0a5e96f... is unchanged; sweep_errors.csv is unchanged | holds |
| 21 | research:38-41 | 49,725 / 19,905 / 5,000 / 23,540 / 970 / 400 blue lines | sweep.txt | holds |
| 22 | research:42 | "Every measure is sent at 17 significant digits" | `chunked()` is the only sender | holds |
| 23 | research:42 | "the 2026-10-27 run rounded them to 11 decimals" ("them" = every measure) | Old `format()` was per frame. The snapped and expensive frames are whole metres, which went out with 0 decimals, exactly. That run had no tops. | **false** (only the CSV measures) |
| 24 | research:46-48 | table 36/31/31; 0; 85/86/86; 294/293/293 | sweep.txt / sweep_summary.csv | holds |
| 25 | research:50 | "Rounded to 11 decimals the CSV column read 42 / 38 / 38" | `git show 7bfd156:` sweep_summary.csv | holds |
| 26 | research:50-52 | "Shifts of at most 5e-12 m"; "a net 6 ... before ... and 7 after"; "hid one the migration fixes" | fmt_check.R; 42-36 and 38-31; crossings_365234 is absent from the old moved list | holds |
| 27 | research:62-65 | 400 by md5; top over every segment; 0 before, 383 after; 341 and 0 → 327; 17 (14) | sweep.txt, sweep_tops.csv | holds |
| 28 | research:66-67 | "2 before, 218 after" was unscripted and its writing unrecorded | accepted in round 1 | unverifiable (accepted) |
| 29 | research:67-70 | candidate top gives "345 tops and 2 before"; both lines' candidate top "sits below a later segment" | sweep_tops.csv: 345 non-NA m_guarded. 359014708: m_guarded 1244.37274 lies inside 115007619 (ds 1244.37271, us 1370.915). 359017843: 136.73120 lies inside 136080023 (ds 136.73101). "2 before" is accepted. | holds |
| 30 | research:71-74 | "5 CSV measures now resolve", the 5 named, "`sweep_changed.csv` carries each as the %.17g text sent" | sweep_changed.csv; R `%.17g` of R's parse of each, and R's parse equals PG's for all 536,831 CSV texts (fmt_check.R) | holds |
| 31 | research:75-76 | "3.4e-13 m below the top of segment 702605415 (957.70485427024937 ...)" | psql: us 0x408deda38aa2b956; sent is ...953, 3 ULPs, 3.41e-13 | holds |
| 32 | research:76 | "the CSV holds that top written at 15 significant digits" | crossings.csv row 365234 is `957.704854270249` | holds |
| 33 | research:76-77 | "which the old 4-decimal comparison cannot place" | round(us,4) = round(m,4) = 957.7049, and the comparison is strict | holds |
| 34 | research:77-78 | the next segment starts 0.5 mm higher, at 957.705341846863 | psql: 702605459 ds 957.705341846863, gap 0.488 mm | holds |
| 35 | research:78 | `957.70485427025`, "6.3e-13 m *above* that top" | As decimal text it is 6.29e-13 above. As PostgreSQL parses it, the value fwapg compares, it is **6.82e-13** (6 ULPs; psql and Python Decimal). In the same sentence, 3.4e-13 is a double-to-double difference. | holds for the text only (mixed instruments) |
| 36 | research:79 | "and so in the gap, missed in every state" | The migrated `fwa_locatealong()` picks its segment with `round(ds,4) <= round(m,4) AND round(us,4) >= round(m,4)`. For `957.70485427025` that is 957.7049, so it **picks 702605415**: it is not in any gap at that resolution. The miss is `ST_LocateAlong(702605415.geom, 957.70485427025)`, which returns 0 rows because the line's M ends at 957.7048542702494. At ...903 it returns 1 row (psql). | **false** (the outcome holds, the cause does not) |
| 37 | research:98 | "85 → 86 ... and 36 → 31 locatealong misses are the net" | sweep.txt | holds |
| 38 | #289 body | "`format()` uses one number of decimals for the whole vector, chosen so that every element shows 7 significant digits" | `format(c(0.000123456789, 1000.5))` gives `0.0001234568` / `1000.5000000000` (7 and 14 digits). Round 2 measured 0 to 18 digits across the 23,540. | **false as worded** ("at least 7, set by the element needing the most decimals") |
| 39 | #289 body | "11 decimals, which moved 12,260 of them by up to 5e-12 m" | fmt_check.R | holds |
| 40 | #289 body | the `format()` example gives `"1528.851" "4494.620"`; 957.70485427024903 becomes `"957.70485427025"` | R run here; round 1's rebuild | holds |
| 41 | #289 body | that covers "the CSV misses, the '4 CSV measures now resolve' list and the per-state tables" | The per-state tables' position and watershed columns were exact and did not move | overbroad (only their CSV column) |
| 42 | #289 body | snapped positions are whole metres, "so they are unaffected"; "the CSV measures and the 400-stream head-case sample are the ones in question" | the re-run: no position count moved | holds |
| 43 | #289 body | "Since #274, `frs_point_locate()` and the network traversals send route measures at 17 significant digits" | grep R/ | holds |
| 44 | task_plan:3 | the frame repeats rows 38-39, and "(lines 334-336)" | old file :334-336 is the `sprintf`/`format` block | row 38 **false as worded**; the rest holds |
| 45 | task_plan:9-11 | the correction note ("first said 7 significant digits ... measured 11 decimals") | round 1 | holds |
| 46 | task_plan:13-17 | snapped positions are unaffected; "Since #274 ..." | as rows 42-43 | holds |
| 47 | task_plan gate | 400 blue lines by md5; top over every segment; `m_guarded` carried; "%.17g ... in all three states" | script :325-340, :540-542 | holds |
| 48 | task_plan P1 | the read-back guard "`stopifnot(identical(...))`" | Implemented as `if (...) stop()`, which also checks blue_line_key | holds in substance |
| 49 | task_plan P1 | changed and errors CSVs written as %.17g | `write_exact()` | holds |
| 50 | task_plan P2 | `tie266_tops` is in `tbls`, "dropped at start and end" | :158, `drop_all()` at :164 and :843 | holds |
| 51 | task_plan P2 | smoke run green; round-trip guard passes | progress.md | unverifiable (logged) |
| 52 | task_plan P3 | header md5s match; "after the trials: unchanged"; b088b43 | sweep.txt header = old md5s | holds |
| 53 | task_plan P4 | NEWS moved to the PR body; "corrects 0.44.0's 'four of 23,540'" | NEWS.md:86 says "four of 23,540" | holds (accepted) |
| 54 | task_plan ctx | "about 50 minutes: base 1082 s, tiebreak 959 s, both 913 s" | old header, 2,954 s | holds |
| 55 | task_plan ctx | md5s `a048f8e2…`, `98d84a33…`; un-migrated, 4,907,441 segments | sweep.txt | holds |
| 56 | task_plan ctx | keys from `format()` already exact; `write.csv()` uses 15 digits | R | holds |

## Findings

- **[severity: fragile]** research/fwa_point_snap.md:9. "so the head case below was not reachable through it" is false. The sentence was added on this branch.
  - Over the sweep's own 400 sampled tops, 30 are written at 15 significant digits that parse back to the stored double (PostgreSQL `extra_float_digits = 0`). That is 25 of the 341 candidate tops. Two were spot-checked against R's `sprintf("%s")` bit for bit.
  - Through the old `frs_point_locate()` the exact head was reachable for about 7.5% of streams. Of the rest, 188 rounded up past the end and 182 rounded down inside the top segment.
  - The fix is to say that it rounds most tops off the top, about half of them past the end, and to drop "not reachable".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (an unqualified quantifier, and an unexecuted causal claim)

- **[severity: fragile]** research/fwa_point_snap.md:78-79. "6.3e-13 m *above* that top and so in the gap, missed in every state" names the wrong cause. The cause came from round 1's review ("in the 0.5 mm gap ... That is why the old run missed it") and was adopted without being run.
  - The migrated `fwa_locatealong()` compares 4-decimal bounds with the top closed, so `957.70485427025` (957.7049) selects segment 702605415, not a gap.
  - It misses because `ST_LocateAlong()` on that segment returns no point past its last M, 957.7048542702494. psql gives 0 rows at `...025` and 1 row at `...903`.
  - The 6.3e-13 is also measured on the decimal text. PostgreSQL reads it as 6.82e-13 above the top, and fwapg compares that value. The 3.4e-13 in the same sentence is a double-to-double difference.
  - The outcome ("missed in every state") holds. The fix is "6.8e-13 m above that top, past the segment's last M, so `ST_LocateAlong()` returns nothing".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a reviewer's prescribed wording is an unexecuted claim); code-check.md "One fact derived twice" (two instruments in one sentence)

- **[severity: fragile]** research/fwa_point_snap.md:42. "Every measure is sent at 17 significant digits (fresh#289; the 2026-10-27 run rounded them to 11 decimals)" is false for "them".
  - The old `format()` ran per frame. The 49,725 snapped positions and the 970 expensive positions went out with no decimals, which is exact.
  - That run had no tops.
  - Only the 23,540 CSV measures were rounded to 11 decimals. Line 11 already says so correctly.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a compression that gained a quantifier)

- **[severity: fragile]** data-raw/point_snap_tie_sweep.R:41-42. "Measures reach SQL at 17 significant digits (.frs_sql_exact()) and keys through %d, as on fresh's own code paths since #274" is an unqualified universal, and it is false.
  - `frs_wsg_drainage()` (R/frs_wsg_drainage.R:101) sends measures at 15 digits through `dbQuoteLiteral()`. Run here: `957.704854270249::float8`. NEWS.md:9 says the same.
  - Round 2 narrowed the sibling sentence in `chunked()` (:385) to "frs_point_locate() and the network traversals" and judged this one acceptable. Both make the same claim, and only one was fixed.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** #289 issue body, and planning/active/task_plan.md:3 (the copied frame). "`format()` uses one number of decimals for the whole vector, chosen so that every element shows 7 significant digits" is false as worded.
  - The decimal count is set by the element that needs the most decimals to show 7. Every other element shows more: 322.567 went out as `322.56700000000`, and round 2 measured 0 to 18 digits.
  - This is the remainder of round 1's 7-digit premise.
  - The fix is to write "enough decimals that the element needing the most shows 7 significant digits".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- Minor, no fix required:
  - The #289 body's "and the per-state tables" covers columns that were exact and did not move (row 41).
  - The `chunked()` comment's "rounds most measures" holds only for the CSV frame (row 8).

No code defect was found in data-raw/point_snap_tie_sweep.R or in tests/testthat/test-frs_fwapg_gate.R. The script's guards are sound: the read-back, `sent_exact()` on chunked()'s own `sent`, the whole-metre check, the table order, and `write_exact()` quoting. Every log figure in the note re-derives from the committed logs or the database.
