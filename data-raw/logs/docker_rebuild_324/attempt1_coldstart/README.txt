Attempt 1, 2026-11-24 18:17Z: stopped at stage 1 with "Connection refused" ~30 s in.
The compose healthcheck (pg_isready over the Unix socket) reported healthy while
the image init ran its socket-only temporary server. Fixed by checking over TCP
(pg_isready -h 127.0.0.1) with start_period: 15m; attempt 2 is the run beside this.
