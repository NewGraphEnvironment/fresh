# =====================================================================
# frs_order_child — direct-child-of-large-parent rearing classifier
# =====================================================================
#
# Post-classification UPDATE that adds <label> = TRUE to direct-child
# segments of large-order rivers. Mocked SQL-shape tests confirm the
# emitted SQL matches the design spec from fresh#158.

# Helper: run with mocked DBI calls, return the captured UPDATE SQL.
.run_order_child <- function(...) {
  update_sql <- character(0)
  testthat::local_mocked_bindings(
    .package = "DBI",
    dbExecute = function(conn, statement, ...) {
      update_sql <<- c(update_sql, statement)
      0L
    },
    dbGetQuery = function(conn, statement, ...) {
      data.frame(n = 0L)
    }
  )
  defaults <- list(
    conn = "mock",
    table = "fresh.streams",
    habitat = "fresh.streams_habitat",
    species = "BT",
    verbose = FALSE)
  user <- list(...)
  args <- modifyList(defaults, user)
  do.call(frs_order_child, args)
  update_sql
}

test_that("frs_order_child default emits canonical bcfishpass-parity SQL", {
  sql_log <- .run_order_child()
  expect_length(sql_log, 1L)
  s <- sql_log[1]

  # UPDATE target + label
  expect_match(s, "UPDATE fresh\\.streams_habitat h")
  expect_match(s, "SET rearing = TRUE")

  # CTE wraps the streams source to derive stream_order_max
  expect_match(s, "FROM fresh\\.streams\\s*\\n")
  expect_match(s, "FROM s\\b")

  # Required guards
  expect_match(s, "h\\.species_code = 'BT'")
  expect_match(s, "h\\.accessible = TRUE")
  expect_match(s, "h\\.rearing IS NOT TRUE")

  # bcfp-parity defaults: child stream_order = 1 (both bounds default
  # to 1L when caller passes neither — matches bcfp's hardcoded
  # `stream_order = 1` predicate).
  expect_match(s, "s\\.stream_order >= 1")
  expect_match(s, "s\\.stream_order <= 1")
  expect_match(s, "s\\.stream_order_parent >= 5")

  # Per-BLK stream_order_max derived in CTE, predicate enforces direct-
  # child mouth-side reach (excludes headwater portions of multi-order
  # BLKs that grow to higher order at their mouth).
  expect_match(s, "MAX\\(stream_order\\) OVER \\(PARTITION BY blue_line_key\\)")
  expect_match(s, "s\\.stream_order = s\\.stream_order_max")

  # Distance clause not present at default
  expect_no_match(s, "downstream_route_measure")
})

test_that("frs_order_child emits child_order_min/max bounds when set", {
  sql_log <- .run_order_child(child_order_min = 2L, child_order_max = 4L)
  s <- sql_log[1]

  expect_match(s, "s\\.stream_order >= 2")
  expect_match(s, "s\\.stream_order <= 4")
  # Direct-child mouth-side reach predicate stays on regardless of
  # caller-passed child bounds.
  expect_match(s, "s\\.stream_order = s\\.stream_order_max")
})

test_that("frs_order_child emits distance_max clause when set", {
  sql_log <- .run_order_child(distance_max = 300)
  s <- sql_log[1]
  expect_match(s, "s\\.downstream_route_measure <= 300")
})

test_that("frs_order_child SQL always derives stream_order_max via CTE", {
  # `stream_order_max` is the direct-child filter that bounds the bypass
  # to the mouth-side reach of a BLK. Without it, multi-order BLKs (a
  # named creek that grows from order-1 headwaters to order-3 mouth)
  # would have their order-1 headwater segments credited even though
  # they are not direct trib reaches of large rivers.
  #
  # fresh.streams doesn't store stream_order_max; the CTE derives it
  # via window function so the predicate works against either source.
  for (args in list(
    list(),
    list(child_order_min = 1L),
    list(child_order_max = 3L),
    list(child_order_min = 1L, child_order_max = 2L),
    list(distance_max = 500),
    list(parent_order_min = 7L),
    list(label = "lake_rearing"))) {
    sql <- do.call(.run_order_child, args)
    expect_match(sql[1],
      "MAX\\(stream_order\\) OVER \\(PARTITION BY blue_line_key\\)",
      info = paste("args:", paste(names(args), collapse = ",")))
    expect_match(sql[1], "s\\.stream_order = s\\.stream_order_max",
      info = paste("args:", paste(names(args), collapse = ",")))
  }
})

test_that("frs_order_child handles parent_order_min override", {
  sql_log <- .run_order_child(parent_order_min = 7L)
  s <- sql_log[1]
  expect_match(s, "s\\.stream_order_parent >= 7")
  expect_no_match(s, "stream_order_parent >= 5")
})

test_that("frs_order_child works on non-rearing label (lake_rearing)", {
  sql_log <- .run_order_child(label = "lake_rearing")
  s <- sql_log[1]
  # All three label references swap together
  expect_match(s, "SET lake_rearing = TRUE")
  expect_match(s, "h\\.lake_rearing IS NOT TRUE")
  expect_no_match(s, "SET rearing = TRUE")
})

test_that("frs_order_child species code is SQL-quoted (defends against injection)", {
  sql_log <- .run_order_child(species = "O'Brien")
  s <- sql_log[1]
  # Single quote doubled — bcfishpass schema IDs are enum-like so this is
  # paranoia, but the helper does it anyway via .frs_quote_string.
  expect_match(s, "h\\.species_code = 'O''Brien'")
})

test_that("frs_order_child rejects bad identifiers", {
  expect_error(
    frs_order_child("mock", table = "bad;name", habitat = "h",
      species = "BT"),
    "table contains invalid"
  )
  expect_error(
    frs_order_child("mock", table = "fresh.streams", habitat = "h",
      species = ""),
    "species must be a single non-empty string"
  )
  expect_error(
    frs_order_child("mock", table = "fresh.streams", habitat = "h",
      species = "BT", parent_order_min = "five"),
    "parent_order_min must be a numeric scalar"
  )
})
