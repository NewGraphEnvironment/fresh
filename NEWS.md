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
- Input type validation on all numeric params
- Add subbasin query vignette with tmap v4 composition
- Fix ref CTE to always query stream network, not target table

Initial release. Stream network-aware spatial operations via direct SQL against fwapg and bcfishpass. See the [function reference](https://newgraphenvironment.github.io/fresh/reference/) for details.
