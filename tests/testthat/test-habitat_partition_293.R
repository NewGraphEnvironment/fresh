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

  tgt <- "working.p293_streams"
  hab <- "working.p293_habitat"
  solo <- "working.p293_solo_habitat"
  solo_s <- "working.p293_solo_streams"
  tbls <- c(tgt, hab, solo, solo_s, paste0(hab, "_near_river"),
            paste0(solo, "_near_river"),
            paste0("working.streams_", c("p293a", "p293b", "p293c")))
  on.exit({
    for (t in tbls) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", t))
    }
    DBI::dbDisconnect(conn)
  })
  for (t in tbls) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", t))
  }
  n_of <- function(t) DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s", t))$n
  run <- function(label, aoi, streams, habitat) {
    frs_habitat(conn, aoi = aoi, species = "CO", label = label,
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

  run <- function() frs_habitat_classify(conn, table = "pg_temp.p293_nofwa",
    to = "pg_temp.p293_nofwa_habitat", species = "CO", params = params,
    gate = FALSE, verbose = FALSE)
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
  run <- function(sp) frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_sp", species = sp, params = params, gate = FALSE,
    verbose = FALSE)
  n_of <- function(sp) DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM pg_temp.p293_sp WHERE species_code = '%s'",
    sp))$n

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
  run <- function() frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_tx", species = "CO", params = params, gate = FALSE,
    verbose = FALSE)
  run()
  n0 <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_tx")$n
  expect_gt(n0, 0)

  # The delete and the inserts are one transaction, so an insert that fails
  # cannot leave the partition deleted and not written back. Make the second
  # species' insert fail after the first has run: a two-species call deletes
  # once and then inserts per species.
  calls <- 0L
  local_mocked_bindings(.frs_db_execute = function(conn, sql) {
    if (grepl("INSERT INTO pg_temp.p293_tx", sql, fixed = TRUE)) {
      calls <<- calls + 1L
      if (calls == 2L) stop("boom")
    }
    DBI::dbExecute(conn, sql)
  })
  expect_error(frs_habitat_classify(conn, table = "pg_temp.nr_streams",
    to = "pg_temp.p293_tx", species = c("CO", "BT"), params = params,
    gate = FALSE, verbose = FALSE), "boom")
  # The condition the assertion rests on: the delete and one insert did run.
  expect_identical(calls, 2L)
  expect_identical(DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM pg_temp.p293_tx")$n, n0)
})

# --- Nothing is left reading these tables on the short key ------------------

test_that("every habitat-to-streams join is built by the one key helper", {
  # Enumeration over the parsed functions, not over R/: devtools::test() runs
  # from tests/testthat and R CMD check has no R/ at all, so a list.files()
  # sweep counts zero over zero and passes. Terminating on an enumeration is
  # what closes a review loop (planning.md), so this is the instrument.
  fns <- list(
    .frs_run_connectivity = .frs_run_connectivity,
    .frs_connected_waterbody = .frs_connected_waterbody,
    frs_cluster = frs_cluster,
    frs_order_child = frs_order_child,
    frs_habitat_overlay = frs_habitat_overlay)
  for (nm in names(fns)) {
    txt <- paste(deparse(body(fns[[nm]])), collapse = "\n")
    hits <- gregexpr("id_segment = s.id_segment", txt, fixed = TRUE)[[1]]
    n_hits <- if (length(hits) == 1 && hits[[1]] == -1) 0L else length(hits)
    expect_identical(n_hits, 0L,
      info = paste(nm, "still spells a habitat-to-streams join inline;",
                   "build it with .frs_key_match()"))
  }
})
