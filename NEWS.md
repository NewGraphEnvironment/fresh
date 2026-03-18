# fresh 0.3.1

- Add `from` and `extra_where` params to waterbody specs in `frs_network()` for filtering waterbodies to those connected to habitat streams ([#49](https://github.com/NewGraphEnvironment/fresh/issues/49))
- Network traversal table configurable via `.frs_opt("tbl_network")` ([#44](https://github.com/NewGraphEnvironment/fresh/issues/44))

# fresh 0.3.0

Server-side habitat model pipeline — replaces ~34 bcfishpass SQL scripts with 4 composable functions. See the [function reference](https://newgraphenvironment.github.io/fresh/reference/) for details.

- Add `frs_extract()` for staging read-only data to writable working schema ([#36](https://github.com/NewGraphEnvironment/fresh/issues/36))
- Add `frs_break()` family (`find`, `validate`, `apply`, wrapper) for network geometry splitting via `ST_LocateBetween` and `fwa_slopealonginterval` gradient sampling ([#38](https://github.com/NewGraphEnvironment/fresh/issues/38))
- Add `frs_classify()` for labeling features by attribute ranges, break accessibility (via `fwa_upstream`), and manual overrides — pipeable for multi-label classification ([#39](https://github.com/NewGraphEnvironment/fresh/issues/39))
- Add `frs_aggregate()` for network-directed feature summarization from points ([#40](https://github.com/NewGraphEnvironment/fresh/issues/40))
- Add `frs_col_generate()` to convert gradient/measures/length to PostgreSQL generated columns — auto-recompute after geometry changes ([#45](https://github.com/NewGraphEnvironment/fresh/issues/45))
- Add `.frs_opt()` for configurable column names via `options()` — foundation for spyda compatibility ([#44](https://github.com/NewGraphEnvironment/fresh/issues/44))
- All write functions return `conn` invisibly for consistent `|>` chaining

# fresh 0.2.0

- **Breaking:** All DB-using functions now take `conn` as the first required parameter instead of `...` connection args. Create a connection once with `conn <- frs_db_conn()` and pass it to all calls. Enables piping: `conn |> frs_break() |> frs_classify()` ([#35](https://github.com/NewGraphEnvironment/fresh/issues/35))

# fresh 0.1.0

- Multi-blue-line-key support for `frs_watershed_at_measure()` and `frs_network()` via `upstream_blk` param ([#20](https://github.com/NewGraphEnvironment/fresh/issues/20))
- Add `frs_watershed_at_measure()` for watershed polygon delineation with subbasin subtraction
- Add `frs_network()` unified multi-table traversal function replacing per-type fetch functions
- Add `frs_default_cols()` with sensible column defaults for streams, lakes, crossings, fish obs, and falls
- Add `upstream_measure` param for network subtraction between two points on the same stream
- Add `frs_waterbody_network()` for upstream/downstream lake and wetland queries via waterbody key bridge
- Add `wscode_col`, `localcode_col`, and `extra_where` params for custom table schemas
- Add `frs_check_upstream()` validation for cross-BLK network connectivity
- Add `blue_line_key` and `stream_order_min` params to `frs_point_snap()` for targeted snapping via KNN ([#16](https://github.com/NewGraphEnvironment/fresh/issues/16), [#17](https://github.com/NewGraphEnvironment/fresh/issues/17), [#7](https://github.com/NewGraphEnvironment/fresh/issues/7), [#18](https://github.com/NewGraphEnvironment/fresh/issues/18))
- Add stream filtering guards: exclude placeholder streams (999 wscode) and unmapped tributaries (NULL localcode) from network queries; `include_all` to bypass. Subsurface flow (edge_type 1410/1425) kept in network results (real connectivity) but excluded from KNN snap candidates ([#15](https://github.com/NewGraphEnvironment/fresh/issues/15))
- Add `frs_clip()` for clipping sf results to an AOI polygon, with `clip` param on `frs_network()` for inline use ([#12](https://github.com/NewGraphEnvironment/fresh/issues/12))
- Add `frs_watershed_split()` for programmatic sub-basin delineation from break points — snap, delineate, subtract with stable `blk`/`drm` identifiers ([#31](https://github.com/NewGraphEnvironment/fresh/issues/31))
- Security hardening: quote string values in SQL, validate table/column identifiers, clear error on missing PG env vars, gitignore credential files ([#19](https://github.com/NewGraphEnvironment/fresh/issues/19))
- Input type validation on all numeric params
- Add subbasin query vignette with tmap v4 composition
- Fix ref CTE to always query stream network, not target table

Initial release. Stream network-aware spatial operations via direct SQL against fwapg and bcfishpass. See the [function reference](https://newgraphenvironment.github.io/fresh/reference/) for details.
