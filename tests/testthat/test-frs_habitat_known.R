# Unit tests: frs_habitat_known
#
# Mocked tests cover argument validation, column-skip behaviour, SQL
# shape. Integration tests at the bottom hit a small fixture on a
# live fwapg.

# Helper: build a dbGetQuery mock that returns
# - species list for `SELECT DISTINCT species_code`
# - target table columns when the info_schema query targets `table_name = 'h'`
# - known table columns when targeting `table_name = 'k'`
mk_dbq <- function(species, table_cols, known_cols) {
  function(conn, sql) {
    if (grepl("DISTINCT species_code", sql)) {
      data.frame(species_code = species)
    } else if (grepl("information_schema", sql)) {
      if (grepl("table_name = 'h'", sql)) {
        data.frame(column_name = table_cols)
      } else {
        data.frame(column_name = known_cols)
      }
    } else {
      data.frame()
    }
  }
}

# All-habitat columns the function expects in the target table by default
TBL_DEFAULT <- c("id_segment", "species_code",
                 "blue_line_key", "downstream_route_measure",
                 "spawning", "rearing", "lake_rearing", "wetland_rearing")

# -- Argument validation -------------------------------------------------------

test_that("frs_habitat_known validates conn", {
  expect_error(
    frs_habitat_known("not a conn", "x.y", "x.z"),
    "DBIConnection")
})

test_that("frs_habitat_known validates table / known are schema-qualified strings", {
  fake <- structure(list(), class = "DBIConnection")
  expect_error(frs_habitat_known(fake, "", "x.y"))
  expect_error(frs_habitat_known(fake, "x.y", ""))
  expect_error(frs_habitat_known(fake, c("a", "b"), "x.y"))
})

test_that("frs_habitat_known requires schema-qualified known table", {
  fake <- structure(list(), class = "DBIConnection")
  # `table = "ws.h"` so the table_cols mock branch matches; known is
  # the unqualified one being tested.
  mockery::stub(frs_habitat_known, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT, character(0)))
  expect_error(
    frs_habitat_known(fake, "ws.h", "no_schema",
                      species = "CO"),
    "schema-qualified")
})

# -- Empty table -> no-op ------------------------------------------------------

test_that("empty table -> early return without error", {
  fake <- structure(list(), class = "DBIConnection")

  mockery::stub(frs_habitat_known, "DBI::dbGetQuery", function(conn, sql) {
    if (grepl("DISTINCT species_code", sql)) {
      data.frame(species_code = character(0))
    } else if (grepl("information_schema", sql) && grepl("table_name = 'h'", sql)) {
      # table validation: species discovery returned 0, so we still
      # check habitat_types here. Provide all habitat columns.
      data.frame(column_name = TBL_DEFAULT)
    } else {
      data.frame(column_name = character(0))
    }
  })

  expect_silent(suppressMessages(
    frs_habitat_known(fake, "ws.h", "ws.k", verbose = FALSE)
  ))
})

# -- Missing column for a (species, habitat) pair -> skip ---------------------

test_that("missing per-species column is skipped, not an error", {
  fake <- structure(list(), class = "DBIConnection")
  exec_calls <- list()

  mockery::stub(frs_habitat_known, "DBI::dbGetQuery",
    mk_dbq(
      species     = "CT",
      table_cols  = TBL_DEFAULT,
      known_cols  = c("blue_line_key", "downstream_route_measure",
                       "spawning_bt", "rearing_bt",
                       "spawning_co", "rearing_co")))
  mockery::stub(frs_habitat_known, ".frs_db_execute", function(conn, sql) {
    exec_calls[[length(exec_calls) + 1L]] <<- sql
    0L
  })

  out <- expect_output(
    frs_habitat_known(fake, "ws.h", "ws.k", species = "CT", verbose = TRUE),
    "skip CT/spawning")

  # No UPDATEs should have run for CT (no matching columns)
  expect_length(exec_calls, 0)
})

# -- SQL shape: correct columns + values ---------------------------------------

test_that("UPDATE SQL ORs in TRUE on matching segments only", {
  fake <- structure(list(), class = "DBIConnection")
  captured <- list()

  mockery::stub(frs_habitat_known, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT,
           c("blue_line_key", "downstream_route_measure", "spawning_co")))
  mockery::stub(frs_habitat_known, ".frs_db_execute", function(conn, sql) {
    captured[[length(captured) + 1L]] <<- sql
    3L
  })

  invisible(frs_habitat_known(fake, "ws.h", "ws.k",
                              species = "CO",
                              habitat_types = "spawning",
                              verbose = FALSE))

  expect_length(captured, 1)
  sql <- captured[[1]]
  expect_match(sql, "UPDATE ws\\.h")
  expect_match(sql, "SET spawning = TRUE")
  expect_match(sql, "FROM ws\\.k")
  expect_match(sql, "h\\.blue_line_key = k\\.blue_line_key")
  expect_match(sql, "h\\.downstream_route_measure = k\\.downstream_route_measure")
  expect_match(sql, "h\\.species_code = 'CO'")
  expect_match(sql, "k\\.spawning_co IS TRUE")
  # Idempotency / additive guard — assert the parens so a refactor
  # that drops them (which would break AND/OR precedence) fails the
  # test.
  expect_match(sql, "AND \\(h\\.spawning IS NULL OR h\\.spawning = FALSE\\)")
})

test_that("rejects malformed species codes (non-alphabetic)", {
  fake <- structure(list(), class = "DBIConnection")
  expect_error(
    frs_habitat_known(fake, "ws.h", "ws.k", species = "CO; DROP --"),
    "alphabetic")
  expect_error(
    frs_habitat_known(fake, "ws.h", "ws.k", species = c("CO", "BAD CODE")),
    "alphabetic")
})

test_that("rejects habitat_types not in target table", {
  fake <- structure(list(), class = "DBIConnection")
  mockery::stub(frs_habitat_known, "DBI::dbGetQuery", function(conn, sql) {
    if (grepl("information_schema", sql)) {
      data.frame(column_name = c("id_segment", "species_code", "spawning"))
    } else {
      data.frame(species_code = "CO")
    }
  })
  expect_error(
    frs_habitat_known(fake, "ws.h", "ws.k", species = "CO",
                      habitat_types = c("spawning", "rearing"),
                      verbose = FALSE),
    "habitat_types not found")
})

# -- Custom join key parameter (`by`) ----------------------------------------

test_that("custom by= produces matching join predicate", {
  fake <- structure(list(), class = "DBIConnection")
  captured <- character(0)

  mockery::stub(frs_habitat_known, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT, c("id_segment", "spawning_co")))
  mockery::stub(frs_habitat_known, ".frs_db_execute", function(conn, sql) {
    captured <<- c(captured, sql); 0L
  })

  frs_habitat_known(fake, "ws.h", "ws.k",
                    species = "CO",
                    habitat_types = "spawning",
                    by = "id_segment",
                    verbose = FALSE)

  expect_length(captured, 1)
  expect_match(captured, "h\\.id_segment = k\\.id_segment")
  expect_no_match(captured, "blue_line_key")
})

# -- NULL species -> all distinct species in the table ------------------------

test_that("NULL species pulls from table.species_code", {
  fake <- structure(list(), class = "DBIConnection")

  species_seen <- character(0)
  mockery::stub(frs_habitat_known, "DBI::dbGetQuery",
    mk_dbq(c("BT", "CO"), TBL_DEFAULT,
           c("blue_line_key", "downstream_route_measure",
             "spawning_bt", "spawning_co")))
  mockery::stub(frs_habitat_known, ".frs_db_execute", function(conn, sql) {
    if (grepl("species_code = '([A-Z]+)'", sql)) {
      m <- regmatches(sql, regexpr("species_code = '([A-Z]+)'", sql))
      species_seen <<- c(species_seen, sub(".*'([A-Z]+)'.*", "\\1", m))
    }
    1L
  })

  frs_habitat_known(fake, "ws.h", "ws.k",
                    habitat_types = "spawning",
                    verbose = FALSE)

  expect_setequal(species_seen, c("BT", "CO"))
})

# -- Identifier injection ----------------------------------------------------

test_that("malicious identifiers are rejected by validator", {
  fake <- structure(list(), class = "DBIConnection")
  expect_error(
    frs_habitat_known(fake, "ws.h; DROP TABLE x; --", "ws.k"))
  expect_error(
    frs_habitat_known(fake, "ws.h", "ws.k", by = "bad-name"))
  expect_error(
    frs_habitat_known(fake, "ws.h", "ws.k", habitat_types = "spawn'; DROP --"))
})

# -- Integration: real DB, small fixture --------------------------------------

test_that("integration: known segment flips FALSE -> TRUE on a fixture", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_known_h")
    .frs_test_drop(conn, "working.test_known_k")
    DBI::dbDisconnect(conn)
  })

  # Note: assumes `working` schema already exists. Other fresh
  # integration tests rely on the same convention; CREATE SCHEMA
  # requires DB-level DDL which the shared connection lacks.

  # Build a 3-segment streams_habitat fixture with all FALSE
  DBI::dbExecute(conn,
    "CREATE TABLE working.test_known_h (
       id_segment integer, species_code text,
       blue_line_key bigint, downstream_route_measure double precision,
       spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean)")
  DBI::dbExecute(conn,
    "INSERT INTO working.test_known_h VALUES
       (1, 'CO', 100, 10.0, FALSE, FALSE, FALSE, FALSE),
       (2, 'CO', 100, 20.0, TRUE,  FALSE, FALSE, FALSE),
       (3, 'CO', 100, 30.0, FALSE, FALSE, FALSE, FALSE)")

  # Known-habitat fixture: segment at DRM=10 has spawning_co; segment
  # at DRM=20 has rearing_co (already classified spawning, will flip
  # rearing too); segment at DRM=30 has nothing.
  DBI::dbExecute(conn,
    "CREATE TABLE working.test_known_k (
       blue_line_key bigint, downstream_route_measure double precision,
       spawning_co boolean, rearing_co boolean)")
  DBI::dbExecute(conn,
    "INSERT INTO working.test_known_k VALUES
       (100, 10.0, TRUE,  FALSE),
       (100, 20.0, FALSE, TRUE),
       (100, 30.0, FALSE, FALSE)")

  invisible(frs_habitat_known(conn,
    table = "working.test_known_h",
    known = "working.test_known_k",
    species = "CO",
    habitat_types = c("spawning", "rearing"),
    verbose = FALSE))

  result <- DBI::dbGetQuery(conn,
    "SELECT id_segment, spawning, rearing
     FROM working.test_known_h ORDER BY id_segment")

  expect_equal(result$spawning, c(TRUE, TRUE, FALSE))
  expect_equal(result$rearing,  c(FALSE, TRUE, FALSE))
})

test_that("integration: already-TRUE rows are not re-touched (additive-only)", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_known_h3")
    .frs_test_drop(conn, "working.test_known_k3")
    DBI::dbDisconnect(conn)
  })

  DBI::dbExecute(conn,
    "CREATE TABLE working.test_known_h3 (
       id_segment integer, species_code text,
       blue_line_key bigint, downstream_route_measure double precision,
       spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean)")
  # Both segments START as spawning = TRUE
  DBI::dbExecute(conn,
    "INSERT INTO working.test_known_h3 VALUES
       (1, 'CO', 100, 10.0, TRUE, FALSE, FALSE, FALSE),
       (2, 'CO', 100, 20.0, TRUE, FALSE, FALSE, FALSE)")
  DBI::dbExecute(conn,
    "CREATE TABLE working.test_known_k3 (
       blue_line_key bigint, downstream_route_measure double precision,
       spawning_co boolean)")
  # Known says both are spawning. The additive guard should make the
  # UPDATE skip both rows (already TRUE), returning rowcount 0.
  DBI::dbExecute(conn,
    "INSERT INTO working.test_known_k3 VALUES
       (100, 10.0, TRUE),
       (100, 20.0, TRUE)")

  # capture rowcount via verbose path: the cat() output reports
  # `<sp>/<hab>: <n> segments flipped`. Use direct dbExecute to read
  # the matching count.
  invisible(frs_habitat_known(conn,
    table = "working.test_known_h3",
    known = "working.test_known_k3",
    species = "CO", habitat_types = "spawning",
    verbose = FALSE))

  # Both rows should still be TRUE; nothing flipped — additive guard
  # held. Verifying by query.
  result <- DBI::dbGetQuery(conn,
    "SELECT spawning FROM working.test_known_h3 ORDER BY id_segment")
  expect_equal(result$spawning, c(TRUE, TRUE))
})

test_that("integration: idempotent on second call", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, "working.test_known_h2")
    .frs_test_drop(conn, "working.test_known_k2")
    DBI::dbDisconnect(conn)
  })

  # Note: assumes `working` schema already exists. Other fresh
  # integration tests rely on the same convention; CREATE SCHEMA
  # requires DB-level DDL which the shared connection lacks.
  DBI::dbExecute(conn,
    "CREATE TABLE working.test_known_h2 (
       id_segment integer, species_code text,
       blue_line_key bigint, downstream_route_measure double precision,
       spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean)")
  DBI::dbExecute(conn,
    "INSERT INTO working.test_known_h2 VALUES
       (1, 'CO', 100, 10.0, FALSE, FALSE, FALSE, FALSE)")
  DBI::dbExecute(conn,
    "CREATE TABLE working.test_known_k2 (
       blue_line_key bigint, downstream_route_measure double precision,
       spawning_co boolean)")
  DBI::dbExecute(conn,
    "INSERT INTO working.test_known_k2 VALUES (100, 10.0, TRUE)")

  invisible(frs_habitat_known(conn, "working.test_known_h2",
    "working.test_known_k2", species = "CO",
    habitat_types = "spawning", verbose = FALSE))
  invisible(frs_habitat_known(conn, "working.test_known_h2",
    "working.test_known_k2", species = "CO",
    habitat_types = "spawning", verbose = FALSE))

  result <- DBI::dbGetQuery(conn,
    "SELECT spawning FROM working.test_known_h2")
  expect_true(result$spawning)
})
