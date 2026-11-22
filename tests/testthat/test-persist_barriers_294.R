# fresh#294: persisted gradient barriers are keyed by the parent segment each
# falls on, and a job writes only its own segments' barriers.
#
# frs_break_find() reads every segment of a blue line, so a job on one
# watershed group finds barriers along the whole line, the neighbouring group's
# part included, at its own species' gradient classes. The old delete by
# blue_line_key then let the last job to run own both groups' barriers
# (data-raw/barrier_span_294.R). These tests drive .frs_persist_barriers() on
# pg_temp tables: two groups share blue line 1, and each job's barrier table
# covers the whole line, as a real job's does.

# One job's working tables: a segmented streams table holding only its own
# group's segments, and a barriers table covering the whole line.
.b294_job <- function(conn, tag, wsg, lfids, barriers) {
  st <- paste0("pg_temp.b294_streams_", tag)
  br <- paste0("pg_temp.b294_barriers_", tag)
  for (t in c(st, br)) DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t))
  # Two child segments per parent, as a split leaves them.
  DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE %s AS
     SELECT (row_number() OVER ())::int AS id_segment,
            l::bigint AS linear_feature_id, %s::text AS watershed_group_code
     FROM unnest(ARRAY[%s]) AS l, generate_series(1, 2)",
    sub("^pg_temp\\.", "", st), DBI::dbQuoteString(conn, wsg),
    paste(lfids, collapse = ", ")))
  DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE %s (
       blue_line_key integer, downstream_route_measure double precision,
       gradient_class integer, label text, source text,
       wscode_ltree ltree, localcode_ltree ltree,
       linear_feature_id bigint, watershed_group_code text)",
    sub("^pg_temp\\.", "", br)))
  for (i in seq_len(nrow(barriers))) {
    b <- barriers[i, ]
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO %s VALUES (1, %s, %d, 'gradient_%04d', 'attribute',
         '100'::ltree, '100'::ltree, %s, %s)",
      br, .frs_sql_exact(b$m), b$cls, b$cls,
      if (is.na(b$lfid)) "NULL" else b$lfid,
      if (is.na(b$wsg)) "NULL" else DBI::dbQuoteString(conn, b$wsg)))
  }
  list(streams = st, barriers = br)
}

# Group AAAA owns parents 101 and 102, group BBBB owns 201 and 202, all on
# blue line 1. Each job found barriers on both groups' parts, at its own
# classes; job B's run also found one barrier no segment contains.
.b294_fixture <- function(conn) {
  a <- .b294_job(conn, "a", "AAAA", c(101, 102), data.frame(
    m = c(100, 1500, 2500), cls = c(249L, 449L, 249L),
    lfid = c(101, 102, 201), wsg = c("AAAA", "AAAA", "BBBB")))
  b <- .b294_job(conn, "b", "BBBB", c(201, 202), data.frame(
    m = c(100, 1500, 2500, 3500, 9999), cls = c(849L, 849L, 449L, 449L, 849L),
    lfid = c(101, 102, 201, 202, NA), wsg = c("AAAA", "AAAA", "BBBB", "BBBB", NA)))
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.b294_target")
  list(a = a, b = b, to = "pg_temp.b294_target")
}

.b294_rows <- function(conn, to) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT linear_feature_id, watershed_group_code, downstream_route_measure,
            gradient_class
     FROM %s ORDER BY downstream_route_measure", to))
}

test_that("a second group's job leaves the first group's barriers alone", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  f <- .b294_fixture(conn)

  .frs_persist_barriers(conn, f$to, f$a$barriers, f$a$streams)
  .frs_persist_barriers(conn, f$to, f$b$barriers, f$b$streams)
  r <- .b294_rows(conn, f$to)

  # AAAA's barriers are job A's, at job A's classes; BBBB's are job B's.
  expect_equal(r$downstream_route_measure, c(100, 1500, 2500, 3500))
  expect_equal(r$gradient_class, c(249L, 449L, 449L, 449L))
  expect_equal(r$watershed_group_code, c("AAAA", "AAAA", "BBBB", "BBBB"))
  expect_equal(r$linear_feature_id, c(101, 102, 201, 202))

  # Order does not matter: B then A ends in the same state.
  DBI::dbExecute(conn, sprintf("DROP TABLE %s", f$to))
  .frs_persist_barriers(conn, f$to, f$b$barriers, f$b$streams)
  .frs_persist_barriers(conn, f$to, f$a$barriers, f$a$streams)
  expect_equal(.b294_rows(conn, f$to), r)
})

test_that("a re-run replaces its own barriers instead of adding to them", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  f <- .b294_fixture(conn)

  .frs_persist_barriers(conn, f$to, f$a$barriers, f$a$streams)
  .frs_persist_barriers(conn, f$to, f$b$barriers, f$b$streams)
  r1 <- .b294_rows(conn, f$to)
  .frs_persist_barriers(conn, f$to, f$b$barriers, f$b$streams)
  .frs_persist_barriers(conn, f$to, f$a$barriers, f$a$streams)
  expect_equal(.b294_rows(conn, f$to), r1)

  # A job whose barriers moved removes the old ones on its own segments.
  DBI::dbExecute(conn, sprintf(
    "DELETE FROM %s WHERE downstream_route_measure = 1500", f$a$barriers))
  .frs_persist_barriers(conn, f$to, f$a$barriers, f$a$streams)
  expect_equal(.b294_rows(conn, f$to)$downstream_route_measure,
               c(100, 2500, 3500))
})

test_that("a barrier on no segment is not written", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  f <- .b294_fixture(conn)

  # It could never be addressed by a later delete, and the next run's NULL-key
  # guard would refuse the table because of it.
  .frs_persist_barriers(conn, f$to, f$b$barriers, f$b$streams)
  r <- .b294_rows(conn, f$to)
  expect_false(any(is.na(r$linear_feature_id)))
  expect_false(9999 %in% r$downstream_route_measure)
  expect_no_error(.frs_persist_barriers(conn, f$to, f$b$barriers, f$b$streams))
})

test_that("a barriers table written before the key existed is refused", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  f <- .b294_fixture(conn)

  # The shape frs_habitat() persisted before fresh#294.
  DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE %s (
       blue_line_key integer, downstream_route_measure double precision,
       gradient_class integer, label text, source text,
       wscode_ltree ltree, localcode_ltree ltree)",
    sub("^pg_temp\\.", "", f$to)))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s VALUES (1, 100, 249, 'gradient_0249', 'attribute',
       '100'::ltree, '100'::ltree)", f$to))

  expect_error(.frs_persist_barriers(conn, f$to, f$a$barriers, f$a$streams),
               "linear_feature_id")
  # Refused before anything was deleted or written.
  r <- DBI::dbGetQuery(conn, sprintf(
    "SELECT downstream_route_measure FROM %s", f$to))
  expect_equal(r$downstream_route_measure, 100)
})

test_that("the delete is undone when the insert fails", {
  skip_if_no_conn()
  skip_if_not_installed("mockery")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  f <- .b294_fixture(conn)
  .frs_persist_barriers(conn, f$to, f$a$barriers, f$a$streams)
  r1 <- .b294_rows(conn, f$to)

  # Autocommitted separately, a failure between the two statements would
  # leave the job's segments with no barriers at all.
  mockery::stub(.frs_persist_barriers, ".frs_db_execute",
    function(conn, sql) {
      if (grepl("^\\s*INSERT", sql)) stop("insert failed")
      DBI::dbExecute(conn, sql)
    })
  expect_error(.frs_persist_barriers(conn, f$to, f$a$barriers, f$a$streams),
               "insert failed")
  expect_equal(.b294_rows(conn, f$to), r1)
})

test_that("a target that is its own source is refused", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  f <- .b294_fixture(conn)
  expect_error(.frs_persist_barriers(conn, f$a$barriers, f$a$barriers,
                                     f$a$streams), "same table")
})
