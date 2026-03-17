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
