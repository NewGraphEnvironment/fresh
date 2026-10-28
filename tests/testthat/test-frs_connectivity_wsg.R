# The connectivity passes run per job against a habitat table that may hold
# several watershed groups (one shared `to_habitat`), with only the job's own
# streams table. `id_segment` is unique only within a group, so every habitat
# join has to match `watershed_group_code` too, and every UPDATE has to be
# confined to the groups present in `table` (fresh#242).
#
# Each test asserts in both directions: the other group's colliding rows are
# untouched, and the other group's flags neither rescue nor condemn this
# group's. Each also asserts an expected keep AND an expected strip on this
# group, so neither a no-op nor a strip-everything mutant passes.
#
# The fixture is tests/testthat/helper-synthetic.R. Segments with
# `wscode = "100"` are all mutually "upstream" under the 4-arg
# `fwa_upstream(a, a, b, b)`, which is TRUE whenever `b <@ a`, equality
# included — so a segment that must be strippable goes on a separate river
# (`wscode = "200"`), which is not a descendant of `100`.

.cwb_run <- function(conn, species = "BT", distance_max = 3000,
                     spawn_connected = NULL, lake_adjacent = FALSE) {
  .frs_connected_waterbody(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    species = species,
    waterbody_poly = "whse_basemapping.fwa_lakes_poly",
    waterbody_ha_min = 1, bridge_gradient = 0.05,
    distance_max = distance_max, spawn_connected = spawn_connected,
    lake_adjacent = lake_adjacent, verbose = FALSE)
}

test_that("connected_waterbody never clears another group's spawning rows", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # TEST: rearing lake 11 on the mainstem, spawning on the mainstem below it
  # (kept), spawning on a separate river (stripped: not under wscode 100 and
  # no trace reaches it).
  segs <- rbind(
    .bkt_seg(1, 0, spawn = TRUE),
    .bkt_seg(2, 1000, wbk = 11, rear = TRUE),
    .bkt_seg(3, 0, spawn = TRUE, blk = 2L, wscode = "200", y = 5000))
  .bkt_fixture(conn, segs)
  # OTHR reuses id 3 with spawning TRUE. Its own streams live in another job's
  # table, so nothing here may touch it — today the subtractive UPDATE has no
  # group scope at all and wipes it.
  .bkt_habitat_add(conn, .bkt_seg(3, 0, spawn = TRUE))
  .cwb_run(conn)

  own <- .bkt_flags(conn, "spawning")
  expect_true(own[["1"]])                    # kept: upstream of rearing
  expect_false(own[["3"]])                   # stripped: neither phase reaches it
  expect_true(.bkt_flags(conn, "spawning", wsg = "OTHR")[["3"]])
})

test_that("connected_waterbody takes no trace origin from another group's rearing", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # TEST: rearing lake 11 on the mainstem with spawning above it (kept).
  # Lake 22 sits on a separate river with spawning just below it and is NOT
  # rearing for TEST, so that spawning must be stripped.
  segs <- rbind(
    .bkt_seg(1, 1000, wbk = 11, rear = TRUE),
    .bkt_seg(2, 2000, spawn = TRUE),
    .bkt_seg(3, 1000, wbk = 22, blk = 2L, wscode = "200", y = 5000),
    .bkt_seg(4, 0, spawn = TRUE, blk = 2L, wscode = "200", y = 5000))
  .bkt_fixture(conn, segs)
  # OTHR calls id 3 rearing. Today that makes lake 22 a Phase 1 trace origin
  # (and a `rearing_segs` row), which rescues TEST's id 4.
  .bkt_habitat_add(conn, .bkt_seg(3, 1000, rear = TRUE))
  .cwb_run(conn)

  own <- .bkt_flags(conn, "spawning")
  expect_true(own[["2"]])                    # kept: upstream of TEST rearing
  expect_false(own[["4"]])                   # stripped: lake 22 is not rearing here
})

test_that("the additive spawn_connected step promotes no other group's row", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Rearing lake 11, with an accessible non-spawning segment in the downstream
  # trace that meets the permissive spawn_connected thresholds, and one on a
  # separate river that no trace reaches.
  segs <- rbind(
    .bkt_seg(1, 1000, wbk = 11, rear = TRUE),
    .bkt_seg(2, 0),
    .bkt_seg(3, 0, blk = 2L, wscode = "200", y = 5000))
  .bkt_fixture(conn, segs)
  .bkt_habitat_add(conn, .bkt_seg(2, 0))
  .cwb_run(conn, spawn_connected = list(
    gradient_max = 0.05, channel_width_min = 5, edge_types_explicit = 1000))

  own <- .bkt_flags(conn, "spawning")
  expect_true(own[["2"]])                    # promoted: in the trace, meets thresholds
  expect_false(own[["3"]])                   # not promoted: no trace reaches it
  expect_false(.bkt_flags(conn, "spawning", wsg = "OTHR")[["2"]])
})
