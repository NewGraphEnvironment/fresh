# Backlog move 2: rules loading and persist validators (#319)

## Outcome

This move landed five fixes from backlog move 2 as v0.57.0. Three of them were things that went wrong silently.
- **Locale (#267):** the rules YAML is now read as UTF-8 whatever the session locale. Under C/POSIX the bundled file used to load with no rules.
- **Reservoirs (#250):** the `lake_rearing` bucket now reads lakes and manmade waterbodies, the same polygons an L rule's `rearing` predicate reads. This is a deliberate output change, by link#310 decision 5.
- **Floor (#251):** waterbody-connected spawning applies no area floor when the rule declares none. It used to apply 200 ha.

The other two make config and schema drift fail loudly:
- **Rules (#222):** `gradient` and `channel_width` must be a finite `[min, max]`, and empty rule keys and empty `channel_width_min_bypass` sub-keys are refused.
- **Targets (#222):** a `to_habitat` missing a flag column, or a `frs_feature_find()` target missing `feature_id`, gains the column, and one of the wrong type is refused.
- **`frs_col_join()` (#239, #222):** new columns take the source query's types, read from the prepared result's OIDs with `format_type()`. That covers subqueries, `ltree` and `geometry`, and resolves the name as the UPDATE does.

Two things were learned along the way:
- **Temp table dropped:** the plan's temp-table type probe was replaced by the OID probe, which needs no DDL and no temp privilege.
- **Narrow bare types:** code-check round 3 found that a bare `character` or `bit` means `char(1)` or `bit(1)`. They are now widened to the varying forms.

The legacy wide path `frs_habitat_species()` still reads lakes only, and is filed as #330.

## Measurement

- **Gate decisions:** #251 "no floor"; #222 "alter, refuse wrong type".
- **Branch tests on main's code:** every new test is red against `origin/main`'s R code (f3e331d) and green on the branch.
- **Direct #250 check on CHWK, CO and BT, fresh main against the branch:**
  - segmentation is identical (10,752 segments);
  - `accessible`, `spawning`, `rearing` and `wetland_rearing` are identical;
  - `lake_rearing` moved BT 162 → 182 (+20 rows on 2 reservoirs) and CO 184 → 208 (+24 rows on 4 reservoirs);
  - every difference is FALSE → TRUE on a manmade `waterbody_key`.
- **link's suite:** 1,492 tests, the same for every test against fresh main and against the branch, each side run from its own library. As the plan review predicted, no link test reads fresh's `lake_rearing` from a database, which is why the CHWK check above exists.
- **What link reaches:** 85 fresh functions, of which 11 changed. Each is neutral on link's path except the deliberate `lake_rear` change:
  - link's 24 rules files load identically, and all of them declare 200 ha for SK and KO;
  - link's `frs_col_join` columns get the same types (`double precision`, `text`, `integer`).
- **v0.41.0 golden predicates:** across 66 fixtures, every predicate is byte-identical except `lake_rear`, which gains exactly the reservoir arm at the same floor. The first full-suite run caught this; the test now pins it.
- **Full suite on the release commit d035ef3:** 2,962 expectations, 0 failures, 6 documented skips.
- **Code-check:** four rounds, ended on an enumeration:
  - rounds 1 and 2 were clean;
  - round 3 found the `char(n)`/`bit(n)` narrowing and an over-claim in CLAUDE.md;
  - round 4 found an over-claim inside round 3's doc fix;
  - the enumeration covered the 24 `pg_type` types that take a modifier, and the 6 sentences in the tree on `frs_col_join()` typing.
  - Five subagents ran on this task: the plan review and the four review rounds, rounds 2 and 3 in parallel. That is at the guideline of about five.
- The details are in `findings.md`, under "Measurements".

## Owed

- File a link issue covering four things:
  - `.lnk_discharge_join()` can drop its own `ADD COLUMN mad_m3s double precision` workaround once link pins ≥ 0.57.0 (#239);
  - the pin bump moves `lake_rearing` to include reservoirs (#250). Re-run `data-raw/pretest_run.sh` at that bump;
  - link's own #267: `names(yaml::read_yaml(rules_path))` in `lnk_config.R` reads nothing under the C locale;
  - stale text: `lnk_rollup_wsg.R` roxygen ("until that changes no reservoir is flagged") and `lnk_discharge.R`'s note on `frs_col_join()` typing text.

Closed by: PR (this branch, `319-backlog-move-2-rules-loading-and-persist`), release commit d035ef3.
