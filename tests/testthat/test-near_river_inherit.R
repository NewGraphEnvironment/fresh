# Unit tests: near_river inherited from the thresholds CSV (#263), with a
# measure per stage (#262). Pure R, no DB.

nr_tbl <- "w.streams_near_river"
fx_dir <- test_path("fixtures", "predicates_0410")

# A thresholds CSV for CH (rear width 1.5 m, rear MAD 0.28) with the
# given near_river cells, and optionally BT (no MAD range).
nr_csv <- function(cells = list(), bt = FALSE) {
  base <- data.frame(species_code = "CH", spawn_gradient_max = 0.0449,
                     spawn_channel_width_min = 4, spawn_channel_width_max = 9999,
                     spawn_mad_min = 0.46, spawn_mad_max = 9999,
                     rear_gradient_max = 0.0549, rear_channel_width_min = 1.5,
                     rear_channel_width_max = 9999, rear_mad_min = 0.28,
                     rear_mad_max = 100, stringsAsFactors = FALSE)
  if (bt) {
    b <- base
    b$species_code <- "BT"
    b$spawn_mad_min <- b$spawn_mad_max <- b$rear_mad_min <- b$rear_mad_max <- NA
    base <- rbind(base, b)
  }
  for (k in names(cells)) base[[k]] <- cells[[k]]
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(base, tmp, row.names = FALSE)
  tmp
}

ch_rear_pair <- list(rear_river_channel_width_min = 20,
                     rear_river_discharge_min = 3,
                     rear_river_distance_max = 1000)

params_with <- function(cells = ch_rear_pair, rules = NULL, bt = FALSE) {
  csv <- nr_csv(cells, bt = bt)
  on.exit(unlink(csv))
  p <- frs_params(csv = csv, rules_yaml = NULL)
  if (!is.null(rules)) for (sp in names(rules)) p[[sp]]$rules <- rules[[sp]]
  p
}

sp_of <- function(params, sp = "CH") {
  list(species_code = sp, spawn_gradient_min = 0,
       spawn_gradient_max = params[[sp]]$spawn_gradient_max,
       params_sp = params[[sp]])
}

stream_rule <- list(edge_types_explicit = c(1000, 1100))

exists_sql <- function(measure, q, d = 1000) {
  sprintf(paste0(
    "EXISTS (SELECT 1 FROM w.streams_near_river n WHERE n.id_segment = s.id_segment ",
    "AND n.watershed_group_code = s.watershed_group_code ",
    "AND n.measure = '%s' AND n.threshold = %s AND n.distance_max = %s ",
    "AND n.dist_m <= %s)"), measure, q, d, d)
}

# -- frs_params ------------------------------------------------------------

test_that("frs_params stores each stage's pair beside ranges", {
  p <- params_with()
  expect_identical(p$CH$near_river$rear,
                   list(measure = "model", discharge_min = 3,
                        channel_width_min = 20, stream_order_min = NULL,
                        distance_max = 1000))
  expect_null(p$CH$near_river$spawn)
  # ranges is untouched: the pair is not a range.
  expect_identical(names(p$CH$ranges$rear),
                   c("gradient", "channel_width", "mad_m3s"))
  p2 <- params_with(list(spawn_river_measure = "stream_order",
                         spawn_river_stream_order_min = 5,
                         spawn_river_distance_max = 500))
  expect_identical(p2$CH$near_river$spawn$measure, "stream_order")
  expect_equal(p2$CH$near_river$spawn$stream_order_min, 5)
})

test_that("NA or absent near_river columns give no pair", {
  expect_null(params_with(list())$CH$near_river$rear)
  na_cells <- stats::setNames(as.list(rep(NA, 10)),
                              .frs_near_river_csv_cols())
  p <- params_with(na_cells)
  expect_null(p$CH$near_river$spawn)
  expect_null(p$CH$near_river$rear)
  bundled <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"), rules_yaml = NULL)
  expect_true(all(vapply(bundled, function(x) {
    is.null(x$near_river$spawn) && is.null(x$near_river$rear)
  }, logical(1))))
})

test_that("frs_params stops on half pairs and bad values", {
  bad <- list(
    no_d = list(rear_river_discharge_min = 3),
    no_min = list(rear_river_measure = "discharge",
                  rear_river_distance_max = 1000),
    model_one = list(rear_river_discharge_min = 3,
                     rear_river_distance_max = 1000),
    inf_d = list(rear_river_measure = "discharge",
                 rear_river_discharge_min = 3, rear_river_distance_max = Inf),
    zero_q = list(rear_river_measure = "discharge",
                  rear_river_discharge_min = 0, rear_river_distance_max = 10),
    measure = list(rear_river_measure = "width",
                   rear_river_channel_width_min = 3,
                   rear_river_distance_max = 10))
  msgs <- c(no_d = "rear_river_discharge_min is set but rear_river_distance_max is not",
            no_min = "'discharge', which needs rear_river_discharge_min",
            model_one = "'model', which needs rear_river_channel_width_min",
            inf_d = "rear_river_distance_max must be a finite number above zero",
            zero_q = "rear_river_discharge_min must be a finite number above zero",
            measure = "rear_river_measure must be one of")
  for (k in names(bad)) {
    expect_error(params_with(bad[[k]]), msgs[[k]], info = k)
    expect_error(params_with(bad[[k]]), "^CH rear", info = k)
  }
})

test_that("frs_params warns on an unknown near_river column", {
  expect_warning(params_with(c(ch_rear_pair, list(rear_river_width_min = 3))),
                 "unknown near_river column ignored: rear_river_width_min")
})

# -- the resolver ----------------------------------------------------------

test_that("an inheriting rule takes the pair; model resolves per size model", {
  p <- params_with(rules = list(CH = list(rear = list(stream_rule))))
  cw <- frs_habitat_predicates(sp_of(p), near_river_table = nr_tbl)$rear
  expect_identical(cw, paste0(
    "((s.edge_type IN (1000, 1100) AND s.gradient BETWEEN 0 AND 0.0549 AND ",
    "(s.channel_width BETWEEN 1.5 AND 9999 OR ",
    exists_sql("channel_width", 20), ")))"))
  mad <- frs_habitat_predicates(sp_of(p), model = "mad",
                                near_river_table = nr_tbl)$rear
  expect_identical(mad, paste0(
    "((s.edge_type IN (1000, 1100) AND s.gradient BETWEEN 0 AND 0.0549 AND ",
    "(s.mad_m3s BETWEEN 0.28 AND 100 OR ", exists_sql("discharge", 3), ")))"))
})

test_that("an explicit measure applies under both models", {
  for (m in c("discharge", "channel_width", "stream_order")) {
    cells <- list(rear_river_measure = m, rear_river_distance_max = 500)
    cells[[sprintf("rear_river_%s_min", m)]] <- 7
    p <- params_with(cells, rules = list(CH = list(rear = list(stream_rule))))
    for (model in c("cw", "mad")) {
      sql <- frs_habitat_predicates(sp_of(p), model = model,
                                    near_river_table = nr_tbl)$rear
      expect_match(sql, exists_sql(m, 7, 500), fixed = TRUE,
                   info = paste(m, model))
    }
  }
})

test_that("a rule's own mapping wins over the inherited pair", {
  rule <- c(stream_rule,
            list(near_river = list(discharge_min = 10, distance_max = 50)))
  p <- params_with(rules = list(CH = list(rear = list(rule))))
  sql <- frs_habitat_predicates(sp_of(p), near_river_table = nr_tbl)$rear
  expect_match(sql, exists_sql("discharge", 10, 50), fixed = TRUE)
  expect_false(grepl("channel_width'", sql))
})

test_that("near_river: false opts out of the inherited pair", {
  rule <- c(stream_rule, list(near_river = FALSE))
  p <- params_with(rules = list(CH = list(rear = list(rule))))
  sql <- frs_habitat_predicates(sp_of(p), near_river_table = nr_tbl)$rear
  expect_identical(sql, paste0(
    "((s.edge_type IN (1000, 1100) AND s.gradient BETWEEN 0 AND 0.0549 AND ",
    "s.channel_width BETWEEN 1.5 AND 9999))"))
  # and it needs no table
  expect_no_error(frs_habitat_predicates(sp_of(p)))
})

test_that("a thresholds: false rule inherits no pair; false there is a no-op", {
  carve <- list(edge_types_explicit = c(1050, 1150), thresholds = FALSE)
  for (rule in list(carve, c(carve, list(near_river = FALSE)))) {
    p <- params_with(rules = list(CH = list(rear = list(rule))))
    expect_identical(
      frs_habitat_predicates(sp_of(p))$rear, "((s.edge_type IN (1050, 1150)))")
  }
})

test_that("lake and wetland rules never inherit a pair", {
  for (wt in c("L", "W")) {
    rule <- list(waterbody_type = wt)
    p <- params_with(rules = list(CH = list(rear = list(rule))))
    expect_false(grepl("EXISTS",
      frs_habitat_predicates(sp_of(p), near_river_table = nr_tbl)$rear),
      info = wt)
  }
})

test_that("a rule with no size test inherits no pair (no tightening)", {
  # Under cw, a stage with no width range gives inheriting rules no size
  # test; an inherited pair would make "near a river" their only one.
  cells <- c(ch_rear_pair, list(rear_channel_width_min = NA,
                                rear_channel_width_max = NA))
  p <- params_with(cells, rules = list(CH = list(rear = list(stream_rule))))
  expect_identical(frs_habitat_predicates(sp_of(p))$rear,
    "((s.edge_type IN (1000, 1100) AND s.gradient BETWEEN 0 AND 0.0549))")
  expect_identical(nrow(.frs_near_river_specs(p, "CH", "cw")), 0L)
  # Under mad the same species has a MAD range, so the pair applies.
  expect_identical(nrow(.frs_near_river_specs(p, "CH", "mad")), 1L)
})

test_that("a mad species with no MAD range reads (FALSE OR EXISTS)", {
  cells <- list(rear_river_channel_width_min = c(20, 20),
                rear_river_discharge_min = c(3, 3),
                rear_river_distance_max = c(1000, 1000))
  p <- params_with(cells, rules = list(BT = list(rear = list(stream_rule))),
                   bt = TRUE)
  sql <- frs_habitat_predicates(sp_of(p, "BT"), model = "mad",
                                near_river_table = nr_tbl)$rear
  expect_match(sql, paste0("(FALSE OR ", exists_sql("discharge", 3), ")"),
               fixed = TRUE)
})

test_that("the river-polygon rule inherits under cw and under mad", {
  r_rule <- list(waterbody_type = "R", channel_width = c(0, 9999))
  p <- params_with(rules = list(CH = list(rear = list(r_rule))))
  cw <- frs_habitat_predicates(sp_of(p), near_river_table = nr_tbl)$rear
  expect_match(cw, paste0("(s.channel_width BETWEEN 0 AND 9999 OR ",
                          exists_sql("channel_width", 20), ")"), fixed = TRUE)
  mad <- frs_habitat_predicates(sp_of(p), model = "mad",
                                near_river_table = nr_tbl)$rear
  expect_match(mad, paste0("(s.mad_m3s BETWEEN 0.28 AND 100 OR ",
                           exists_sql("discharge", 3), ")"), fixed = TRUE)
  # A consumer that means "the river polygon is the river" opts it out.
  p$CH$rules$rear[[1]]$near_river <- FALSE
  expect_false(grepl("EXISTS", frs_habitat_predicates(sp_of(p))$rear))
})

# -- the walk's pairs equal the compiler's ---------------------------------

test_that(".frs_near_river_specs lists the effective pairs, from one resolver", {
  cells <- list(rear_river_channel_width_min = c(20, 20),
                rear_river_discharge_min = c(3, 3),
                rear_river_distance_max = c(1000, 1000))
  rules <- list(
    CH = list(rear = list(stream_rule)),                       # inherits
    BT = list(rear = list(c(stream_rule, list(                 # overrides
      near_river = list(stream_order_min = 5, distance_max = 200))))))
  p <- params_with(cells, rules = rules, bt = TRUE)
  p$CO <- p$CH
  p$CO$species_code <- "CO"
  p$CO$rules <- list(rear = list(c(stream_rule, list(near_river = FALSE))))
  specs <- .frs_near_river_specs(p, c("CH", "BT", "CO"), "cw")
  expect_identical(specs, data.frame(
    measure = c("channel_width", "stream_order"), threshold = c(20, 5),
    distance_max = c(1000, 200), stringsAsFactors = FALSE))
  # Each pair in the specs is the one the compiled predicate reads.
  for (sp in c("CH", "BT")) {
    sql <- frs_habitat_predicates(sp_of(p, sp), near_river_table = nr_tbl)$rear
    hit <- vapply(seq_len(nrow(specs)), function(i) {
      grepl(exists_sql(specs$measure[i], specs$threshold[i],
                       specs$distance_max[i]), sql, fixed = TRUE)
    }, logical(1))
    expect_identical(sum(hit), 1L, info = sp)
  }
  # Both models: model resolves to width under cw and discharge under mad.
  both <- .frs_near_river_specs(p, "CH", c("cw", "mad"))
  expect_identical(both$measure, c("channel_width", "discharge"))
})

test_that("params with rules but no near_river slot give the empty frame", {
  params <- list(CH = list(rules = list(rear = list(stream_rule))))
  none <- .frs_near_river_specs(params, "CH", c("cw", "mad"))
  expect_identical(nrow(none), 0L)
  expect_identical(names(none), c("measure", "threshold", "distance_max"))
})

# -- byte identity against fresh 0.41.0 ------------------------------------

test_that("NA or absent columns compile every fixture rule as 0.41.0 did", {
  frozen <- readRDS(file.path(fx_dir, "predicates.rds"))
  sets <- c(fresh = "fresh", link_default = "link_default",
            link_bcfishpass = "link_bcfishpass")
  na_cols <- .frs_near_river_csv_cols()
  for (with_cols in c(FALSE, TRUE)) {
    for (k in names(sets)) {
      csv <- file.path(fx_dir, sprintf("thresholds_%s.csv", sets[[k]]))
      if (with_cols) {
        x <- utils::read.csv(csv, stringsAsFactors = FALSE)
        for (cc in na_cols) x[[cc]] <- NA
        csv <- tempfile(fileext = ".csv")
        utils::write.csv(x, csv, row.names = FALSE)
      }
      params <- frs_params(csv = csv,
        rules_yaml = file.path(fx_dir, sprintf("rules_%s.yaml", sets[[k]])))
      for (sp in names(params)) {
        for (model in c("cw", "mad")) {
          key <- paste(k, sp, model, sep = "/")
          now <- frs_habitat_predicates(sp_of(params, sp), model = model,
            near_river_table = "w.streams_near_river")
          expect_identical(now, frozen[[key]],
                           info = paste(key, "with_cols", with_cols))
        }
      }
    }
  }
  expect_length(frozen, 66)
})
