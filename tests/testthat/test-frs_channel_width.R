# --- Unit tests (no DB) ---

.cw_cols_default <- c(
  linear_feature_id = "bigint",
  upstream_area_ha = "double precision",
  map_upstream = "integer",
  channel_width = "double precision",
  channel_width_source = "text"
)

# Run frs_channel_width() against a mocked connection. Returns the SQL it
# executed. `cols` is the mocked table schema (named: column -> type).
# Each UPDATE reports `n_rows` rows affected in turn; the still-NULL count
# query returns `n_null`.
.run_cw <- function(..., cols = .cw_cols_default, n_rows = c(0L, 0L),
                    n_null = 0L, verbose = FALSE) {
  sql_log <- character(0)
  i_upd <- 0L
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      if (!grepl("^UPDATE", sql)) return(0L)
      i_upd <<- i_upd + 1L
      n_rows[[i_upd]]
    }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      if (grepl("pg_attribute", sql)) {
        data.frame(column_name = names(cols), data_type = unname(cols),
                   stringsAsFactors = FALSE)
      } else {
        data.frame(n_null = n_null)
      }
    },
    .package = "DBI"
  )
  frs_channel_width("mock", "working.streams", ..., verbose = verbose)
  sql_log
}

.cw_sql <- function(model, col_area = "upstream_area_ha",
                    col_precip = "map_upstream") {
  .frs_channel_width_sql(.frs_channel_width_models(model), col_area,
                         col_precip)
}

test_that("poisson2021 preset reproduces the fwapg expression", {
  sql <- .cw_sql("poisson2021")
  expect_match(sql, "^round\\(\\(exp\\(0.30713\\) \\* ")
  expect_match(sql,
    "\\(\\(upstream_area_ha::double precision \\+ 1\\) / 100\\) \\^ 0.4577882",
    fixed = FALSE)
  expect_match(sql,
    "\\(\\(map_upstream::double precision \\+ 1\\) / 1000\\) \\^ 0.4577882")
  expect_match(sql, "::numeric, 2\\)::double precision$")
})

test_that("hall2007 preset converts ha to km2 and mm to cm, unrounded", {
  sql <- .cw_sql("hall2007")
  expect_match(sql, "^0.196 \\* ")
  expect_match(sql,
    "\\(\\(upstream_area_ha::double precision \\+ 0\\) / 100\\) \\^ 0.28")
  expect_match(sql,
    "\\(\\(map_upstream::double precision \\+ 0\\) / 10\\) \\^ 0.355")
  expect_false(grepl("round", sql))
})

test_that("preset coefficients match the published formulas", {
  ev <- function(m, A, P) {
    with(.frs_channel_width_models(m),
         k * ((A + a_off) / a_div)^a * ((P + p_off) / p_div)^b)
  }
  A <- 2500
  P <- 800
  # fwapg channel_width_modelled.sql, where its area already carries the +1
  fwapg <- exp(0.3071300 + 0.4577882 *
                 (log(A + 1) + log(P + 1) - log(100) - log(1000)))
  expect_equal(ev("poisson2021", A, P), fwapg, tolerance = 1e-9)
  # flooded fl_flood_surface(): km2 and cm/yr
  hall <- ((A / 100)^0.280) * 0.196 * ((P / 10)^0.355)
  expect_equal(ev("hall2007", A, P), hall, tolerance = 1e-12)
})

test_that("custom coefficients are formatted and labelled", {
  m <- list(k = 2, a = 0.5, b = 0.3, a_div = 100, p_div = 10,
            a_off = 0, p_off = 1, digits = 1)
  sql <- .cw_sql(m)
  expect_match(sql, "^round\\(\\(2 \\* ")
  expect_match(sql, "map_upstream::double precision \\+ 1\\) / 10\\) \\^ 0.3")
  expect_match(sql, "::numeric, 1\\)")
  expect_equal(.frs_channel_width_models(m)$label, "MODELLED_CUSTOM")
  expect_false(grepl("round", .cw_sql(m[names(m) != "digits"])))

  log <- .run_cw(model = m)
  expect_true(any(grepl("channel_width_source = 'MODELLED_CUSTOM'", log)))
})

test_that("model validation rejects bad input", {
  ok <- list(k = 1, a = 0.5, b = 0.3, a_div = 1, p_div = 10,
             a_off = 0, p_off = 0)
  expect_error(.frs_channel_width_models("nope"),
               "Unknown channel width model")
  expect_error(.frs_channel_width_models(c("poisson2021", "hall2007")),
               "Unknown channel width model")
  expect_error(.frs_channel_width_models(list(k = 1, a = 0.5)),
               "missing: b, a_div, p_div, a_off, p_off")
  expect_error(.frs_channel_width_models(c(ok, z = 1)), "unknown fields: z")
  expect_error(.frs_channel_width_models(modifyList(ok, list(k = "1"))),
               "model\\$k")
  expect_error(.frs_channel_width_models(modifyList(ok, list(a = NA_real_))),
               "model\\$a")
  expect_error(.frs_channel_width_models(modifyList(ok, list(a_div = 0))),
               "a_div")
  expect_error(.frs_channel_width_models(modifyList(ok, list(digits = 1.5))),
               "digits")
  expect_error(.frs_channel_width_models(1), "preset name or a named list")
})

test_that("identifiers are validated", {
  expect_error(frs_channel_width("mock", "DROP TABLE x"), "invalid characters")
  expect_error(frs_channel_width("mock", "working.s", to = "w; DROP"),
               "invalid characters")
  expect_error(frs_channel_width("mock", "working.s", col_area = "a b"),
               "invalid characters")
  expect_error(frs_channel_width("mock", "working.s", col_source = "x'y"),
               "invalid characters")
})

test_that("output columns cannot collide with inputs or each other", {
  expect_error(.run_cw(to = "upstream_area_ha"), "`to` must differ")
  expect_error(.run_cw(col_source = "map_upstream"),
               "`col_source` must differ")
  expect_error(.run_cw(col_source = "channel_width"),
               "`col_source` must differ")
})

test_that("missing input columns error with the frs_col_join recipe", {
  cols <- .cw_cols_default
  expect_error(.run_cw(cols = cols[names(cols) != "upstream_area_ha"]),
               "upstream_area_ha not found.*frs_col_join")
  expect_error(.run_cw(cols = cols[names(cols) != "map_upstream"]),
               "map_upstream not found.*frs_col_join")
  expect_error(.run_cw(cols = character(0)), "not found")
})

test_that("existing output columns must have usable types", {
  cols <- .cw_cols_default
  cols["channel_width"] <- "integer"
  expect_error(.run_cw(cols = cols), "channel_width exists as integer")
  cols <- .cw_cols_default
  cols["channel_width_source"] <- "integer"
  expect_error(.run_cw(cols = cols), "channel_width_source exists as integer")
})

test_that("default run fills only NULL rows and labels only those", {
  log <- .run_cw()
  expect_true(any(grepl(
    "ADD COLUMN IF NOT EXISTS channel_width double precision", log)))
  expect_true(any(grepl(
    "ADD COLUMN IF NOT EXISTS channel_width_source text", log)))
  upd <- grep("^UPDATE", log, value = TRUE)
  expect_length(upd, 1)
  expect_match(upd, "SET channel_width = round\\(")
  expect_match(upd, "channel_width_source = 'MODELLED_POISSON2021'")
  expect_match(upd, "WHERE channel_width IS NULL AND ")
  # Bases guarded so NULL / non-positive inputs are skipped, not errors
  expect_match(upd, "\\(upstream_area_ha::double precision \\+ 1\\) > 0")
  expect_match(upd, "\\(map_upstream::double precision \\+ 1\\) > 0")
})

test_that("source column defaults to <to>_source", {
  log <- .run_cw(model = "hall2007", to = "channel_width_hall")
  expect_true(any(grepl(
    "ADD COLUMN IF NOT EXISTS channel_width_hall_source text", log)))
  upd <- grep("^UPDATE", log, value = TRUE)
  expect_match(upd, "channel_width_hall_source = 'MODELLED_HALL2007'")
  expect_false(any(grepl("channel_width_source", log)))
})

test_that("col_source = NULL writes no label", {
  log <- .run_cw(col_source = NULL)
  expect_false(any(grepl("_source", log)))
})

test_that("overwrite = TRUE rewrites every row in one statement", {
  log <- .run_cw(overwrite = TRUE)
  upd <- grep("^UPDATE", log, value = TRUE)
  # a separate clear-then-fill would wipe widths if the fill failed
  expect_length(upd, 1)
  expect_match(upd, "SET channel_width = CASE WHEN .* THEN round\\(")
  expect_match(upd,
    "channel_width_source = CASE WHEN .* THEN 'MODELLED_POISSON2021' END$")
  expect_false(grepl("WHERE", upd))
})

test_that("mixed-case names compare as Postgres folds them", {
  log <- .run_cw(to = "CW_Est", col_area = "Upstream_Area_Ha")
  expect_true(any(grepl("ADD COLUMN IF NOT EXISTS cw_est double precision",
                        log)))
  expect_true(any(grepl("cw_est_source = 'MODELLED_POISSON2021'", log)))
})

test_that("type checks ignore typmods", {
  cols <- .cw_cols_default
  cols["channel_width"] <- "numeric(10,2)"
  cols["channel_width_source"] <- "character varying(40)"
  expect_no_error(.run_cw(cols = cols))
})

test_that("returns conn invisibly", {
  local_mocked_bindings(.frs_db_execute = function(conn, sql) 0L)
  local_mocked_bindings(
    dbGetQuery = function(conn, sql) {
      data.frame(column_name = names(.cw_cols_default),
                 data_type = unname(.cw_cols_default))
    },
    .package = "DBI"
  )
  expect_invisible(out <- frs_channel_width("mock", "working.streams",
                                            verbose = FALSE))
  expect_identical(out, "mock")
})

test_that("value fills what the regression leaves NULL, labelled ASSIGNED", {
  log <- .run_cw(value = 1.5)
  upd <- grep("^UPDATE", log, value = TRUE)
  expect_length(upd, 2)
  expect_match(upd[1], "SET channel_width = round\\(")
  expect_equal(upd[2], paste(
    "UPDATE working.streams SET channel_width = 1.5,",
    "channel_width_source = 'ASSIGNED' WHERE channel_width IS NULL"))
})

test_that("value runs after an overwrite too, without a label if asked", {
  log <- .run_cw(value = 2, overwrite = TRUE, col_source = NULL)
  upd <- grep("^UPDATE", log, value = TRUE)
  expect_length(upd, 2)
  expect_match(upd[1], "CASE WHEN")
  expect_equal(upd[2], paste(
    "UPDATE working.streams SET channel_width = 2",
    "WHERE channel_width IS NULL"))
})

test_that("value must be a positive finite number", {
  for (bad in list(0, -1, NA_real_, Inf, "1", c(1, 2), TRUE)) {
    expect_error(frs_channel_width("mock", "working.s", value = bad),
                 "`value` must be")
  }
})

test_that("integer64 value and coefficients render as numbers", {
  skip_if_not_installed("bit64")
  log <- .run_cw(value = bit64::as.integer64(2))
  expect_true(any(grepl("SET channel_width = 2,", log)))
  m <- list(k = bit64::as.integer64(2), a = 0.5, b = 0.3, a_div = 100,
            p_div = 10, a_off = 0, p_off = 0)
  expect_match(.cw_sql(m), "^2 \\* ")
})

test_that("verbose reports modelled, assigned and still-NULL counts", {
  expect_message(
    .run_cw(value = 1, n_rows = c(5L, 2L), n_null = 2L, verbose = TRUE),
    "channel_width: 5 modelled \\(MODELLED_POISSON2021\\), 2 assigned, 0 still NULL")
  expect_message(
    .run_cw(n_rows = 5L, n_null = 3L, verbose = TRUE),
    "5 modelled .*, 0 assigned, 3 still NULL")
  # overwrite touches every row; modelled = rows written minus rows left NULL
  expect_message(
    .run_cw(overwrite = TRUE, n_rows = 15L, n_null = 4L, verbose = TRUE),
    "11 modelled .*, 0 assigned, 4 still NULL")
})

test_that("verbose = FALSE runs no count query and says nothing", {
  expect_silent(log <- .run_cw(value = 1))
  expect_false(any(grepl("count\\(", log)))
})


# --- Integration tests (live DB, Byman-Ailport AOI) ---

# Extract the AOI and join existing widths plus both regression inputs.
# Area is the largest upstream area per wscode/localcode pair: fwapg's
# MODELLED convention, so poisson2021 can be compared to it directly.
.cw_live_table <- function(conn, to) {
  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = to,
    cols = c("linear_feature_id", "stream_order", "wscode_ltree",
             "localcode_ltree", "geom"),
    aoi = readRDS(system.file("extdata", "test_streamline.rds",
                              package = "fresh")),
    overwrite = TRUE)
  frs_col_join(conn, to,
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")
  frs_col_join(conn, to,
    from = "(SELECT s.wscode_ltree, s.localcode_ltree,
                    max(ua.upstream_area_ha) AS upstream_area_ha
             FROM whse_basemapping.fwa_stream_networks_sp s
             JOIN whse_basemapping.fwa_streams_watersheds_lut l
               ON s.linear_feature_id = l.linear_feature_id
             JOIN whse_basemapping.fwa_watersheds_upstream_area ua
               ON l.watershed_feature_id = ua.watershed_feature_id
             WHERE s.watershed_group_code = 'BULK'
             GROUP BY s.wscode_ltree, s.localcode_ltree)",
    cols = "upstream_area_ha",
    by = c("wscode_ltree", "localcode_ltree"))
  frs_col_join(conn, to,
    from = "whse_basemapping.fwa_stream_networks_mean_annual_precip",
    cols = "map_upstream",
    by = c("wscode_ltree", "localcode_ltree"))
  invisible(to)
}

test_that("SQL matches the presets and poisson2021 reproduces fwapg MODELLED", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  tbl <- "working.test_channel_width_est"
  on.exit({
    .frs_test_drop(conn, tbl)
    DBI::dbDisconnect(conn)
  })
  .cw_live_table(conn, tbl)
  # One row with a missing input, so the NULL-input path runs on real data
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s SET upstream_area_ha = NULL WHERE linear_feature_id =
       (SELECT min(linear_feature_id) FROM %s
        WHERE channel_width_source IS DISTINCT FROM 'MODELLED')", tbl, tbl))

  conn |>
    frs_channel_width(tbl, to = "cw_poisson", verbose = FALSE) |>
    frs_channel_width(tbl, model = "hall2007", to = "cw_hall",
                      verbose = FALSE)

  res <- DBI::dbGetQuery(conn, sprintf(
    "SELECT upstream_area_ha::double precision AS area_ha,
            map_upstream::double precision AS precip_mm,
            channel_width, channel_width_source, cw_poisson, cw_hall,
            cw_poisson_source, cw_hall_source
     FROM %s", tbl))

  modelled <- res[res$channel_width_source %in% "MODELLED", ]
  expect_gt(nrow(modelled), 0)
  # Measured 2026-10-07: 9 MODELLED rows, max |diff| 0.03 m. Residual is
  # input-snapshot drift, not the formula (findings.md, #234).
  expect_true(all(abs(modelled$cw_poisson - modelled$channel_width) <= 0.05))
  expect_true(all(res$cw_poisson_source[!is.na(res$cw_poisson)] ==
                    "MODELLED_POISSON2021"))

  # The SQL agrees row by row with the preset evaluated in R. (Which model
  # is wider depends on area and precipitation together, so no fixed
  # inequality between them holds.)
  ev <- function(m) {
    with(.frs_channel_width_models(m),
         k * ((res$area_ha + a_off) / a_div)^a *
           ((res$precip_mm + p_off) / p_div)^b)
  }
  has <- !is.na(res$area_ha) & !is.na(res$precip_mm)
  expect_gt(sum(has), 0)
  expect_equal(res$cw_poisson[has], round(ev("poisson2021")[has], 2))
  expect_equal(res$cw_hall[has], ev("hall2007")[has])
  expect_equal(sum(!has), 1L)
  expect_true(all(is.na(res$cw_poisson[!has])))
  expect_true(all(is.na(res$cw_hall[!has])))
  expect_true(all(res$cw_hall[has] > 0))
  expect_true(all(res$cw_hall_source[!is.na(res$cw_hall)] ==
                    "MODELLED_HALL2007"))

  # overwrite rewrites in place: same values, mixed-case names resolve
  frs_channel_width(conn, toupper(tbl), to = "CW_Poisson", overwrite = TRUE,
                    verbose = FALSE)
  again <- DBI::dbGetQuery(conn, sprintf(
    "SELECT cw_poisson, cw_poisson_source FROM %s", tbl))
  expect_equal(sort(again$cw_poisson), sort(res$cw_poisson))
  expect_equal(sum(!is.na(again$cw_poisson_source)),
               sum(!is.na(res$cw_poisson)))
})

test_that("default call fills NULL widths and leaves existing ones alone", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  tbl <- "working.test_channel_width_fill"
  on.exit({
    .frs_test_drop(conn, tbl)
    DBI::dbDisconnect(conn)
  })
  .cw_live_table(conn, tbl)

  sql_before <- sprintf(
    "SELECT linear_feature_id, channel_width, channel_width_source
     FROM %s WHERE channel_width IS NOT NULL ORDER BY linear_feature_id", tbl)
  before <- DBI::dbGetQuery(conn, sql_before)
  n_null <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s WHERE channel_width IS NULL", tbl))$n
  expect_gt(nrow(before), 0)
  expect_gt(n_null, 1)
  # Stand-in for a placeholder / unmapped segment: NULL width, no inputs
  id_no_input <- DBI::dbGetQuery(conn, sprintf(
    "SELECT min(linear_feature_id) AS id FROM %s
     WHERE channel_width IS NULL", tbl))$id
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s SET upstream_area_ha = NULL, map_upstream = NULL
     WHERE linear_feature_id = %s", tbl, id_no_input))

  expect_message(
    frs_channel_width(conn, tbl, value = 0.5),
    sprintf(
      "^channel_width: %d modelled \\(MODELLED_POISSON2021\\), 1 assigned, 0 still NULL",
      n_null - 1L))

  after <- DBI::dbGetQuery(conn, sprintf(
    "SELECT linear_feature_id, channel_width, channel_width_source
     FROM %s WHERE linear_feature_id IN (%s) ORDER BY linear_feature_id",
    tbl, paste(before$linear_feature_id, collapse = ", ")))
  expect_identical(after, before)

  filled <- DBI::dbGetQuery(conn, sprintf(
    "SELECT stream_order, channel_width FROM %s
     WHERE channel_width_source = 'MODELLED_POISSON2021'", tbl))
  expect_equal(nrow(filled), n_null - 1L)
  expect_true(all(filled$channel_width > 0))
  expect_true(all(filled$stream_order == 1L))

  assigned <- DBI::dbGetQuery(conn, sprintf(
    "SELECT linear_feature_id, channel_width FROM %s
     WHERE channel_width_source = 'ASSIGNED'", tbl))
  expect_equal(assigned$linear_feature_id, id_no_input)
  expect_equal(assigned$channel_width, 0.5)
  expect_equal(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s WHERE channel_width IS NULL",
    tbl))$n, 0L)
})
