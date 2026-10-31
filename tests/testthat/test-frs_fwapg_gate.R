# What NewGraphEnvironment/fwapg#41's rework changes on fresh's own code paths
# (#266). These run against a database that has the migration, or against one
# trialled through FRESH_FWAPG_TRIAL; without either they skip, naming the
# migration. FRESH_FWAPG_CURRENT=true says the database should already have
# it, and then they fail instead of skipping.
#
# The first pin is constructed by query rather than found: a measure exactly
# equal to a blue line's maximum upstream_route_measure, which the pre-rework
# function cannot place (see skip_unless_head_case() for why). No candidate
# segment has an integer upstream_route_measure (whole_metre_top = 0, measured
# in the sweep), so fresh's own clamped measure never lands there — but a
# caller passing a segment's own upstream measure does, which is what link
# does. The second pin is the one position of 970 that the sweep found
# erroring before the migration and not after.

# The exact top of a blue line among the segments fresh would snap to — this
# chooses the measure, so fresh's guards belong here; proving the red side over
# the population fwa_locatealong() actually scans is skip_unless_head_case()'s
# job. Derived rather than retyped, and kept at full precision, which is what
# frs_point_locate() sends since #274 (it wrote 15 significant digits before).
blk_top <- function(conn, blk) {
  m <- DBI::dbGetQuery(conn, sprintf(
    "SELECT max(upstream_route_measure) AS m
     FROM whse_basemapping.fwa_stream_networks_sp
     WHERE blue_line_key = %d
       AND localcode_ltree IS NOT NULL AND NOT wscode_ltree <@ '999'
       AND edge_type <> 1425", blk))$m
  if (is.na(m)) NA_real_ else m
}

# The head case, stated as the property that makes it one and checked without
# the migration. The pre-rework fwa_locatealong() compares bounds ROUNDED TO 4
# DECIMALS:
#   round(ds, 4) <= round(m, 4) AND round(us, 4) > round(m, 4)
# so a measure at a stream's top can never be placed — `round(us, 4) >
# round(us, 4)` is false by construction, whatever the range's openness. That
# predicate selecting nothing is the red side, and it is the same query on any
# database, whichever version of the function is installed.
#
# It is scanned over EVERY segment of the blue line, with none of fresh's
# candidate guards, because fwa_locatealong() has none either — its only
# predicate is on blue_line_key and the two rounded measures. Carrying the
# guards here would have modelled a narrower population than the function
# scans: measured over 20,000 blue lines, 109 of them have an unguarded
# segment (a 1425 connector, a NULL local code, a `999.*` code) whose range
# holds the guarded maximum, so the guard would pass while the pre-rework
# function resolves the measure and the pin goes green on a stale database.
skip_unless_head_case <- function(conn, blk, m) {
  n <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) FILTER (
              WHERE round(downstream_route_measure::numeric, 4) <= round(%1$s::numeric, 4)
                AND round(upstream_route_measure::numeric, 4) > round(%1$s::numeric, 4)) AS old_rule,
            count(*) FILTER (
              WHERE round(downstream_route_measure::numeric, 4) <= round(%1$s::numeric, 4)
                AND round(upstream_route_measure::numeric, 4) >= round(%1$s::numeric, 4)) AS closed,
            round(max(upstream_route_measure)::numeric, 4) >= round(%1$s::numeric, 4) AS at_top
     FROM whse_basemapping.fwa_stream_networks_sp
     WHERE blue_line_key = %2$d", .frs_sql_exact(m, "m"), blk))
  skip_if_not(isTRUE(n$at_top) && n$old_rule == 0L && n$closed >= 1L,
              sprintf("blue line %d at %s is not a head case on this database", blk,
                      .frs_sql_exact(m, "m")))
}

# Blue line 360447231, named rather than searched for. Of 400 streams sampled
# by ORDER BY md5(blue_line_key), 2 resolved their own top measure before the
# migration and 218 after (#266) — the head case is the common case, not a
# rarity. How that sample wrote its tops is not recorded, so
# skip_unless_head_case() re-checks the column rule at the exact top; it does
# not check ST_LocateAlong() on the geometry, which expect_gt() below does.
head_blk <- 360447231L

test_that("fwa_locatealong() resolves a measure at a stream's head", {
  conn <- local_fwapg_indexpoint()
  m <- blk_top(conn, head_blk)
  skip_if(is.na(m), sprintf("blue line %d is not on this database", head_blk))
  skip_unless_head_case(conn, head_blk, m)

  located <- frs_point_locate(conn, blue_line_key = head_blk,
                              downstream_route_measure = m)
  expect_gt(nrow(located), 0L)
  expect_equal(sf::st_crs(located)$epsg, 3005L)
})

# The position data-raw/logs/indexpoint_266/sweep_errors.csv found: one of 970
# swept positions where fwa_watershedatmeasure() raised
#   line_interpolate_point: 2nd arg isn't within [0,1]
# before the migration and does not after. The error comes through
# fwa_upstreambordercrossings, which the tiebreak migration rewrites —
# fwa_watershedatmeasure's own segment pick
# (`downstream_route_measure <= v_measure ORDER BY desc LIMIT 1`) has no top
# bound to close, so there is no placement to pin, only error -> no error.
err_blk <- 359434058L
err_m <- 159

test_that("fwa_watershedatmeasure() no longer errors where it used to", {
  conn <- local_fwapg_indexpoint()
  n <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) AS n FROM whse_basemapping.fwa_stream_networks_sp
     WHERE blue_line_key = %d AND downstream_route_measure <= %s", err_blk, err_m))$n
  skip_if(n == 0L, sprintf("blue line %d at %s is not on this database", err_blk, err_m))

  # The red side, on a second connection with no trial applied, so it reads
  # committed state. Only meaningful while that state still predates the
  # migration; once the database itself is current there is no red side left.
  plain <- local_fwapg()
  if (!frs_indexpoint_current(plain)) {
    expect_error(
      frs_watershed_at_measure(plain, blue_line_key = err_blk,
                               downstream_route_measure = err_m),
      "line_interpolate_point")
  }
  expect_no_error(
    frs_watershed_at_measure(conn, blue_line_key = err_blk,
                             downstream_route_measure = err_m))
})

# -- the gate ------------------------------------------------------------------

# This one FAILS rather than skips when FRESH_FWAPG_CURRENT says the database
# should be current. Its own direct connection, reading committed state: not
# skip_if_no_conn(), not local_fwapg_indexpoint(), and never a trial's
# connection, so neither an unreachable database nor a stale one nor a
# rolled-back trial can turn this suite green.
test_that("FRESH_FWAPG_CURRENT=true means the database really is current", {
  skip_if_not(frs_fwapg_current_wanted(),
              "FRESH_FWAPG_CURRENT is not set: nothing is claimed about this database")
  conn <- frs_fwapg_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  # deliberately NOT wrapped in tryCatch: ::regproc throws when the function
  # is absent or ambiguous, and that is a failure here, not a skip
  args <- DBI::dbGetQuery(conn,
    "SELECT pg_get_function_arguments('whse_basemapping.fwa_indexpoint'::regproc) AS a")$a
  expect_match(paste(args, collapse = " "), "include_disconnected")
  expect_false(DBI::dbGetQuery(conn, "
    SELECT p.prosrc ~* 'exbc' AS e FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'whse_basemapping' AND p.proname = 'fwa_watershedatmeasure'")$e)
})
