# fresh#293 — a custom-AOI job must delete only the ground it will reinsert,
# from the shared habitat table and from the shared near_river table, and the
# reads of those tables must distinguish two jobs' rows inside one group once
# the delete stops removing one of them.

# --- The delete statement, no database --------------------------------------

test_that("a subset delete carries the extra predicate and a whole-group delete does not", {
  cols <- c("id_segment", "watershed_group_code", "linear_feature_id",
            "species_code")
  sub <- .frs_persist_delete_sql("fresh.hab", "working.streams", NULL,
    cols, cols, extra_subset = "species_code IN ('CO')")
  expect_match(sub,
    "linear_feature_id IN (SELECT linear_feature_id FROM working.streams)",
    fixed = TRUE)
  expect_match(sub, "species_code IN ('CO')", fixed = TRUE)

  # A whole-group delete is a wholesale replace and is the repair path for
  # damage already done, so it must stay unscoped: scoping it by species makes
  # the staged backfill un-completable, because rows for a species no longer
  # modelled would keep a NULL key for ever (#293 review, F2).
  grp <- .frs_persist_delete_sql("fresh.hab", "working.streams", "ADMS",
    cols, cols, extra_subset = "species_code IN ('CO')")
  expect_match(grp, "watershed_group_code = 'ADMS'", fixed = TRUE)
  expect_false(grepl("species_code", grp, fixed = TRUE))
})

test_that("the key-match predicate adds linear_feature_id only when asked", {
  with_lfid <- .frs_key_match("h", "s", TRUE)
  expect_match(with_lfid, "h.id_segment = s.id_segment", fixed = TRUE)
  expect_match(with_lfid, "h.watershed_group_code = s.watershed_group_code",
               fixed = TRUE)
  expect_match(with_lfid, "h.linear_feature_id = s.linear_feature_id",
               fixed = TRUE)
  without <- .frs_key_match("h", "s", FALSE)
  expect_match(without, "h.id_segment = s.id_segment", fixed = TRUE)
  expect_false(grepl("linear_feature_id", without, fixed = TRUE))
})

test_that("the near_river predicate keys on the parent segment when it can", {
  nr <- list(measure = "discharge", threshold = 3, distance_max = 1000)
  keyed <- .frs_near_river_sql(nr, "fresh.hab_near_river", lfid = TRUE)
  expect_match(keyed, "n.linear_feature_id = s.linear_feature_id",
               fixed = TRUE)
  plain <- .frs_near_river_sql(nr, "fresh.hab_near_river", lfid = FALSE)
  expect_false(grepl("linear_feature_id", plain, fixed = TRUE))
  # Both still carry the pair's own numbers and the group.
  for (sql in list(keyed, plain)) {
    expect_match(sql, "n.watershed_group_code = s.watershed_group_code",
                 fixed = TRUE)
    expect_match(sql, "n.measure = 'discharge'", fixed = TRUE)
  }
})

test_that("an empty pair list narrows the delete to nothing, not to everything", {
  # .frs_persist_delete_sql() reads a NULL extra_subset as "do not narrow", so
  # returning NULL here would widen the delete to every pair on the job's
  # ground while the loop wrote none back — this issue's loss, produced by the
  # helper added to prevent it (round 2 of /code-check). The sibling in
  # frs_habitat_classify() skips the delete instead; both refuse to widen.
  expect_identical(
    .frs_near_river_pairs_in(character(0), numeric(0), numeric(0)), "FALSE")
  one <- .frs_near_river_pairs_in("discharge", 3, 1000)
  expect_match(one, "(measure, threshold, distance_max) IN (('discharge'",
               fixed = TRUE)
})

test_that("the predicate builder refuses to guess the near_river key", {
  # A rule that actually carries a near_river pair, or the predicate never
  # reaches .frs_near_river_sql() and both keys compile to the same text —
  # an assertion that cannot fail (code-check.md).
  sp <- list(species_code = "CH", spawn_gradient_min = 0,
             spawn_gradient_max = 0.0449,
             params_sp = list(
               ranges = list(rear = list(channel_width = c(1.5, 9999),
                                         gradient = c(0, 0.0549))),
               rules = list(rear = list(list(
                 edge_types_explicit = 1000,
                 near_river = list(discharge_min = 3,
                                   distance_max = 1000))))))
  # Pure and with no connection, so it cannot look at the tables. Defaulting
  # would hand a caller re-deriving the predicate 0.53.0's short key by
  # omission while the table it reads has begun holding two jobs' rows — which
  # is exactly how link's habitat validator calls it (round 3 of /code-check).
  expect_error(
    frs_habitat_predicates(sp, near_river_table = "w.streams_near_river"),
    "near_river_lfid must be given")
  # Nor does anything else stand in for an answer: isTRUE() alone would read
  # each of these as FALSE, the short key (round 5 of /code-check).
  for (bad in list(NA, "TRUE", c(TRUE, TRUE), 1)) {
    expect_error(
      frs_habitat_predicates(sp, near_river_table = "w.streams_near_river",
                             near_river_lfid = bad),
      "near_river_lfid must be TRUE or FALSE")
  }
  # Both answers are accepted, and they differ.
  with_key <- frs_habitat_predicates(sp,
    near_river_table = "w.streams_near_river", near_river_lfid = TRUE)
  without <- frs_habitat_predicates(sp,
    near_river_table = "w.streams_near_river", near_river_lfid = FALSE)
  expect_match(with_key$rear, "n.linear_feature_id = s.linear_feature_id",
               fixed = TRUE)
  expect_false(grepl("linear_feature_id", without$rear, fixed = TRUE))
  expect_false(identical(with_key, without))
  # And no table means no question to answer, so the common call is unchanged.
  # A species whose rules carry no near_river pair, since one that does
  # already refuses a NULL table for its own reason.
  plain <- list(species_code = "CO", spawn_gradient_min = 0,
                spawn_gradient_max = 0.05,
                params_sp = list(spawn_gradient_max = 0.05,
                                 ranges = list(rear = list(
                                   gradient = c(0, 0.05)))))
  expect_no_error(frs_habitat_predicates(plain))
})

# --- The read side, on a synthetic network ----------------------------------

test_that("a stale same-group near_river row for another parent is not read", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.nr_near",
    threshold = 3, distance_max = 1000, verbose = FALSE)

  # Another job's row, same group, at an id_segment this job's table uses, for
  # a parent segment this job does not hold. Once the delete stops removing
  # whole groups this is what the table can hold, and it is a row the reads
  # must not treat as this job's: 81 of 275 derived ids on a measured job
  # equalled a real same-group linear_feature_id (research/id_segment_identity.md).
  stale_id <- DBI::dbGetQuery(conn,
    "SELECT min(id_segment) AS id FROM pg_temp.nr_streams
      WHERE id_segment NOT IN (SELECT id_segment FROM pg_temp.nr_near)")$id
  expect_false(is.na(stale_id))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO pg_temp.nr_near (id_segment, linear_feature_id,
       watershed_group_code, measure, threshold, distance_max, dist_m)
     VALUES (%d, -999, 'TEST', 'discharge', 3, 1000, 1)", stale_id))

  nr <- list(measure = "discharge", threshold = 3, distance_max = 1000)
  n_matched <- function(lfid) {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int AS n FROM pg_temp.nr_streams s
        WHERE s.id_segment = %d AND %s", stale_id,
      .frs_near_river_sql(nr, "pg_temp.nr_near", lfid = lfid)))$n
  }
  # The collision is live — assert it before asserting the fix, or a predicate
  # that matched nothing at all would satisfy this test.
  expect_identical(n_matched(FALSE), 1L)
  expect_identical(n_matched(TRUE), 0L)
})

# --- End to end, against the Freshwater Atlas -------------------------------

# The documented custom-AOI example's sub-basin, and a tributary strictly
# inside it. Both are in one watershed group, so a whole-group delete run for
# the inner one removes every row the outer one wrote.
.p293_aoi_outer <-
  "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"
.p293_aoi_inner <-
  "wscode_ltree <@ '100.190442.999098.995997.058910.432966.284811'::ltree"

test_that("a custom-AOI classify keeps the group's rows for ground outside the AOI", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  tgt <- frs_test_tbl("p293_streams")
  hab <- frs_test_tbl("p293_habitat")
  solo <- frs_test_tbl("p293_solo_habitat")
  solo_s <- frs_test_tbl("p293_solo_streams")
  tbls <- c(tgt, hab, solo, solo_s, paste0(hab, "_near_river"),
            paste0(solo, "_near_river"),
            vapply(c("p293a", "p293b", "p293c"), frs_test_label_tbl, ""))
  on.exit({
    for (t in tbls) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", t))
    }
    DBI::dbDisconnect(conn)
  })
  for (t in tbls) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", t))
  }
  n_of <- function(t) {
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", t))$n
  }
  run <- function(label, aoi, streams, habitat) {
    frs_habitat(conn, aoi = aoi, species = "CO", label = frs_test_label(label),
      to_streams = streams, to_habitat = habitat, verbose = FALSE)
  }

  # The inner AOI on its own: the rows one such job writes, and the near_river
  # rows its walk finds. The walk reads only the job's own working table, so
  # these are the same numbers the shared run below will write for it.
  r_solo <- run("p293c", .p293_aoi_inner, solo_s, solo)
  n_solo <- n_of(solo)
  nr_solo <- if (!is.na(DBI::dbGetQuery(conn, sprintf(
    "SELECT to_regclass('%s_near_river')::text AS r", solo))$r)) {
    n_of(paste0(solo, "_near_river"))
  } else {
    NA_integer_
  }

  # The outer AOI, then the inner one, into one shared pair of tables.
  r_outer <- run("p293a", .p293_aoi_outer, tgt, hab)
  n_outer <- n_of(hab)
  expect_equal(n_outer, r_outer$n_segments)

  r_inner <- run("p293b", .p293_aoi_inner, tgt, hab)

  # The condition the test rests on: the inner AOI is a strict subset, so a
  # correct overwrite replaces part of the table and leaves the rest.
  expect_lt(r_inner$n_segments, r_outer$n_segments)

  # One species, one row per segment, and the inner run replaces only its own
  # ground — so the total is unchanged. Before the fix it is the inner run's
  # count alone, because the whole group was deleted.
  expect_equal(n_of(hab), n_outer)

  if (!is.na(nr_solo)) {
    expect_gt(n_of(paste0(hab, "_near_river")), nr_solo)
  }

  # Two jobs' rows now coexist in one group, which is the state the reads have
  # to cope with (#293 review, B1). Assert it reached the table, so the read
  # tests above are about something real.
  expect_gt(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM (
       SELECT 1 FROM %s GROUP BY id_segment, watershed_group_code, species_code
       HAVING count(*) > 1) z", hab))$n, 0)
})

test_that("a habitat target that cannot carry the key is refused, naming the repair", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_hab")
  # A habitat table written before #293: no linear_feature_id, and rows that
  # no partition delete keyed on it could ever address.
  DBI::dbExecute(conn, "CREATE TABLE pg_temp.p293_hab (id_segment integer,
    watershed_group_code varchar(4), species_code text, accessible boolean,
    spawning boolean, rearing boolean, lake_rearing boolean,
    wetland_rearing boolean)")
  DBI::dbExecute(conn, "INSERT INTO pg_temp.p293_hab VALUES
    (1, 'TEST', 'CO', TRUE, FALSE, TRUE, FALSE, FALSE)")
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)

  expect_error(
    frs_habitat_classify(conn, table = "pg_temp.nr_streams",
      to = "pg_temp.p293_hab", species = "CO", params = params,
      gate = FALSE, verbose = FALSE),
    "linear_feature_id")
  # Refused before anything was written, as the near_river checks are.
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_hab")$n, 1L)

  # The repair the message names: a whole-group run replaces the group and
  # writes the key back for it.
  expect_no_error(frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_hab", species = "CO", params = params,
    wsg_code = "TEST", gate = FALSE, verbose = FALSE))
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_hab
      WHERE linear_feature_id IS NULL")$n, 0L)
})

test_that("a network with no linear_feature_id still classifies on id_segment", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  for (t in c("pg_temp.p293_nofwa", "pg_temp.p293_nofwa_habitat")) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
  }
  DBI::dbExecute(conn, "CREATE TABLE pg_temp.p293_nofwa (
    id_segment integer, watershed_group_code varchar(4),
    blue_line_key integer, downstream_route_measure double precision,
    wscode_ltree ltree, localcode_ltree ltree, edge_type integer,
    waterbody_key integer, gradient double precision,
    channel_width double precision)")
  DBI::dbExecute(conn, "INSERT INTO pg_temp.p293_nofwa VALUES
    (1, 'TEST', 1, 0, '100'::ltree, '100'::ltree, 1000, NULL, 0.01, 5)")
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)

  run <- function() {
    frs_habitat_classify(conn, table = "pg_temp.p293_nofwa",
      to = "pg_temp.p293_nofwa_habitat", species = "CO", params = params,
      gate = FALSE, verbose = FALSE)
  }
  expect_no_error(run())
  # No column invented on either side, and re-running replaces rather than
  # appends — on id_segment, the only identity such a network has.
  have <- names(DBI::dbGetQuery(conn,
    "SELECT * FROM pg_temp.p293_nofwa_habitat LIMIT 0"))
  expect_false("linear_feature_id" %in% have)
  n1 <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nofwa_habitat")$n
  expect_no_error(run())
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nofwa_habitat")$n, n1)

  # fresh#225, then fresh#308: a row with NO watershed group. #293 made the
  # delete address it (it once appended a copy per run), but every read
  # equates the group, so the row was written and then never read. It is now
  # refused before anything is written, and the existing rows stand.
  DBI::dbExecute(conn, "INSERT INTO pg_temp.p293_nofwa VALUES
    (2, NULL, 1, 1000, '100'::ltree, '100'::ltree, 1000, NULL, 0.01, 5)")
  expect_error(run(), "no watershed_group_code")
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nofwa_habitat")$n, n1)
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nofwa_habitat
      WHERE watershed_group_code IS NULL")$n, 0L)
})

test_that("wsg_code must be the one group the table holds", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_wsg_hab")
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)
  # A whole-group delete on a table that is not the whole group is #293
  # reintroduced through the new parameter.
  expect_error(
    frs_habitat_classify(conn, table = "pg_temp.nr_streams",
      to = "pg_temp.p293_wsg_hab", species = "CO", params = params,
      wsg_code = "OTHR", gate = FALSE, verbose = FALSE),
    "OTHR")
  expect_error(
    frs_habitat_classify(conn, table = "pg_temp.nr_streams",
      to = "pg_temp.p293_wsg_hab", species = "CO", params = params,
      wsg_code = c("TEST", "OTHR"), gate = FALSE, verbose = FALSE),
    "one watershed group")
})

test_that("a near_river target that cannot carry the key is refused", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_nr")
  # A near_river table written before #293: the right measure columns, no
  # linear_feature_id, against a streams table that has one.
  DBI::dbExecute(conn, "CREATE TABLE pg_temp.p293_nr (id_segment integer,
    watershed_group_code varchar(4), measure text, threshold double precision,
    distance_max double precision, dist_m double precision)")
  DBI::dbExecute(conn, "INSERT INTO pg_temp.p293_nr VALUES
    (1, 'TEST', 'discharge', 3, 1000, 1)")
  expect_error(
    frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nr",
      threshold = 3, distance_max = 1000, verbose = FALSE),
    "Drop pg_temp.p293_nr and re-run")
  # Refused before anything was written.
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nr")$n, 1L)
  # And the reverse: a target carrying the key against a streams table that
  # does not is the same mismatch, not a silent fall back to id_segment.
  DBI::dbExecute(conn, "ALTER TABLE pg_temp.p293_nr ADD COLUMN linear_feature_id bigint")
  DBI::dbExecute(conn, "ALTER TABLE pg_temp.nr_streams DROP COLUMN linear_feature_id")
  expect_error(
    frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nr",
      threshold = 3, distance_max = 1000, verbose = FALSE),
    "has no key both tables share")
})

test_that("classifying one species leaves another species' rows for the same ground", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_sp")
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)
  run <- function(sp) {
    frs_habitat_classify(conn, table = "pg_temp.nr_streams",
      to = "pg_temp.p293_sp", species = sp, params = params, gate = FALSE,
      verbose = FALSE)
  }
  n_of <- function(sp) {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int AS n FROM pg_temp.p293_sp
        WHERE species_code = '%s'", sp))$n
  }

  run(c("CO", "BT"))
  n_co <- n_of("CO")
  n_bt <- n_of("BT")
  expect_gt(n_co, 0)
  expect_gt(n_bt, 0)

  # A CO-only re-run replaces CO's rows and leaves BT's, which is what
  # `overwrite` documents. Before #293 the whole group went.
  run("CO")
  expect_identical(n_of("CO"), n_co)
  expect_identical(n_of("BT"), n_bt)
})

test_that("a failure during classify leaves the partition as it was", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_tx")
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)
  run <- function() {
    frs_habitat_classify(conn, table = "pg_temp.nr_streams",
      to = "pg_temp.p293_tx", species = "CO", params = params, gate = FALSE,
      verbose = FALSE)
  }
  run()
  n0 <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_tx")$n
  expect_gt(n0, 0)

  # The delete and the inserts are one transaction, so an insert that fails
  # cannot leave the partition deleted and not written back. Make the second
  # species' insert fail after the first has run: a two-species call deletes
  # once and then inserts per species.
  calls <- 0L
  deletes <- 0L
  local_mocked_bindings(.frs_db_execute = function(conn, sql) {
    if (grepl("DELETE FROM pg_temp.p293_tx", sql, fixed = TRUE)) {
      deletes <<- deletes + 1L
    }
    if (grepl("INSERT INTO pg_temp.p293_tx", sql, fixed = TRUE)) {
      calls <<- calls + 1L
      if (calls == 2L) stop("boom")
    }
    DBI::dbExecute(conn, sql)
  })
  expect_error(frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_tx", species = c("CO", "BT"), params = params,
    gate = FALSE, verbose = FALSE), "boom")
  # The conditions the assertion rests on: a delete ran and was rolled back,
  # which is not the same as no delete running at all, and one insert ran.
  expect_identical(deletes, 1L)
  expect_identical(calls, 2L)
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_tx")$n, n0)
})

test_that("a call that classifies no species deletes nothing", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_none")
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)
  frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_none", species = "CO", params = params,
    gate = FALSE, verbose = FALSE)
  n0 <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_none")$n
  expect_gt(n0, 0)

  # A species with no parameters classifies nothing, so the loop writes
  # nothing — and a delete that removes rows nothing replaces is the whole of
  # this issue. `extra_subset` from an `if` with no `else` would be NULL here,
  # which reads as "every species" (round 1 of /code-check).
  expect_no_error(frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_none", species = "ZZZ", params = params,
    gate = FALSE, verbose = FALSE))
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_none")$n, n0)
})

test_that("classify runs inside a transaction the caller already opened", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit({
    try(DBI::dbRollback(conn), silent = TRUE)
    DBI::dbDisconnect(conn)
  })
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_nest")
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)
  # RPostgres refuses a nested dbBegin() with "Nested transactions not
  # supported." — capital N, plural — so a fixed, lower-case, singular match
  # never fires and a caller already holding a transaction was refused
  # outright (round 1 of /code-check).
  DBI::dbBegin(conn)
  expect_no_error(frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_nest", species = "CO", params = params,
    gate = FALSE, verbose = FALSE))
  expect_gt(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nest")$n, 0)
  DBI::dbRollback(conn)
})

test_that("a near_river row the delete cannot address is refused before the delete", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_nrg")
  frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nrg",
    threshold = 3, distance_max = 1000, verbose = FALSE)
  n0 <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nrg")$n
  expect_gt(n0, 0)
  # A row with no parent is one no partition delete can ever address. The
  # guard has to run before the delete, not after: raising afterwards has
  # already lost the rows it exists to protect, and the walk never writes
  # them back (round 1 of /code-check).
  DBI::dbExecute(conn, "INSERT INTO pg_temp.p293_nrg
    (id_segment, linear_feature_id, watershed_group_code, measure, threshold,
     distance_max, dist_m)
    VALUES (950, NULL, 'TEST', 'discharge', 3, 1000, 1)")
  expect_error(frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nrg",
    threshold = 3, distance_max = 1000, verbose = FALSE),
    "hold NULL for it")
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nrg")$n, n0 + 1L)
})

test_that("a near_river walk replaces only the pairs it walks", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_nrp")
  # Two pairs in one call, then one of them on its own. The other's rows are
  # for the same ground, so a delete keyed on ground alone would remove them
  # and write none back — and a habitat rule reading that pair would then
  # match nothing (round 1 of /code-check).
  frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nrp",
    threshold = c(3, 3), distance_max = c(1000, 5000), verbose = FALSE)
  n_pair <- function(d) DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM pg_temp.p293_nrp WHERE distance_max = %s",
    d))$n
  n1 <- n_pair(1000)
  n5 <- n_pair(5000)
  expect_gt(n1, 0)
  expect_gt(n5, 0)
  frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nrp",
    threshold = 3, distance_max = 1000, verbose = FALSE)
  expect_identical(n_pair(1000), n1)
  expect_identical(n_pair(5000), n5)
})

test_that("a network with no watershed group is refused, with or without the parent", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  for (t in c("pg_temp.p293_grp", "pg_temp.p293_grp_near")) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
  }
  DBI::dbExecute(conn, "UPDATE pg_temp.nr_streams
                        SET watershed_group_code = NULL WHERE id_segment = 15")
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)

  # Every match against these tables equates the group as well as the parent,
  # so a row with no group is written and then can never be read or replaced.
  # Refused once, here, rather than handled three different ways in three
  # places (round 2 of /code-check).
  expect_error(frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_grp", species = "CO", params = params,
    gate = FALSE, verbose = FALSE), "no watershed_group_code")
  expect_error(frs_near_river(conn, "pg_temp.nr_streams",
    "pg_temp.p293_grp_near", threshold = 3, distance_max = 1000,
    verbose = FALSE), "no watershed_group_code")

  # And a whole-group delete says so in its own terms rather than letting the
  # NULL-key guard abort later about a column that is not the one at fault.
  expect_error(.frs_wsg_code_check(conn, "pg_temp.nr_streams", "TEST"),
               "rows with no watershed_group_code")
  # Refused before anything was created: the check runs ahead of the target's
  # own pre-flight, so a refused call does not leave an empty table behind.
  expect_true(is.na(DBI::dbGetQuery(conn,
    "SELECT to_regclass('pg_temp.p293_grp')::text AS r")$r))

  # The same network without the parent column was classified before
  # fresh#308, keyed on id_segment, and its rows were never read. Refused now.
  DBI::dbExecute(conn, "ALTER TABLE pg_temp.nr_streams
                        DROP COLUMN linear_feature_id")
  expect_error(frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_grp", species = "CO", params = params,
    gate = FALSE, verbose = FALSE), "no watershed_group_code")
  expect_error(frs_near_river(conn, "pg_temp.nr_streams",
    "pg_temp.p293_grp_near", threshold = 3, distance_max = 1000,
    verbose = FALSE), "no watershed_group_code")

  # The readers refuse it too: each matches habitat rows on the group, so it
  # would read nothing. Refused before they look at the habitat table, which
  # need not exist.
  expect_error(frs_cluster(conn, "pg_temp.nr_streams", "pg_temp.p308_none",
    species = "CO", verbose = FALSE), "no watershed_group_code")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p308_hab")
  DBI::dbExecute(conn, "CREATE TABLE pg_temp.p308_hab (
    id_segment integer, watershed_group_code varchar(4), species_code text,
    spawning boolean, rearing boolean)")
  expect_error(frs_order_child(conn, "pg_temp.nr_streams", "pg_temp.p308_hab",
    species = "CO", verbose = FALSE), "no watershed_group_code")
  # A bridge with a segment that has no group would match no habitat row.
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p308_src")
  DBI::dbExecute(conn, "CREATE TABLE pg_temp.p308_src (
    blue_line_key integer, downstream_route_measure double precision,
    upstream_route_measure double precision, species_code text,
    spawning boolean)")
  DBI::dbExecute(conn, "ALTER TABLE pg_temp.nr_streams
    ADD COLUMN upstream_route_measure double precision")
  expect_error(frs_habitat_overlay(conn, from = "pg_temp.p308_src",
    to = "pg_temp.p308_hab", bridge = "pg_temp.nr_streams", species = "CO",
    habitat_types = "spawning", verbose = FALSE), "no watershed_group_code")
})

test_that("a failure during a near_river walk leaves its pairs as they were", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_nrt")
  frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nrt",
    threshold = c(3, 3), distance_max = c(1000, 5000), verbose = FALSE)
  n0 <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nrt")$n
  expect_gt(n0, 0)

  # The delete and the per-pair inserts are one transaction, as classify's
  # are: a failure in walk i must not leave pairs i..n deleted and not
  # written back (round 2 of /code-check).
  deletes <- 0L
  inserts <- 0L
  local_mocked_bindings(.frs_db_execute = function(conn, sql) {
    if (grepl("DELETE FROM pg_temp.p293_nrt", sql, fixed = TRUE)) {
      deletes <<- deletes + 1L
    }
    if (grepl("INSERT INTO pg_temp.p293_nrt", sql, fixed = TRUE)) {
      inserts <<- inserts + 1L
      if (inserts == 2L) stop("boom")
    }
    DBI::dbExecute(conn, sql)
  })
  expect_error(frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nrt",
    threshold = c(3, 3), distance_max = c(1000, 5000), verbose = FALSE),
    "boom")
  expect_identical(deletes, 1L)
  expect_identical(inserts, 2L)
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_nrt")$n, n0)
})

test_that("a near_river failure in a caller's transaction raises its own error", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit({
    try(DBI::dbRollback(conn), silent = TRUE)
    DBI::dbDisconnect(conn)
  })
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.p293_nrx")
  frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nrx",
    threshold = 3, distance_max = 1000, verbose = FALSE)

  # Where the CALLER owns the transaction, `began` is FALSE and no rollback
  # of ours is registered, so the walk table's DROP is the only handler
  # there is. It runs on the way out of the failure with the transaction
  # already aborted, where every statement raises 25P02 -- and that would
  # become the error the caller sees in place of the one that actually
  # failed. The `try()` on the DROP is what keeps it theirs (round 4 of
  # /code-check). `after = FALSE` cannot cover this branch: there is no
  # rollback to order the DROP against.
  DBI::dbBegin(conn)
  local_mocked_bindings(.frs_db_execute = function(conn, sql) {
    if (grepl("INSERT INTO pg_temp.p293_nrx", sql, fixed = TRUE)) {
      # Abort the caller's transaction in Postgres, not just in R: the
      # 25P02 the DROP would raise only exists once the backend has one.
      try(DBI::dbExecute(conn, "SELECT 1 / 0"), silent = TRUE)
      stop("boom")
    }
    DBI::dbExecute(conn, sql)
  })
  expect_error(frs_near_river(conn, "pg_temp.nr_streams", "pg_temp.p293_nrx",
    threshold = 3, distance_max = 1000, verbose = FALSE), "boom")
  DBI::dbRollback(conn)
})

# --- The read side: connectivity reads only this job's parents --------------
#
# Three of the four sites the first mutation sweep could not credit are the
# .frs_key_match() calls inside .frs_connected_waterbody(), and the wider test
# filter did not rescue them: 130 tests, 0 red. They were a real hole. Every
# test that existed pinned the WATERSHED GROUP arm of those joins (fresh#242,
# test-frs_connectivity_wsg.R), which a same-group row cannot exercise. The
# parent-segment arm is this issue's, and only a decoy inside the group on
# another parent can reach it.

test_that("a same-group row for another parent lends connectivity no rearing", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Segment 1 spawns on the mainstem below a waterbody at segment 2. Nothing
  # in this job's own rows is rearing, so neither phase of
  # .frs_connected_waterbody() finds an origin and 1's spawning is cleared.
  .bkt_fixture(conn, rbind(
    .bkt_seg(1, 0, spawn = TRUE),
    .bkt_seg(2, 1000, wbk = 11)))
  # The decoy: this group's code, segment 2's id_segment, another parent
  # segment (.bkt_habitat_add() negates linear_feature_id), rearing TRUE.
  # Before fresh#293 the delete was whole-group, so a row like this could not
  # survive a run; now a second job over other ground in the same group leaves
  # them, and the parent segment is the only thing separating the two.
  .bkt_habitat_add(conn, .bkt_seg(2, 1000, rear = TRUE), wsg = "TEST")

  # The collision is live before anything is asserted about it: a mutant that
  # drops the parent from the join has to have something to go wrong with.
  expect_identical(DBI::dbGetQuery(conn, "
    SELECT count(*)::int AS n FROM pg_temp.bkt_habitat h
    INNER JOIN pg_temp.bkt_streams s
       ON h.id_segment = s.id_segment
      AND h.watershed_group_code = s.watershed_group_code
    WHERE h.linear_feature_id <> s.linear_feature_id
      AND h.rearing IS TRUE")$n, 1L)

  .frs_connected_waterbody(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    species = "BT", waterbody_poly = "whse_basemapping.fwa_lakes_poly",
    waterbody_ha_min = 1, bridge_gradient = 0.05, distance_max = 3000,
    spawn_connected = NULL, lake_adjacent = FALSE, verbose = FALSE)

  # Cleared. Read through either arm the decoy would rescue it: as a trace
  # origin it sits on segment 2's waterbody and the walk reaches 1 below it,
  # and as a rearing segment it puts 1 upstream of rearing -- every wscode
  # "100" segment is upstream of every other under the 4-arg predicate.
  expect_false(.bkt_flags(conn, "spawning")[["1"]])
})

test_that("the subtractive clear cannot reach another parent's row", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Rearing at a waterbody on segment 1; segment 3 spawns on a separate river
  # that neither phase reaches, so this job's own row at 3 is cleared.
  .bkt_fixture(conn, rbind(
    .bkt_seg(1, 0, wbk = 11, rear = TRUE),
    .bkt_seg(3, 0, spawn = TRUE, blk = 2L, wscode = "200", y = 5000)))
  # Another job's spawning row for this group at that same id_segment, on
  # another parent. The clear addresses habitat rows through `table`, so the
  # parent key is the whole of what keeps this one out of reach: its
  # id_segment is not in the qualifying set, so nothing else protects it.
  .bkt_habitat_add(conn, .bkt_seg(3, 0, spawn = TRUE), wsg = "TEST")

  spawning_at <- function(lfid) DBI::dbGetQuery(conn, sprintf(
    "SELECT spawning FROM pg_temp.bkt_habitat
     WHERE species_code = 'BT' AND watershed_group_code = 'TEST'
       AND id_segment = 3 AND linear_feature_id = %d", lfid))$spawning
  expect_true(spawning_at(3L))     # both start spawning, or neither direction
  expect_true(spawning_at(-3L))    # of the assertion below means anything

  .frs_connected_waterbody(conn, "pg_temp.bkt_streams", "pg_temp.bkt_habitat",
    species = "BT", waterbody_poly = "whse_basemapping.fwa_lakes_poly",
    waterbody_ha_min = 1, bridge_gradient = 0.05, distance_max = 3000,
    spawn_connected = NULL, lake_adjacent = FALSE, verbose = FALSE)

  expect_false(spawning_at(3L))    # this job's own row: cleared
  expect_true(spawning_at(-3L))    # the other parent's row: untouched
})

# --- Nothing is left reading these tables on the short key ------------------

test_that("no habitat-to-streams join is left spelled inline", {
  # Round 1 of /code-check found three such joins still inline in
  # .frs_connected_waterbody(), written alias-reversed —
  # `s2.id_segment = hr.id_segment` — and the first version of this test could
  # not see them: it grepped for the literal `"id_segment = s.id_segment"`,
  # which matches none of them, so it asserted 0 == 0 for the one file that
  # still had the defect. A proxy, not the property (code-check.md).
  #
  # The property: every `<a>.id_segment = <b>.id_segment` written as text in
  # the package is one of a named, justified set. .frs_key_match() builds its
  # own with sprintf from parts, so it contributes no literal and a site
  # converted to it drops out of the count. Anything new fails here.
  #
  # Over the namespace, not over R/: devtools::test() runs from tests/testthat
  # and R CMD check has no R/ at all, where a list.files() sweep would count
  # zero over zero and pass.
  allowed <- c(
    # s.id_segment = a.id_segment — the per-threshold accessibility temp
    # table, built from `table` inside this call. Nothing else writes it.
    frs_habitat_classify = 1L,
    # Two joins of `table` to a downstream-trace output, streams to streams;
    # the habitat side of the same statements is `hab_join`, built by
    # .frs_key_match().
    .frs_bucket_connected = 2L,
    # c.id_segment = su.id_segment, two CTEs of one statement; and
    # q.id_segment = h.id_segment, where `h` is already pinned to a row of
    # `table` by the key, so id_segment alone is exact there.
    .frs_connected_waterbody = 2L,
    # n.id_segment = s.id_segment, which carries the parent segment too when
    # `lfid` is TRUE — the one site where the short key is an option rather
    # than a mistake.
    .frs_near_river_sql = 1L)

  ns <- asNamespace("fresh")
  # Wider than one spelling (round 6 of /code-check): any spacing around the
  # `=`, a line break inside the SQL string (deparse() writes it as the two
  # characters backslash-n), a sprintf() placeholder for an alias, and a
  # `USING (...)` naming id_segment -- the form data-raw/ already uses.
  ws <- "(\\s|\\\\n)*"
  pat <- paste0("[A-Za-z0-9_%]+[.]id_segment", ws, "=", ws,
                "[A-Za-z0-9_%]+[.]id_segment",
                "|USING", ws, "[(][^)]*id_segment")
  found <- integer(0)
  for (nm in ls(ns, all.names = TRUE)) {
    f <- get(nm, envir = ns)
    if (!is.function(f)) next
    txt <- paste(deparse(f), collapse = "\n")
    m <- gregexpr(pat, txt, perl = TRUE)[[1]]
    n <- if (length(m) == 1 && m[[1]] == -1) 0L else length(m)
    if (n > 0) found[[nm]] <- n
  }

  # The regex has to be able to see the shape it is policing, or this test is
  # the same proxy as the one it replaces: both alias orders, matched against
  # the text the fixed sites used to carry.
  # Probed through deparse(), the text the loop above actually searches.
  spelled <- function(f) paste(deparse(f), collapse = "\n")
  probes <- list(
    function() "INNER JOIN %s hr ON s2.id_segment = hr.id_segment",
    function() "INNER JOIN %s h ON h.id_segment = s.id_segment",
    function() "ON h.id_segment=s.id_segment",
    function() "ON h.id_segment =
       s.id_segment",
    function() "ON %s.id_segment = %s.id_segment",
    function() "JOIN t USING (id_segment, watershed_group_code)")
  for (f in probes) expect_match(spelled(f), pat, perl = TRUE)
  # And it does not fire on a single-sided equality, or the count would move.
  expect_no_match(spelled(function() "WHERE h.id_segment = 5"), pat,
                  perl = TRUE)

  expect_identical(found[order(names(found))],
                   allowed[order(names(allowed))])
})

test_that("no habitat key is built with the parent segment switched off", {
  # The count above proves no join is spelled inline. It says nothing about a
  # call that builds one through .frs_key_match() with the parent arm turned
  # OFF -- `.frs_key_match("hr", "s2", FALSE)` passes it, and that is exactly
  # the mutation the sweep applies at each of these sites. So the arm needs an
  # enumeration of its own, over the parsed bodies rather than their text:
  # there are 19 call sites and one guard, and 19 sweep rows of one guard is
  # not an enumeration of anything.
  #
  # This is a check on the SHAPE of the call. What it cannot show is that the
  # arm changes an answer -- a proxy is not the property (code-check.md). The
  # three tests under "The read side" above are that half, one per
  # .frs_connected_waterbody() site, and the subtractive clear's own key is
  # pinned by "the subtractive clear cannot reach another parent's row".
  # Its own accumulator per call, so the self-check below cannot add to the
  # namespace's count. Bodies only: no site sits in a formal default, and
  # reaching into one would force the empty symbol of every argument that has
  # no default. The count pinned below is what would catch a site moving there.
  key_calls <- function(e) {
    out <- list()
    rec <- function(x) {
      if (!is.call(x)) return(invisible(NULL))
      if (is.name(x[[1]]) && identical(as.character(x[[1]]), ".frs_key_match")) {
        out[[length(out) + 1L]] <<- x
      }
      for (i in seq_along(x)) rec(x[[i]])
      invisible(NULL)
    }
    rec(e)
    out
  }

  # The walker has to be able to see a call before its verdict means anything,
  # and to reach one nested in a sprintf() argument, which is where most of
  # them sit.
  expect_identical(
    length(key_calls(quote(sprintf("%s", .frs_key_match("h", "s", FALSE))))),
    1L)

  ns <- asNamespace("fresh")
  calls <- list()
  for (nm in ls(ns, all.names = TRUE)) {
    f <- get(nm, envir = ns)
    if (!is.function(f) || is.null(body(f))) next
    calls <- c(calls, key_calls(body(f)))
  }

  # Every site takes the arm from the pair test: the symbol `lfid`, which each
  # function sets from .frs_lfid_pair(), or that call written in place. Never
  # a literal, which is what a mutant leaves behind.
  from_pair_test <- vapply(calls, function(e) {
    a <- as.list(e)[-1]
    nm <- names(a)
    if (is.null(nm)) nm <- rep("", length(a))
    v <- if ("lfid" %in% nm) a[[which(nm == "lfid")]] else a[[3]]
    identical(v, quote(lfid)) ||
      (is.call(v) && is.name(v[[1]]) &&
         identical(as.character(v[[1]]), ".frs_lfid_pair"))
  }, logical(1))

  # The count is pinned too, so a site cannot be deleted into compliance. It
  # moves when a join is added or removed; read the diff before changing it.
  expect_identical(length(calls), 19L)
  expect_true(all(from_pair_test))
})

test_that("every exported reader of group-keyed habitat rows refuses a NULL group", {
  # fresh#308: the joins built by .frs_key_match() and the near_river EXISTS
  # built by .frs_near_river_sql() equate watershed_group_code, so a segment
  # with none is read by nothing. Each exported function that reaches either
  # must reach .frs_group_required() too. Walked over the namespace's call
  # graph, not over R/ (no R/ exists under R CMD check).
  ns <- asNamespace("fresh")
  fns <- Filter(function(n) is.function(get(n, envir = ns)),
                ls(ns, all.names = TRUE))
  callees <- lapply(stats::setNames(fns, fns), function(n) {
    intersect(all.names(body(get(n, envir = ns))), fns)
  })
  reach <- function(n) {
    seen <- character(0)
    todo <- n
    while (length(todo) > 0) {
      x <- todo[[1]]
      todo <- todo[-1]
      if (x %in% seen) next
      seen <- c(seen, x)
      todo <- c(todo, callees[[x]])
    }
    seen
  }
  readers <- c(".frs_key_match", ".frs_near_river_sql")
  exempt <- c(
    # Builds predicate text for a caller and takes no table to check; its
    # callers (frs_habitat_classify) check.
    "frs_habitat_predicates")
  exported <- getNamespaceExports(ns)
  hits <- Filter(function(n) any(readers %in% reach(n)), exported)
  # The walk has to see the readers at all, or this passes vacuously.
  expect_true(all(c("frs_cluster", "frs_order_child", "frs_habitat_overlay",
                    "frs_habitat_classify", "frs_habitat") %in% hits))
  # frs_near_river() writes the rows .frs_near_river_sql() reads rather than
  # reading any itself, so the walk does not list it; it guards all the same.
  expect_true(".frs_group_required" %in% reach("frs_near_river"))
  unguarded <- Filter(function(n) !".frs_group_required" %in% reach(n),
                      setdiff(hits, exempt))
  expect_identical(sort(unguarded), character(0))
  # A stale exemption is a gap waiting to happen.
  expect_true(all(exempt %in% hits))
})
