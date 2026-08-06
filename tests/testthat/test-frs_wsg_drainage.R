# -- arg validation (no DB needed) -------------------------------------------

test_that("frs_wsg_drainage rejects non-character watershed_group_code", {
  expect_error(
    frs_wsg_drainage(NULL, watershed_group_code = 1:3),
    "is.character"
  )
})

test_that("frs_wsg_drainage rejects empty watershed_group_code", {
  expect_error(
    frs_wsg_drainage(NULL, watershed_group_code = character(0)),
    "length"
  )
})

test_that("frs_wsg_drainage rejects NA in watershed_group_code", {
  expect_error(
    frs_wsg_drainage(NULL, watershed_group_code = c("BULK", NA_character_)),
    "anyNA"
  )
})

test_that("frs_wsg_drainage rejects empty-string focal codes", {
  expect_error(
    frs_wsg_drainage(NULL, watershed_group_code = c("BULK", "")),
    "nzchar"
  )
})

test_that("frs_wsg_drainage rejects an outlets table missing columns", {
  expect_error(
    frs_wsg_drainage(NULL, "BULK", outlets = data.frame(watershed_group_code = "BULK")),
    "missing column"
  )
})

# -- the bundled outlet table (no DB needed) ---------------------------------

test_that("frs_wsg_outlets ships one complete row per watershed group", {
  o <- frs_wsg_outlets()

  expect_setequal(
    names(o),
    c("watershed_group_code", "blue_line_key", "downstream_route_measure",
      "wscode_ltree", "localcode_ltree")
  )
  expect_gt(nrow(o), 200L)
  expect_false(any(duplicated(o$watershed_group_code)))
  expect_false(anyNA(o))
  expect_true(all(nzchar(o$wscode_ltree)))
  expect_true(all(nzchar(o$localcode_ltree)))
  expect_true(all(o$downstream_route_measure >= 0))
})

test_that("outlet selection avoids the sliver that broke public.wsg_outlet", {
  # MORR clips a 2-segment, 0 km, order-1 piece of the Bulkley-coded line
  # `400.431358`. Selecting on ltree depth alone picks that sliver and makes
  # the Bulkley appear to drain through the Morice. See link#227.
  o <- frs_wsg_outlets()

  expect_identical(
    o$wscode_ltree[o$watershed_group_code == "MORR"],
    "400.431358.585806"
  )
  expect_identical(
    o$wscode_ltree[o$watershed_group_code == "BULK"],
    "400.431358"
  )
  # Upper and Lower Fraser are separable only by measure — same blue line.
  fra <- o[o$watershed_group_code %in% c("LFRA", "UFRA"), ]
  expect_identical(length(unique(fra$blue_line_key)), 1L)
  expect_gt(
    fra$downstream_route_measure[fra$watershed_group_code == "UFRA"],
    fra$downstream_route_measure[fra$watershed_group_code == "LFRA"]
  )
})

# -- live DB tests (gated on PG_DB_SHARE) ------------------------------------

test_that("frs_wsg_drainage respects hydrology where FWA naming inverts it", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  # FWA carried the "Bulkley" name down through the confluence, so the Morice
  # — the larger flow — is filed as the tributary. The Morice drains through
  # the Bulkley; not the reverse.
  morr <- frs_wsg_drainage(conn, "MORR")
  expect_true("BULK" %in% morr)
  expect_gt(which(morr == "MORR"), which(morr == "BULK"))

  bulk <- frs_wsg_drainage(conn, "BULK")
  expect_false("MORR" %in% bulk)
})

test_that("frs_wsg_drainage orders same-stem groups by measure, not alphabet", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  # Every Fraser group carries wscode `100`; a single-ltree predicate cannot
  # order them and drops LFRA entirely. LFRA is the most downstream group in
  # the basin, so it must lead any Fraser closure.
  ufra <- frs_wsg_drainage(conn, "UFRA")
  expect_true("LFRA" %in% ufra)
  expect_identical(ufra[1], "LFRA")
  expect_identical(ufra[length(ufra)], "UFRA")
})

test_that("frs_wsg_drainage excludes tributaries and upstream neighbours", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  bulk <- frs_wsg_drainage(conn, "BULK")
  expect_true(all(c("LSKE", "KISP") %in% bulk))   # Skeena flows through both
  expect_false(any(c("MSKE", "USKE") %in% bulk))  # upstream of the confluence
  expect_false("LKEL" %in% bulk)                  # a separate tributary
})

test_that("frs_wsg_drainage includes the focal groups themselves", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  # fwa_downstream() is strict, so the focal set must be unioned in.
  res <- frs_wsg_drainage(conn, c("PARS", "BULK"))
  expect_true(all(c("PARS", "BULK") %in% res))
})

test_that("frs_wsg_drainage closure is invariant to focal input order", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  expect_identical(
    frs_wsg_drainage(conn, c("PARS", "BULK")),
    frs_wsg_drainage(conn, c("BULK", "PARS"))
  )
})

test_that("frs_wsg_drainage upper-cases focal codes internally", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  expect_identical(
    frs_wsg_drainage(conn, c("pars", "bulk")),
    frs_wsg_drainage(conn, c("PARS", "BULK"))
  )
})

test_that("frs_wsg_drainage warns on unmatched focal codes but returns valid ones", {
  skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  expect_warning(
    res <- frs_wsg_drainage(conn, c("BULK", "TYPO")),
    "TYPO"
  )
  expect_true(length(res) > 0L)
  expect_true("BULK" %in% res)
  expect_false("TYPO" %in% res)
})

test_that("frs_wsg_drainage errors when no focal codes match", {
  expect_error(
    suppressWarnings(frs_wsg_drainage(NULL, c("FAK1", "FAK2"))),
    "No drainage closure found"
  )
})
