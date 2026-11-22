# Unit tests: frs_habitat_overlay
#
# Mocked tests cover argument validation, SQL shape, and edge cases.
# Integration tests at the bottom hit a small fixture on a live DB.
#
# Source-table shape contract (canonical): one row per (segment x
# species). Each row carries `by` columns + `species_col` (default
# "species_code") + one indicator column per habitat type. Indicator
# coercion accepts integer 1, text 'true'/'t'/'1' (case + whitespace
# insensitive), boolean.

# A zero-row frame with these columns: what `SELECT * FROM t LIMIT 0`
# returns, which is how the function reads a table's column names.
cols0 <- function(cols) {
  as.data.frame(stats::setNames(rep(list(logical(0)), length(cols)), cols))
}

# Helper: build a dbGetQuery mock with separate species/target/source
# branches. `to_cols` and `from_cols` describe column inventories
# returned by the `LIMIT 0` column lookups.
mk_dbq <- function(species, to_cols, from_cols, bridge_cols = character(0)) {
  function(conn, sql) {
    if (grepl("DISTINCT species_code", sql)) {
      data.frame(species_code = species)
    } else if (grepl("LIMIT 0", sql)) {
      if (grepl("FROM ws.h LIMIT 0", sql, fixed = TRUE)) {
        cols0(to_cols)
      } else if (grepl("FROM ws.s LIMIT 0", sql, fixed = TRUE)) {
        cols0(bridge_cols)
      } else {
        cols0(from_cols)
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

# Canonical-shape source columns (default `by` + species_col + habitat_types)
SRC_DEFAULT <- c("blue_line_key", "downstream_route_measure",
                 "species_code",
                 "spawning", "rearing", "lake_rearing", "wetland_rearing")

# -- Argument validation -------------------------------------------------------

test_that("validates conn", {
  expect_error(
    frs_habitat_overlay("not a conn", from = "x.z", to = "x.y"),
    "DBIConnection")
})

test_that("validates from / to are schema-qualified strings", {
  fake <- structure(list(), class = "DBIConnection")
  expect_error(frs_habitat_overlay(fake, from = "x.y", to = ""))
  expect_error(frs_habitat_overlay(fake, from = "", to = "x.y"))
  expect_error(frs_habitat_overlay(fake, c("a", "b"), "x.y"))
})

test_that("rejects malicious from / to identifiers", {
  fake <- structure(list(), class = "DBIConnection")
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k; DROP TABLE x; --", to = "ws.h"))
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h; DROP TABLE x; --"))
})

test_that("rejects malicious species_col identifier", {
  fake <- structure(list(), class = "DBIConnection")
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
                        species = "CO",
                        species_col = "species; DROP TABLE x; --"),
    "invalid")
})

test_that("rejects malformed species codes (non-alphabetic)", {
  fake <- structure(list(), class = "DBIConnection")
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h", species = "CO; DROP --"),
    "alphabetic")
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h", species = c("CO", "BAD CODE")),
    "alphabetic")
})

test_that("requires schema-qualified from / to", {
  fake <- structure(list(), class = "DBIConnection")
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT, character(0)))
  expect_error(
    frs_habitat_overlay(fake, from = "no_schema", to = "ws.h",
                        species = "CO"),
    "schema-qualified")
})

test_that("rejects habitat_types not in target table", {
  fake <- structure(list(), class = "DBIConnection")
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery", function(conn, sql) {
    if (grepl("LIMIT 0", sql)) {
      cols0(c("id_segment", "species_code", "spawning"))
    } else {
      data.frame(species_code = "CO")
    }
  })
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h", species = "CO",
                        habitat_types = c("spawning", "rearing"),
                        verbose = FALSE),
    "habitat_types not found")
})

test_that("rejects from table missing required columns", {
  fake <- structure(list(), class = "DBIConnection")
  # Source missing `rearing` column
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT,
           c("blue_line_key", "downstream_route_measure",
             "species_code", "spawning")))
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
                        species = "CO",
                        habitat_types = c("spawning", "rearing"),
                        verbose = FALSE),
    "missing required columns")
})

test_that("rejects from table missing species_col", {
  fake <- structure(list(), class = "DBIConnection")
  # Source has habitat columns but no species_code
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT,
           c("blue_line_key", "downstream_route_measure",
             "spawning", "rearing")))
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
                        species = "CO",
                        habitat_types = c("spawning", "rearing"),
                        verbose = FALSE),
    "species_code")
})

# -- Empty table -> no-op ------------------------------------------------------

test_that("empty target table -> early return without error", {
  fake <- structure(list(), class = "DBIConnection")
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery", function(conn, sql) {
    if (grepl("DISTINCT species_code", sql)) {
      data.frame(species_code = character(0))
    } else if (grepl("FROM ws.h LIMIT 0", sql, fixed = TRUE)) {
      cols0(TBL_DEFAULT)
    } else {
      cols0(character(0))
    }
  })
  expect_silent(suppressMessages(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h", verbose = FALSE)
  ))
})

# -- SQL shape: canonical-shape dispatch ---------------------------------------

test_that("UPDATE SQL emits canonical-shape WHERE clause", {
  fake <- structure(list(), class = "DBIConnection")
  captured <- list()

  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT, SRC_DEFAULT))
  mockery::stub(frs_habitat_overlay, ".frs_db_execute", function(conn, sql) {
    captured[[length(captured) + 1L]] <<- sql
    3L
  })

  invisible(frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
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
  expect_match(sql, "k\\.species_code = 'CO'")
  expect_match(sql, "lower\\(trim\\(k\\.spawning::text\\)\\) IN \\('true', 't', '1'\\)")
  # Idempotency / additive guard — assert the parens so a refactor
  # that drops them (which would break AND/OR precedence) fails.
  expect_match(sql, "AND \\(h\\.spawning IS NULL OR h\\.spawning = FALSE\\)")
})

test_that("custom species_col interpolated into SQL", {
  fake <- structure(list(), class = "DBIConnection")
  captured <- list()
  src_cols <- c("blue_line_key", "downstream_route_measure",
                "sp_code", "spawning")
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT, src_cols))
  mockery::stub(frs_habitat_overlay, ".frs_db_execute", function(conn, sql) {
    captured[[length(captured) + 1L]] <<- sql
    0L
  })

  invisible(frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
                                species = "CO",
                                habitat_types = "spawning",
                                species_col = "sp_code",
                                verbose = FALSE))

  expect_length(captured, 1)
  expect_match(captured[[1]], "k\\.sp_code = 'CO'")
  expect_no_match(captured[[1]], "k\\.species_code = ")
})

# -- Custom join key parameter (`by`) ----------------------------------------

test_that("custom by= produces matching join predicate", {
  fake <- structure(list(), class = "DBIConnection")
  captured <- character(0)
  src_cols <- c("id_segment", "species_code", "spawning")
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT, src_cols))
  mockery::stub(frs_habitat_overlay, ".frs_db_execute", function(conn, sql) {
    captured <<- c(captured, sql); 0L
  })

  frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
                      species = "CO",
                      habitat_types = "spawning",
                      by = "id_segment",
                      verbose = FALSE)

  expect_length(captured, 1)
  expect_match(captured, "h\\.id_segment = k\\.id_segment")
  expect_no_match(captured, "blue_line_key")
})

# -- Direct mode on id_segment must name the keys `to` carries (fresh#277) -----

# Run direct mode with these column inventories; return the captured SQL, or
# the error message.
.ov_direct <- function(to_cols, from_cols, by) {
  fake <- structure(list(), class = "DBIConnection")
  captured <- character(0)
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq("CO", to_cols, from_cols))
  mockery::stub(frs_habitat_overlay, ".frs_db_execute", function(conn, sql) {
    captured <<- c(captured, sql)
    0L
  })
  tryCatch({
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h", species = "CO",
                        habitat_types = "spawning", by = by, verbose = FALSE)
    captured
  }, error = function(e) paste("ERROR:", conditionMessage(e)))
}

test_that("direct mode refuses id_segment without the group a multi-group to carries", {
  to_wsg <- c("id_segment", "watershed_group_code", "species_code", "spawning")
  from_wsg <- c("id_segment", "watershed_group_code", "species_code",
                "spawning")
  # id_segment repeats across groups, so this would write into every group
  # holding the same id.
  res <- .ov_direct(to_wsg, from_wsg, "id_segment")
  expect_match(res, "^ERROR:.*watershed_group_code")
  expect_match(res, "by")
  # Naming the group passes, and the join carries it.
  ok <- .ov_direct(to_wsg, from_wsg, c("id_segment", "watershed_group_code"))
  expect_length(ok, 1)
  expect_match(ok, "h.watershed_group_code = k.watershed_group_code",
               fixed = TRUE)
})

test_that("direct mode names the source when it lacks the group", {
  to_wsg <- c("id_segment", "watershed_group_code", "species_code", "spawning")
  from_no <- c("id_segment", "species_code", "spawning")
  # The caller cannot fix this through `by` alone: the source needs the column.
  res <- .ov_direct(to_wsg, from_no, "id_segment")
  expect_match(res, "^ERROR:.*ws\\.k.*watershed_group_code")
})

test_that("direct mode refuses id_segment without the parent both tables carry", {
  cols <- c("id_segment", "watershed_group_code", "linear_feature_id",
            "species_code", "spawning")
  # Since fresh#293 one group can hold two jobs' rows with the same derived
  # id_segment; the parent segment separates them.
  res <- .ov_direct(cols, cols, c("id_segment", "watershed_group_code"))
  expect_match(res, "^ERROR:.*linear_feature_id")
  ok <- .ov_direct(cols, cols,
                   c("id_segment", "watershed_group_code", "linear_feature_id"))
  expect_length(ok, 1)
  # Only the target carrying the parent: nothing to match it against.
  to_only <- .ov_direct(cols, setdiff(cols, "linear_feature_id"),
                        c("id_segment", "watershed_group_code"))
  expect_length(to_only, 1)
})

test_that("direct mode's point join is not affected by the id_segment rule", {
  cols <- c("blue_line_key", "downstream_route_measure", "id_segment",
            "watershed_group_code", "linear_feature_id", "species_code",
            "spawning")
  # A position on a blue line is unique across groups already.
  res <- .ov_direct(cols, cols, c("blue_line_key", "downstream_route_measure"))
  expect_length(res, 1)
  expect_no_match(res, "^ERROR:")
})

# -- NULL species -> all distinct species in the table ------------------------

test_that("NULL species pulls from table.species_code", {
  fake <- structure(list(), class = "DBIConnection")
  captured <- list()
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq(c("BT", "CO", "ST"), TBL_DEFAULT, SRC_DEFAULT))
  mockery::stub(frs_habitat_overlay, ".frs_db_execute", function(conn, sql) {
    captured[[length(captured) + 1L]] <<- sql; 0L
  })

  frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
                      habitat_types = "spawning", verbose = FALSE)

  # Three species x one habitat type = three UPDATE calls
  expect_length(captured, 3)
  expect_true(any(grepl("species_code = 'BT'", captured)))
  expect_true(any(grepl("species_code = 'CO'", captured)))
  expect_true(any(grepl("species_code = 'ST'", captured)))
})

# -- Identifier injection ----------------------------------------------------

test_that("malicious identifiers rejected by validator", {
  fake <- structure(list(), class = "DBIConnection")
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k; DROP TABLE x; --", to = "ws.h"))
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
                        habitat_types = c("ok_col", "bad; DROP --")))
})

# -- Integration: real DB, small fixture --------------------------------------

test_that("integration: canonical shape flips matching species/habitat", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, frs_test_tbl("test_overlay_h"))
    .frs_test_drop(conn, frs_test_tbl("test_overlay_k"))
    DBI::dbDisconnect(conn)
  })

  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       id_segment integer, species_code text,
       blue_line_key bigint, downstream_route_measure double precision,
       spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean)", frs_test_tbl("test_overlay_h")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (1, 'SK', 100, 10.0, FALSE, FALSE, FALSE, FALSE),
       (2, 'CO', 100, 10.0, FALSE, FALSE, FALSE, FALSE),
       (3, 'BT', 100, 20.0, FALSE, FALSE, FALSE, FALSE),
       (4, 'CO', 100, 30.0, FALSE, FALSE, FALSE, FALSE)", frs_test_tbl("test_overlay_h")))

  # Mix of integer 1, NULL, integer 0 to exercise indicator coercion.
  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       blue_line_key bigint, downstream_route_measure double precision,
       species_code text, spawning integer, rearing integer)", frs_test_tbl("test_overlay_k")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (100, 10.0, 'SK', 1,    NULL),
       (100, 10.0, 'CO', 1,    1),
       (100, 20.0, 'BT', NULL, 1),
       (100, 30.0, 'CO', 0,    NULL)", frs_test_tbl("test_overlay_k")))

  invisible(frs_habitat_overlay(conn,
    from = frs_test_tbl("test_overlay_k"),
    to   = frs_test_tbl("test_overlay_h"),
    species = c("SK", "CO", "BT"),
    habitat_types = c("spawning", "rearing"),
    verbose = FALSE))

  result <- DBI::dbGetQuery(conn,
    sprintf("SELECT id_segment, species_code, spawning, rearing
     FROM %s ORDER BY id_segment", frs_test_tbl("test_overlay_h")))

  # SK seg 1: spawning=1 -> TRUE; rearing NULL -> stays FALSE
  expect_equal(result$spawning[result$id_segment == 1L], TRUE)
  expect_equal(result$rearing[result$id_segment == 1L],  FALSE)
  # CO seg 2: both flip TRUE
  expect_equal(result$spawning[result$id_segment == 2L], TRUE)
  expect_equal(result$rearing[result$id_segment == 2L],  TRUE)
  # BT seg 3: spawning NULL -> stays; rearing=1 -> TRUE
  expect_equal(result$spawning[result$id_segment == 3L], FALSE)
  expect_equal(result$rearing[result$id_segment == 3L],  TRUE)
  # CO seg 4: spawning=0 -> stays FALSE (additive guard); rearing NULL -> stays
  expect_equal(result$spawning[result$id_segment == 4L], FALSE)
  expect_equal(result$rearing[result$id_segment == 4L],  FALSE)
})

test_that("integration: text 'TRUE'/'true'/'t' indicators flip", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, frs_test_tbl("test_overlay_txt_h"))
    .frs_test_drop(conn, frs_test_tbl("test_overlay_txt_k"))
    DBI::dbDisconnect(conn)
  })

  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       id_segment integer, species_code text,
       blue_line_key bigint, downstream_route_measure double precision,
       spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean)", frs_test_tbl("test_overlay_txt_h")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (1, 'CO', 100, 10.0, FALSE, FALSE, FALSE, FALSE),
       (2, 'CO', 100, 20.0, FALSE, FALSE, FALSE, FALSE),
       (3, 'CO', 100, 30.0, FALSE, FALSE, FALSE, FALSE),
       (4, 'CO', 100, 40.0, FALSE, FALSE, FALSE, FALSE)", frs_test_tbl("test_overlay_txt_h")))

  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       blue_line_key bigint, downstream_route_measure double precision,
       species_code text, spawning text, rearing text)", frs_test_tbl("test_overlay_txt_k")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (100, 10.0, 'CO', 'TRUE',  'false'),
       (100, 20.0, 'CO', 'true',  'f'),
       (100, 30.0, 'CO', 't',     ''),
       (100, 40.0, 'CO', 'maybe', NULL)", frs_test_tbl("test_overlay_txt_k")))

  invisible(frs_habitat_overlay(conn,
    from = frs_test_tbl("test_overlay_txt_k"),
    to   = frs_test_tbl("test_overlay_txt_h"),
    species = "CO",
    habitat_types = c("spawning", "rearing"),
    verbose = FALSE))

  result <- DBI::dbGetQuery(conn,
    sprintf("SELECT id_segment, spawning, rearing
     FROM %s ORDER BY id_segment", frs_test_tbl("test_overlay_txt_h")))
  # Seg 1-3: 'TRUE'/'true'/'t' all flip spawning; 'false'/'f'/'' do not
  expect_equal(result$spawning, c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(result$rearing,  c(FALSE, FALSE, FALSE, FALSE))
})

test_that("integration: already-TRUE rows are not re-touched (additive-only)", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, frs_test_tbl("test_overlay_addh"))
    .frs_test_drop(conn, frs_test_tbl("test_overlay_addk"))
    DBI::dbDisconnect(conn)
  })

  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       id_segment integer, species_code text,
       blue_line_key bigint, downstream_route_measure double precision,
       spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean)", frs_test_tbl("test_overlay_addh")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (1, 'CO', 100, 10.0, TRUE, FALSE, FALSE, FALSE),
       (2, 'CO', 100, 20.0, TRUE, FALSE, FALSE, FALSE)", frs_test_tbl("test_overlay_addh")))
  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       blue_line_key bigint, downstream_route_measure double precision,
       species_code text, spawning integer)", frs_test_tbl("test_overlay_addk")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (100, 10.0, 'CO', 1),
       (100, 20.0, 'CO', 1)", frs_test_tbl("test_overlay_addk")))

  invisible(frs_habitat_overlay(conn,
    to = frs_test_tbl("test_overlay_addh"),
    from = frs_test_tbl("test_overlay_addk"),
    species = "CO", habitat_types = "spawning",
    verbose = FALSE))

  # Both stay TRUE; the additive guard means no re-flip happened.
  result <- DBI::dbGetQuery(conn,
    sprintf("SELECT spawning FROM %s ORDER BY id_segment", frs_test_tbl("test_overlay_addh")))
  expect_equal(result$spawning, c(TRUE, TRUE))
})

# -- Bridge: range-containment 3-way join -------------------------------------

test_that("bridge requires schema-qualified name", {
  fake <- structure(list(), class = "DBIConnection")
  mockery::stub(frs_habitat_overlay, "DBI::dbGetQuery",
    mk_dbq("CO", TBL_DEFAULT, SRC_DEFAULT))
  expect_error(
    frs_habitat_overlay(fake, from = "ws.k", to = "ws.h",
                        bridge = "no_schema", species = "CO"),
    "schema-qualified")
})

test_that("bridge: missing required columns errors clearly", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, frs_test_tbl("test_bridge_h"))
    .frs_test_drop(conn, frs_test_tbl("test_bridge_s"))
    .frs_test_drop(conn, frs_test_tbl("test_bridge_k"))
    DBI::dbDisconnect(conn)
  })
  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       id_segment integer, species_code text,
       spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean)", frs_test_tbl("test_bridge_h")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES (1, 'CO', FALSE, FALSE, FALSE, FALSE)", frs_test_tbl("test_bridge_h")))
  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (id_segment integer)", frs_test_tbl("test_bridge_s")))  # missing range cols
  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       blue_line_key bigint, downstream_route_measure double precision,
       upstream_route_measure double precision,
       species_code text, spawning integer, rearing integer,
       lake_rearing integer, wetland_rearing integer)", frs_test_tbl("test_bridge_k")))

  expect_error(
    frs_habitat_overlay(conn,
      from = frs_test_tbl("test_bridge_k"),
      to   = frs_test_tbl("test_bridge_h"),
      bridge = frs_test_tbl("test_bridge_s"),
      species = "CO", verbose = FALSE),
    "missing required columns")
})

test_that("integration (bridge): range-containment flips contained segments", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit({
    .frs_test_drop(conn, frs_test_tbl("test_br_h"))
    .frs_test_drop(conn, frs_test_tbl("test_br_s"))
    .frs_test_drop(conn, frs_test_tbl("test_br_k"))
    DBI::dbDisconnect(conn)
  })

  # Target keyed by (id_segment, watershed_group_code)
  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       id_segment integer, watershed_group_code text, species_code text,
       spawning boolean, rearing boolean,
       lake_rearing boolean, wetland_rearing boolean)", frs_test_tbl("test_br_h")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (1, 'TEST', 'SK', FALSE, FALSE, FALSE, FALSE),
       (2, 'TEST', 'SK', FALSE, FALSE, FALSE, FALSE),
       (3, 'TEST', 'SK', FALSE, FALSE, FALSE, FALSE)", frs_test_tbl("test_br_h")))

  # Bridge: id_segment + group + range
  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       id_segment integer, watershed_group_code text, blue_line_key bigint,
       downstream_route_measure double precision,
       upstream_route_measure double precision)", frs_test_tbl("test_br_s")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (1, 'TEST', 100,   0,  50),
       (2, 'TEST', 100,  50, 100),
       (3, 'TEST', 100, 100, 200)", frs_test_tbl("test_br_s")))

  # Source: range [40, 110] for SK spawning
  DBI::dbExecute(conn,
    sprintf("CREATE TABLE %s (
       blue_line_key bigint, downstream_route_measure double precision,
       upstream_route_measure double precision,
       species_code text, spawning integer, rearing integer,
       lake_rearing integer, wetland_rearing integer)", frs_test_tbl("test_br_k")))
  DBI::dbExecute(conn,
    sprintf("INSERT INTO %s VALUES
       (100, 40.0, 110.0, 'SK', 1, NULL, NULL, NULL)", frs_test_tbl("test_br_k")))

  invisible(frs_habitat_overlay(conn,
    from   = frs_test_tbl("test_br_k"),
    to     = frs_test_tbl("test_br_h"),
    bridge = frs_test_tbl("test_br_s"),
    species = "SK",
    verbose = FALSE))

  result <- DBI::dbGetQuery(conn,
    sprintf("SELECT id_segment, spawning, rearing
     FROM %s ORDER BY id_segment", frs_test_tbl("test_br_h")))
  # Only segment 2 (50-100) is fully contained in [40, 110]
  expect_equal(result$spawning, c(FALSE, TRUE, FALSE))
  expect_equal(result$rearing,  c(FALSE, FALSE, FALSE))
})

test_that("integration (bridge): another watershed group sharing an id_segment is left alone", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  for (t in c("ov_h", "ov_s", "ov_k")) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", t))
  }
  # The bridge holds TEST only: segment 2 is blk 100, 50-100 m. The target is
  # shared, as fresh.streams_habitat is: OTHR reuses id_segment 2, and its own
  # segment 2 lies in another working table, nowhere near blk 100.
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE ov_s AS SELECT * FROM (VALUES
      (2, 'TEST'::text, 100::bigint, 50::double precision, 100::double precision)
    ) v(id_segment, watershed_group_code, blue_line_key,
        downstream_route_measure, upstream_route_measure)")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE ov_h AS SELECT * FROM (VALUES
      (2, 'TEST'::text, 'SK'::text, FALSE, FALSE),
      (2, 'OTHR', 'SK', FALSE, FALSE)
    ) v(id_segment, watershed_group_code, species_code, spawning, rearing)")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE ov_k AS SELECT * FROM (VALUES
      (100::bigint, 40::double precision, 110::double precision, 'SK'::text, 1)
    ) v(blue_line_key, downstream_route_measure, upstream_route_measure,
        species_code, spawning)")

  out <- utils::capture.output(frs_habitat_overlay(conn,
    from = "pg_temp.ov_k", to = "pg_temp.ov_h", bridge = "pg_temp.ov_s",
    species = "SK", habitat_types = "spawning"))
  got <- DBI::dbGetQuery(conn, "
    SELECT watershed_group_code AS wsg, spawning FROM pg_temp.ov_h ORDER BY 1")
  expect_true(got$spawning[got$wsg == "TEST"])
  expect_false(got$spawning[got$wsg == "OTHR"])
  # The per-species line counts this job's flip only
  expect_gt(length(out), 0)
  expect_match(out, "SK/spawning: 1 segments flipped", all = FALSE)
  expect_match(out, "1 total updates", all = FALSE)
})

test_that("bridge: `to` and `bridge` must carry watershed_group_code", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  for (t in c("ov2_h", "ov2_h_nowsg", "ov2_s", "ov2_s_nowsg", "ov2_k")) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", t))
  }
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE ov2_h (id_segment integer, watershed_group_code text,
      species_code text, spawning boolean)")
  DBI::dbExecute(conn, "INSERT INTO ov2_h VALUES (1, 'TEST', 'SK', FALSE)")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE ov2_h_nowsg AS SELECT id_segment, species_code, spawning
    FROM ov2_h")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE ov2_s (id_segment integer, watershed_group_code text,
      blue_line_key bigint, downstream_route_measure double precision,
      upstream_route_measure double precision)")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE ov2_s_nowsg AS SELECT id_segment, blue_line_key,
      downstream_route_measure, upstream_route_measure FROM ov2_s")
  DBI::dbExecute(conn, "
    CREATE TEMP TABLE ov2_k (blue_line_key bigint,
      downstream_route_measure double precision,
      upstream_route_measure double precision, species_code text,
      spawning integer)")

  expect_error(
    frs_habitat_overlay(conn, from = "pg_temp.ov2_k", to = "pg_temp.ov2_h_nowsg",
      bridge = "pg_temp.ov2_s", species = "SK", habitat_types = "spawning",
      verbose = FALSE),
    "pg_temp.ov2_h_nowsg.*watershed_group_code")
  expect_error(
    frs_habitat_overlay(conn, from = "pg_temp.ov2_k", to = "pg_temp.ov2_h",
      bridge = "pg_temp.ov2_s_nowsg", species = "SK", habitat_types = "spawning",
      verbose = FALSE),
    "pg_temp.ov2_s_nowsg.*watershed_group_code")
  # Both carrying it: no error, nothing to flip
  expect_no_error(
    frs_habitat_overlay(conn, from = "pg_temp.ov2_k", to = "pg_temp.ov2_h",
      bridge = "pg_temp.ov2_s", species = "SK", habitat_types = "spawning",
      verbose = FALSE))
})
