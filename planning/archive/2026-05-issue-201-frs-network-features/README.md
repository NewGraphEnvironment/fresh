## Outcome

Shipped `frs_network_features()` — direction-agnostic per-segment feature-array primitive. Generic over any FWA-snapped point dataset (barriers, observations, water-quality stations, fish surveys, etc.). Sibling to existing `frs_network_*` family but inverted shape: segments→features (per-segment arrays) rather than point→segments. SQL pattern mirrors `bcfishpass.load_dnstr` exactly (subquery-INNER-JOIN feeding outer GROUP BY with the canonical wscode/localcode/drm DESC ordering).

Live parity 5/5 byte-identical to bcfp's `streams_dnstr_*` precomputed tables (ADMS PSCIS 1031, BULK PSCIS 13046, HORS PSCIS 9256, ADMS dams 15195, ADMS anthropogenic 15534). 20 / 20 mocked unit tests pass. R CMD check completes cleanly after fixing a `.Rbuildignore` gap that was including 84 GB of `docker/postgres-data/` in the build tarball — that fix shipped alongside.

Approach restructure during exploration: dropped the original "two functions, one per direction" idea in favor of a single `direction = c("downstream", "upstream")` arg (required, no default). Also reframed the primitive at fresh's altitude rather than as link's private helper — the SQL pattern is dataset-agnostic and serves any future per-segment summary work.

Closed by: PR [#203](https://github.com/NewGraphEnvironment/fresh/pull/203) (squash `d15ab02`), v0.28.0.
