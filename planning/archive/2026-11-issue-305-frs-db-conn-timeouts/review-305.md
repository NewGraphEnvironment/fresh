# Plan review for #305 (Plan agent, spawned 2026-11-20T15:46:27Z)

Each finding with what was done about it. Verified means reproduced by the main session.

1. **Acceptance (Blocker for the proof step).** Dropping the 10 s default cannot make the silent-host test hang, because the test passes `connect_timeout = 2` explicitly. The mutation must stop `connect_timeout` reaching libpq at all. **Folded:** the Validation step now removes it from `.frs_conn_bounds()`'s output.
2. **Gap: a whole double passed through `...` reaches libpq in e-notation.** Verified: `tcp_user_timeout = 300000` failed live with `invalid integer value "3e+05"`. **Fixed:** `.frs_libpq_whole()` converts whole doubles to integer, or to plain text beyond integer range; tested, and the same call now connects live.
3. **Ordering: the plan put the bounds inside `.frs_conn_resolve()`**, whose share branch keeps only identity fields and whose tests assert exact `params`. **Folded:** the bounds are added in `frs_db_conn()` (as built); the Phase 2 text now says so.
4. **Assumption: a local tunnel is bounded only at connect.** Keepalives and acks come from the local ssh end. **Folded:** stated in the Timeouts section; the plan's "the silent-host case exactly" is corrected to "its connect phase".
5. **Assumption: the defaults override a `PGSERVICE` service file's keywords.** **Documented** in the Timeouts section, with the remedy (`NULL` in `...`, or an explicit `connect_timeout`). Not changed in behaviour: skipping the defaults under `PGSERVICE` would leave a service user with no bounds, which is the issue's defect. Reported in the PR.
6. **Acceptance: "skips within minutes" overstates it.** About 205 gate calls across 40 files, each up to `connect_timeout` per address (two for `localhost`). **Folded:** the CLAUDE.md wording says per gated test, per address.
7. **Gap: keepalives do not cover unacknowledged data; on macOS the retransmission timer governs.** **Documented** in the Timeouts section. No test makes an established connection go silent (needs packet loss); the live connect proves keyword acceptance only, which the PR says.
8. **Gap: `frs_habitat()` workers get the defaults, not the parent's `connect_timeout` or `...`.** **Documented** on `.frs_conn_params()`; filed as #312, not built.
9. **Scope: fine.** The only other `R/` connect sites are `frs_habitat.R:395` and `:581`, both covered.
