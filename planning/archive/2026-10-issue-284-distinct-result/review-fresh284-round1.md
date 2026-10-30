# Review: fresh 284-distinct-result (aabba77 over 7aedbe3), round 1

## Checklist read

No checklist file is under 40,000 bytes, so none was read in full.

- code-check.md (334,881 bytes): I read the prose of all 14 H3s under `## Mechanisms`, skipping the `|` table rows. I read no heading under "Rules that stand alone", Security, or Spreadsheets and PDFs; none of them covers a tool or shape this diff uses.
- code-check-r.md (190,768 bytes): I read 8 headings: "Postgres row order is never fixed unless the query fixes it…", "A database driver's value is not a base R type — and it fails twice", "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's", "`sort()` and `order()` collate by `LC_COLLATE`…", "A `function(...)` mock hides arguments…", "`expect_false(identical(x, y))` cannot fail…", "`paste()` with a zero-length argument…", and "An `information_schema` lookup by the literal table name…". The remaining 140 or so headings (base R, spatial, rendering, packaging) are about tools and patterns this diff does not touch, so I did not read them.
- code-check-shell.md (131,937 bytes): read none. The diff has no shell.
- code-check-spatial.md (155,517 bytes): read none. The diff's SQL calls `fwa_upstream()` and `fwa_downstream()` through the existing walk, but no spatial heading names this diff's pattern.
- code-check-infra.md (41,794 bytes): read none. Its tools do not apply, as stated in the brief.

## Clean

I found no issues.

What I checked, beyond reading the diff:

- **Tests:** I ran them in a detached worktree at aabba77, which is now removed.
  - The unit file `test-frs_network_features.R` passes. The four `distinct` and `result` tests made 1 + 16 + 24 + 2 expectations, with 0 failures and 0 errors.
  - The live test "result = "distinct" returns unique() of the array walk's ids (SKGT)" passes against the local fwapg (PostgreSQL 17.5): 24 expectations, 0 failures, run with `NOT_CRAN=true`.
- **Rows and NULL ids match `"ids"`.**
  - `"distinct"` groups by `a.<segment id>` over the same `walk_from` as `"ids"`, so it returns the same segments, including duplicate segment rows collapsed by GROUP BY.
  - `FILTER (WHERE id IS NOT NULL)` keeps a segment whose only features have NULL ids, with an empty array. `.frs_parse_pg_array(NA)` turns that into `character(0)`, exactly as `"ids"` does.
- **The temp table is still dropped.** On the scoped downstream path, `return(res)` inside the `distinct` branch still runs the `on.exit` DROP.
- **Cost:** `array_agg(DISTINCT … ORDER BY …)` under GROUP BY forces a sort of all segment and feature pairs (PostgreSQL 17 sorts them once, as a presorted aggregate). I suspected this might cost more than the hash `SELECT DISTINCT` the issue measured. The caller's own measurement of this function answers that: `link/data-raw/logs/obs_province_401/walk_fresh_distinct.csv` gives LFRA 37–39 s, SETN 44–46 s and BULK 8 s. Those match the issue's `SELECT DISTINCT` figures (32/35, 46/46, 9/9 s).

## Notes (not findings)

- **A text id that Postgres quotes in array output comes back with its quotes.** Postgres quotes an element that has leading or trailing whitespace or contains a comma, brace, quote or backslash, and `.frs_parse_pg_array()` returns such an element with its quotes, for example `"\" RB\""`. Real data reaches this: `bcfishobs.observations` holds the species code `' RB'`.
  - The parser and its limitation already exist and are documented in `@return` for `"ids"`. link already walks `species_code` under `"ids"`, and its `o.species_code IN (...)` filter keeps `' RB'` out.
  - Not a defect of this diff. It is more reachable now, because `"distinct"` is documented for kinds such as species codes, which are text.
- **The array's order follows the column's collation.** For a text id, that is the database collation (`en_US.utf8` on the local fwapg), not C order. Nothing in fresh or in link's consumer (membership) reads the order, so this is not a defect. The roxygen does say "in its SQL type's order".
- **The live test compares through a double.** It builds its expectation with `as.character(sort(unique(as.numeric(x))))`. A `blue_line_key` with about six trailing zeros would print as `"3.6e+08"` and fail falsely; see "A value compared as `::text`…". On the SKGT fixture the test passes, so this is latent and test-only.
