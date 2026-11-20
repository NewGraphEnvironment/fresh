# libpq connection bounds: what bounds a silent host, and how values reach libpq

**Verified:** 2026-11-20 · **Issues:** #305 (spawned #311, #312) · **Produced by:** probes recorded in `planning/archive/2026-11-issue-305-frs-db-conn-timeouts/` (RPostgres 1.4.10, bundled libpq 16.8, macOS)

## libpq waits without limit by default

- `connect_timeout` defaults to no limit. A host that completes the TCP handshake and then never answers (an SSH tunnel whose far end is gone, a listener that never accepts) blocks the connect indefinitely. Measured with a local `serverSocket()` that is never accepted: `connect_timeout = 2` gives `timeout expired` after 2.14 s; with no bound the call was still blocked when killed at 25 s, and in the mutation test at 60 s.
- libpq turns TCP keepalives on by default but leaves their timing to the OS. On macOS that is `net.inet.tcp.keepidle` 7,200,000 ms, `keepintvl` 75,000 ms, `keepcnt` 8: a dead established peer is noticed after about 2 h 10 m. fresh passes `keepalives_idle = 60`, `keepalives_interval = 10`, `keepalives_count = 6`, about 2 minutes.
- Keepalives probe only an idle socket. Once a query is sent and unacknowledged the OS retransmission timer governs instead; `tcp_user_timeout` shortens that, on Linux only.
- Through a local tunnel, keepalives and acknowledgements come from the tunnel's local end, so only the connect phase is bounded.
- A long query is not bounded by any of these: the server's kernel answers probes and acknowledges data while it works.

## libpq refuses what it does not know

- An unknown keyword fails the whole connect (`invalid connection option "..."`), so a successful live connect proves every keyword was accepted, and a default keyword newer than the oldest libpq a user may link breaks every connect for them. `tcp_user_timeout` exists only from PostgreSQL 12, so fresh does not send it by default (code-check round 1 on #305).
- `connect_timeout`, `keepalives`, `keepalives_idle`, `keepalives_interval` and `keepalives_count` are known to every libpq since 9.0.

## How R values become libpq text

RPostgres's `dbConnect()` turns every option into text with `as.character()` (via `unlist()`), and libpq parses that text:

- A whole double from 1e5 up prints in e-notation: `tcp_user_timeout = 300000` reached libpq as `"3e+05"` and was refused (`invalid integer value "3e+05"`). fresh converts whole doubles to integer first (`.frs_libpq_whole()`).
- `as.integer()` of a value above `.Machine$integer.max` is `NA`, which reaches libpq as `"NA"`: refused by libpq 16, but read as 0 (no limit) by a libpq before 12 that parses with `atoi()` (code-check round 2 on #305). fresh refuses such a `connect_timeout` in R.
- A value set through an environment variable (`PGCONNECT_TIMEOUT`) is parsed by libpq itself, so fresh leaves it alone rather than overriding it, except for `frs_habitat()` workers, which receive the parent's value explicitly.
