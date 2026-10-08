# Internal helpers — not exported

#' Get a configurable column name from options
#'
#' Reads `options(fresh.<name>)` with a default for FWA naming.
#' This is the foundation for #44 (configurable column names for
#' spyda compatibility). Set options once per session:
#'
#' ```
#' options(fresh.wscode_col = "wscode",
#'         fresh.localcode_col = "localcode")
#' ```
#'
#' @param name Character. Option suffix (e.g. `"wscode_col"`).
#' @return Character scalar.
#' @noRd
.frs_opt <- function(name) {
  defaults <- list(
    tbl_network = "whse_basemapping.fwa_stream_networks_sp",
    wscode_col = "wscode_ltree",
    localcode_col = "localcode_ltree",
    blk_col = "blue_line_key",
    measure_ds_col = "downstream_route_measure",
    measure_us_col = "upstream_route_measure",
    segment_id_col = "linear_feature_id"
  )
  getOption(paste0("fresh.", name), default = defaults[[name]])
}

#' Quote a string value for safe SQL interpolation
#'
#' Escapes single quotes by doubling them (SQL standard) and wraps in single
#' quotes. Prevents SQL injection for string literals without needing a DB
#' connection.
#'
#' @param x Character scalar.
#' @return Character scalar, e.g. `"'O''Brien'"`.
#' @noRd
.frs_quote_string <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}


#' Validate a SQL identifier (table or column name)
#'
#' Checks that the identifier matches a safe pattern: word characters, dots
#' (for schema-qualified names), and underscores. Stops with an informative
#' error if validation fails.
#'
#' @param x Character scalar.
#' @param label Character. Name used in error message (e.g. `"table"`).
#' @return `x` invisibly (called for side effect).
#' @noRd
.frs_validate_identifier <- function(x, label = "identifier") {
  if (identical(x, "*")) return(invisible(x))
  if (!grepl("^[A-Za-z_][A-Za-z0-9_.]*$", x)) {
    stop(sprintf("%s contains invalid characters: %s", label, x), call. = FALSE)
  }
  invisible(x)
}


#' Format a numeric value as a locale-safe SQL literal
#'
#' Uses `sprintf` which is not affected by `options(OutDec)`,
#' unlike `format()` or `formatC()`.
#'
#' Infinite values render as `'Infinity'::double precision` (or
#' `'-Infinity'`) — [frs_params()] fills a blank `*_max` threshold with
#' `Inf`, and a bare `Inf` would parse as a column name.
#'
#' @param x Numeric scalar.
#' @return Character string safe for SQL interpolation.
#' @noRd
.frs_sql_num <- function(x) {
  # yaml reads a mixed int/float sequence (`[0, 0.05]`) as a list
  x <- unlist(x)
  if (length(x) == 1L && is.infinite(x)) {
    return(if (x > 0) "'Infinity'::double precision" else
      "'-Infinity'::double precision")
  }
  sprintf("%.10g", x)
}


#' Format a gradient threshold as a `gradient_NNNN` label
#'
#' Generates the canonical 4-digit zero-padded basis-point label.
#' `0.05` becomes `"gradient_0500"`. `0.0549` becomes
#' `"gradient_0549"`.
#'
#' @param thr Numeric scalar in `[0, 1]`. Caller should validate
#'   first via [.frs_validate_gradient_thresholds()].
#' @return Character scalar.
#' @noRd
.frs_gradient_label <- function(thr) {
  sprintf("gradient_%04d", as.integer(round(thr * 10000)))
}


#' Validate a vector of gradient threshold values
#'
#' Errors if any value is:
#'   - not numeric or NA
#'   - outside `[0, 1]` (gradient is a fraction, not a percent)
#'   - cannot be represented exactly at basis-point precision
#'     (e.g. `0.05001` rounds to the same label as `0.05`)
#'   - duplicates another value's label after rounding
#'
#' Catches the silent failure mode where two distinct user-supplied
#' thresholds produce the same `gradient_NNNN` label and would
#' overwrite each other's barrier table.
#'
#' @param x Numeric vector of gradient thresholds (as fractions).
#' @param name Character. Argument name for error messages.
#' @return Invisible `x`. Errors on failure.
#' @noRd
.frs_validate_gradient_thresholds <- function(x, name = "thresholds") {
  if (!is.numeric(x)) {
    stop(sprintf("%s must be numeric", name), call. = FALSE)
  }
  if (length(x) == 0) {
    return(invisible(x))
  }
  if (any(is.na(x))) {
    stop(sprintf("%s contains NA values", name), call. = FALSE)
  }
  if (any(x < 0 | x > 1)) {
    bad <- x[x < 0 | x > 1]
    stop(sprintf(
      "%s values must be in [0, 1] (gradient as fraction, not percent). Got: %s",
      name, paste(bad, collapse = ", ")
    ), call. = FALSE)
  }

  # Precision check: must round-trip through 4-digit basis points
  rounded <- as.integer(round(x * 10000)) / 10000
  diffs <- abs(x - rounded)
  if (any(diffs > 1e-10)) {
    bad <- x[diffs > 1e-10]
    stop(sprintf(
      paste0(
        "%s values exceed basis-point precision (0.0001). ",
        "Each value must be representable as gradient_NNNN. Got: %s. ",
        "Round to 4 decimal places (e.g. 0.0549)."
      ),
      name, paste(bad, collapse = ", ")
    ), call. = FALSE)
  }

  # Label collision check: after rounding, no two values should map
  # to the same label. This is a defensive check — should be impossible
  # if precision check passed.
  labels_int <- as.integer(round(x * 10000))
  if (anyDuplicated(labels_int)) {
    dup_idx <- duplicated(labels_int) | duplicated(labels_int, fromLast = TRUE)
    bad <- unique(x[dup_idx])
    stop(sprintf(
      "%s values produce duplicate labels at basis-point precision: %s",
      name, paste(bad, collapse = ", ")
    ), call. = FALSE)
  }

  invisible(x)
}


#' Resolve waterbody type to FWA polygon table(s)
#'
#' Maps a single-character waterbody type code to the FWA polygon table(s)
#' that contain those features. `"L"` returns both natural lakes and
#' manmade waterbodies (reservoirs) — the FWA splits them by digitization
#' origin, not ecology.
#'
#' @param type Character. One of `"L"` (lakes + reservoirs), `"R"` (rivers),
#'   `"W"` (wetlands).
#' @return Character vector of schema-qualified table names.
#' @noRd
.frs_waterbody_tables <- function(type) {
  switch(type,
    "L" = c("whse_basemapping.fwa_lakes_poly",
            "whse_basemapping.fwa_manmade_waterbodies_poly"),
    "R" = "whse_basemapping.fwa_rivers_poly",
    "W" = "whse_basemapping.fwa_wetlands_poly",
    stop("Unknown waterbody_type: ", type))
}


#' Convert a single rule to a SQL AND predicate
#'
#' Translates one habitat rule (a list of predicates) into a
#' parenthesized SQL string joining the predicates with AND. When
#' `rule$thresholds` is `TRUE` (default) or unset, the species'
#' CSV-derived gradient/channel_width thresholds from `csv_thresholds`
#' are added to the AND chain. When `FALSE`, the rule stands alone
#' (the wetland-flow carve-out pattern).
#'
#' @param rule Named list with optional fields: `edge_types`,
#'   `edge_types_explicit`, `waterbody_type`, `lake_ha_min`,
#'   `wetland_ha_min`, `in_waterbody`, `thresholds`, `gradient`,
#'   `channel_width`, `mad`.
#'
#'   A `waterbody_type` rule's polygon area floor comes from the key of
#'   its type (see `.frs_rule_ha_min()`): `lake_ha_min` on `L`,
#'   `wetland_ha_min` on `W` (fresh#237).
#'
#'   `mad` is a `c(min, max)` mean annual discharge range (m3/s) that
#'   adds `s.mad_m3s BETWEEN min AND max`. It overrides an inherited
#'   `csv_thresholds$mad_m3s`, which is present only for watershed
#'   groups on the `mad` model (fresh#220). Segments with NULL `mad_m3s`
#'   (no discharge modelled) fail a `mad` rule.
#'
#'   `in_waterbody` is a logical that constrains the rule to segments
#'   inside or outside any waterbody polygon — `FALSE` adds
#'   `s.waterbody_key IS NULL` (the natural complement of the positive
#'   `waterbody_type` predicates; lets a stream-edge rule express "this
#'   classification only applies outside polygon footprints"); `TRUE`
#'   adds `s.waterbody_key IS NOT NULL`. Absent means no constraint
#'   (rule matches segments inside or outside polygons indifferently;
#'   pre-`in_waterbody` behaviour). Composes cleanly with
#'   `waterbody_type:` — the positive `waterbody_type` predicate already
#'   implies `IS NOT NULL`, so the two together are redundant rather
#'   than contradictory.
#' @param csv_thresholds Named list with `gradient = c(min, max)`,
#'   `channel_width = c(min, max)` and/or `mad_m3s = c(min, max)`. Any
#'   may be NULL. [frs_habitat_predicates()] passes `channel_width` under
#'   the `cw` model and `mad_m3s` under the `mad` model; `mad_m3s =
#'   c(NA, NA)` marks a species without MAD thresholds and makes
#'   inheriting rules match nothing.
#' @return Character. A parenthesized SQL predicate.
#'   Returns `"(TRUE)"` if the rule has no predicates and no
#'   thresholds to inherit (a wide-open rule).
#' @noRd
.frs_rule_to_sql <- function(rule, csv_thresholds = NULL) {
  parts <- character(0)

  # Use [[ ]] not $ to avoid partial matching: rule$edge_types
  # would match rule$edge_types_explicit because edge_types is a
  # prefix.
  inherit_thresholds <- is.null(rule[["thresholds"]]) ||
    isTRUE(rule[["thresholds"]])

  # Auto-skip gradient/cw inheritance for lake/wetland rules.
  # Lake and wetland flow lines are routing lines through waterbodies —
  # gradient and channel_width are meaningless on them. The relevant
  # threshold is the polygon area floor (lake_ha_min / wetland_ha_min),
  # not stream channel dimensions.
  # Rule-level explicit overrides (rule[["gradient"]], rule[["channel_width"]])
  # still apply if someone sets them deliberately.
  wb_type <- rule[["waterbody_type"]]
  if (!is.null(wb_type) && wb_type %in% c("L", "W")) {
    inherit_thresholds <- FALSE
  }

  if (!is.null(rule[["edge_types"]])) {
    et_categories <- rule[["edge_types"]]
    codes <- unlist(lapply(et_categories, function(et_category) {
      frs_edge_types(category = et_category)$edge_type
    }))
    if (length(codes) > 0) {
      parts <- c(parts, sprintf("s.edge_type IN (%s)",
        paste(codes, collapse = ", ")))
    }
  }

  if (!is.null(rule[["edge_types_explicit"]])) {
    codes <- as.integer(rule[["edge_types_explicit"]])
    parts <- c(parts, sprintf("s.edge_type IN (%s)",
      paste(codes, collapse = ", ")))
  }

  if (!is.null(rule[["in_waterbody"]])) {
    in_wb <- rule[["in_waterbody"]]
    if (!is.logical(in_wb) || length(in_wb) != 1L || is.na(in_wb)) {
      stop("rule[['in_waterbody']] must be a single TRUE or FALSE",
           call. = FALSE)
    }
    parts <- c(parts, if (in_wb) {
      "s.waterbody_key IS NOT NULL"
    } else {
      "s.waterbody_key IS NULL"
    })
  }

  if (!is.null(rule[["waterbody_type"]])) {
    wb_tables <- .frs_waterbody_tables(rule[["waterbody_type"]])
    ha_min <- .frs_rule_ha_min(rule)
    area_clause <- if (is.null(ha_min)) "" else
      sprintf(" WHERE area_ha >= %s", .frs_sql_num(ha_min))
    wb_sql <- paste(vapply(wb_tables, function(wt) {
      sprintf("SELECT waterbody_key FROM %s%s", wt, area_clause)
    }, character(1)), collapse = " UNION ALL ")
    parts <- c(parts, sprintf("s.waterbody_key IN (%s)", wb_sql))
  }

  # Gradient: rule-level override wins, then CSV inheritance fills gap.
  # A rule with gradient: [0, 9999] explicitly overrides the CSV value.
  # A rule without gradient inherits from CSV when thresholds: true.
  if (!is.null(rule[["gradient"]])) {
    g <- rule[["gradient"]]
    parts <- c(parts, sprintf(
      "s.gradient BETWEEN %s AND %s",
      .frs_sql_num(g[1]), .frs_sql_num(g[2])))
  } else if (inherit_thresholds && !is.null(csv_thresholds) &&
             !is.null(csv_thresholds$gradient)) {
    g <- csv_thresholds$gradient
    parts <- c(parts, sprintf(
      "s.gradient BETWEEN %s AND %s",
      .frs_sql_num(g[1]), .frs_sql_num(g[2])))
  }

  # Channel width: same override-then-inherit pattern.
  if (!is.null(rule[["channel_width"]])) {
    cw <- rule[["channel_width"]]
    parts <- c(parts, sprintf(
      "s.channel_width BETWEEN %s AND %s",
      .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
  } else if (inherit_thresholds && !is.null(csv_thresholds) &&
             !is.null(csv_thresholds$channel_width)) {
    cw <- csv_thresholds$channel_width
    parts <- c(parts, sprintf(
      "s.channel_width BETWEEN %s AND %s",
      .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
  }

  # MAD: same override-then-inherit pattern. csv_thresholds only carries
  # mad_m3s under the per-WSG "mad" model (fresh#220). An NA range means
  # the species has no MAD thresholds: nothing qualifies (bcfishpass
  # parity — `mad > NULL` is never true).
  if (!is.null(rule[["mad"]])) {
    mad <- unlist(rule[["mad"]])
    parts <- c(parts, sprintf(
      "s.mad_m3s BETWEEN %s AND %s",
      .frs_sql_num(mad[1]), .frs_sql_num(mad[2])))
  } else if (inherit_thresholds && !is.null(csv_thresholds) &&
             !is.null(csv_thresholds$mad_m3s)) {
    mad <- csv_thresholds$mad_m3s
    parts <- c(parts, if (anyNA(mad)) "FALSE" else sprintf(
      "s.mad_m3s BETWEEN %s AND %s",
      .frs_sql_num(mad[1]), .frs_sql_num(mad[2])))
  }

  if (length(parts) == 0) return("(TRUE)")
  paste0("(", paste(parts, collapse = " AND "), ")")
}


#' Convert a list of rules to a SQL OR predicate
#'
#' Joins individual rule SQL predicates with OR and parenthesizes the
#' result. An empty rule list returns `"FALSE"` (no segments qualify).
#'
#' @param rules List of rule lists. Empty list → `"FALSE"`.
#' @param csv_thresholds Same as for [.frs_rule_to_sql()].
#' @return Character. A parenthesized SQL predicate, or `"FALSE"`.
#' @noRd
.frs_rules_to_sql <- function(rules, csv_thresholds = NULL) {
  if (is.null(rules) || length(rules) == 0) {
    return("FALSE")
  }
  rule_sqls <- vapply(rules, .frs_rule_to_sql, character(1),
                      csv_thresholds = csv_thresholds)
  paste0("(", paste(rule_sqls, collapse = " OR "), ")")
}


#' Polygon area floor of a waterbody-type rule
#'
#' Returns the area floor (ha) a `waterbody_type` rule declares, read
#' from the key of its type: `lake_ha_min` for `L`, `wetland_ha_min` for
#' `W`. The rules loader allows each key only on its type, so this is
#' the one place that pairs them (fresh#237). Every reader of the floor
#' (the main rule compiler, the lake / wetland bucket predicates, the
#' waterbody-connected spawning pass) goes through it.
#'
#' @param rule A single rule (named list), or `NULL`.
#' @return Numeric scalar, or `NULL` when the rule has no type with a
#'   floor (`R`, none), no floor under its type's key, or an `NA` floor.
#' @noRd
.frs_rule_ha_min <- function(rule) {
  keys <- c(L = "lake_ha_min", W = "wetland_ha_min")
  wt <- rule[["waterbody_type"]]
  if (!is.character(wt) || length(wt) != 1L || !wt %in% names(keys)) {
    return(NULL)
  }
  ha_min <- rule[[keys[[wt]]]]
  if (is.null(ha_min) || is.na(ha_min)) return(NULL)
  ha_min
}


#' Find a waterbody-type rule in a species' rear rules list
#'
#' Returns the first rear rule entry whose `waterbody_type` matches
#' `wb_code` (typically `"L"` for lakes or `"W"` for wetlands), or
#' `NULL` if the species has no such rule. Used by
#' [frs_habitat_classify()] to gate `lake_rearing` / `wetland_rearing`
#' flags on the rules-YAML declaration rather than classifying by
#' channel-width alone.
#'
#' @param rules The `rear:` rules list from a species' entry in the
#'   parsed rules YAML (e.g. `params_sp$rules$rear`).
#' @param wb_code Character. One of `"L"` (lake), `"W"` (wetland).
#' @return The matching rule (a named list) or `NULL` if none.
#' @noRd
.frs_find_waterbody_rule <- function(rules, wb_code) {
  if (is.null(rules) || length(rules) == 0) return(NULL)
  for (r in rules) {
    wt <- r[["waterbody_type"]]
    if (!is.null(wt) && identical(wt, wb_code)) return(r)
  }
  NULL
}


#' Add id_segment column to a working table
#'
#' Assigns a unique integer ID to every row. Uses `linear_feature_id`
#' as the starting value (so original FWA segments keep their ID),
#' then generates new IDs for any rows added later by
#' [frs_break_apply()].
#'
#' @param conn DBI connection.
#' @param table Schema-qualified table name.
#' @noRd
.frs_add_id_segment <- function(conn, table) {
  if (!inherits(conn, "DBIConnection")) return(invisible(NULL))
  .frs_db_execute(conn, sprintf(
    "ALTER TABLE %s ADD COLUMN IF NOT EXISTS id_segment integer", table))
  .frs_db_execute(conn, sprintf(
    "UPDATE %s SET id_segment = linear_feature_id
     WHERE id_segment IS NULL", table))
}


#' Add indexes to a working table based on available columns
#'
#' Checks which index-worthy columns exist and creates appropriate indexes.
#' Runs ANALYZE after indexing for up-to-date statistics.
#'
#' @param conn DBI connection.
#' @param table Schema-qualified table name.
#' @noRd
.frs_index_working <- function(conn, table) {
  .frs_validate_identifier(table, "table")

  # Skip indexing for non-DB connections (e.g. mock connections in tests)
  if (!inherits(conn, "DBIConnection")) return(invisible(NULL))

  # Get columns in this table
  parts <- strsplit(table, "\\.")[[1]]
  schema <- if (length(parts) == 2) parts[1] else "public"
  tbl <- parts[length(parts)]

  cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s",
    .frs_quote_string(schema), .frs_quote_string(tbl)
  ))$column_name

  # Build index statements based on available columns.
  # Uses IF NOT EXISTS so callers can index the same table multiple times

  # safely (e.g. frs_network_segment indexes, then frs_habitat_classify
  # re-indexes the same inputs).
  idx <- character(0)

  if ("blue_line_key" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_blk_idx ON %s (blue_line_key)",
      tbl, table))
  }
  if (all(c("blue_line_key", "downstream_route_measure") %in% cols)) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_blk_drm_idx ON %s (blue_line_key, downstream_route_measure)",
      tbl, table))
  }

  if ("wscode_ltree" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_wscode_gist_idx ON %s USING gist (wscode_ltree)",
      tbl, table))
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_wscode_btree_idx ON %s USING btree (wscode_ltree)",
      tbl, table))
  }
  if ("localcode_ltree" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_localcode_gist_idx ON %s USING gist (localcode_ltree)",
      tbl, table))
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_localcode_btree_idx ON %s USING btree (localcode_ltree)",
      tbl, table))
  }
  if ("linear_feature_id" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_lfid_idx ON %s (linear_feature_id)",
      tbl, table))
  }
  if ("watershed_group_code" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_wsg_idx ON %s (watershed_group_code)",
      tbl, table))
  }
  if ("label" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_label_idx ON %s (label)",
      tbl, table))
    if ("blue_line_key" %in% cols) {
      idx <- c(idx, sprintf(
        "CREATE INDEX IF NOT EXISTS %s_label_blk_idx ON %s (label, blue_line_key)",
        tbl, table))
    }
  }
  if ("id_segment" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_id_segment_idx ON %s (id_segment)",
      tbl, table))
  }
  if ("species_code" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_species_code_idx ON %s (species_code)",
      tbl, table))
  }

  for (sql in idx) {
    .frs_db_execute(conn, sql)
  }

  .frs_db_execute(conn, sprintf("ANALYZE %s", table))
}


#' Build a SQL WHERE clause from common filter parameters
#'
#' @param watershed_group_code Character or NULL.
#' @param blue_line_key Integer or NULL.
#' @param bbox Numeric length-4 or NULL (xmin, ymin, xmax, ymax in EPSG:3005).
#' @param extra Character vector of additional SQL predicates.
#'
#' @return Character string starting with " WHERE ..." or empty string.
#' @noRd
.frs_build_where <- function(
    watershed_group_code = NULL,
    blue_line_key = NULL,
    bbox = NULL,
    extra = NULL
) {
  clauses <- character(0)

  if (!is.null(watershed_group_code)) {
    clauses <- c(
      clauses,
      paste0("watershed_group_code = ", .frs_quote_string(watershed_group_code))
    )
  }

  if (!is.null(blue_line_key)) {
    clauses <- c(clauses, paste0("blue_line_key = ", as.integer(blue_line_key)))
  }

  if (!is.null(bbox)) {
    stopifnot(length(bbox) == 4)
    clauses <- c(
      clauses,
      sprintf(
        "geom && ST_MakeEnvelope(%s, %s, %s, %s, 3005)",
        bbox[1], bbox[2], bbox[3], bbox[4]
      )
    )
  }

  if (!is.null(extra)) {
    clauses <- c(clauses, extra)
  }

  if (length(clauses) == 0) return("")

  paste0(" WHERE ", paste(clauses, collapse = " AND "))
}


#' Stream filtering guards to exclude invalid FWA segments
#'
#' Returns SQL predicates that filter out placeholder streams (999 wscode)
#' and unmapped tributaries (NULL localcode). These are no-ops in network
#' traversal (fwa_upstream/fwa_downstream never return them) but matter
#' for direct table queries (frs_stream_fetch, frs_point_snap KNN).
#'
#' Subsurface flow (edge_type 1425 — underground conduits) and network
#' connectors (edge_type 1410 — wetland connectivity) are NOT filtered by
#' default because these are real network connectivity. Use
#' [.frs_snap_guards()] for snap-specific filtering that excludes
#' subsurface segments (1425 only by default).
#'
#' @param alias Character. Table alias prefix. Default `"s"`.
#' @param wscode_col Character. Watershed code column name. Default
#'   `"wscode_ltree"`.
#' @param localcode_col Character. Local code column name. Default
#'   `"localcode_ltree"`.
#' @return Character vector of SQL predicates.
#' @noRd
.frs_stream_guards <- function(alias = "s", wscode_col = "wscode_ltree",
                               localcode_col = "localcode_ltree") {
  prefix <- if (nzchar(alias)) paste0(alias, ".") else ""
  c(
    paste0(prefix, localcode_col, " IS NOT NULL"),
    paste0("NOT ", prefix, wscode_col, " <@ '999'")
  )
}


#' Snap-specific filtering guards
#'
#' Like [.frs_stream_guards()] but also excludes subsurface flow
#' (edge_type 1425 — underground conduits). Used by the KNN snap
#' path where snapping to a culvert is not useful.
#'
#' Note: edge_type 1410 (network connector) is NOT excluded — these are
#' real wetland connectivity (204K segments in wetlands). See
#' NewGraphEnvironment/bcfishpass#8 for discussion.
#'
#' @inheritParams .frs_stream_guards
#' @param exclude_edge_types Integer vector or `NULL`. Edge types to exclude
#'   from snap candidates. Default `1425` (subsurface flow). Set to `NULL`
#'   to snap to all edge types.
#' @return Character vector of SQL predicates.
#' @noRd
.frs_snap_guards <- function(alias = "s", wscode_col = "wscode_ltree",
                             localcode_col = "localcode_ltree",
                             exclude_edge_types = 1425L) {
  guards <- .frs_stream_guards(alias, wscode_col, localcode_col)

  if (!is.null(exclude_edge_types) && length(exclude_edge_types) > 0) {
    prefix <- if (nzchar(alias)) paste0(alias, ".") else ""
    codes <- paste(as.integer(exclude_edge_types), collapse = ", ")
    guards <- c(guards, paste0(prefix, "edge_type NOT IN (", codes, ")"))
  }

  guards
}


#' Check if table is the FWA base stream network table
#' @noRd
.is_fwa_stream_table <- function(table) {
  grepl("fwa_stream_networks_sp", tolower(table))
}


#' Check if a DB connection to fwapg is available
#'
#' Attempts to connect and run a trivial query. Returns `TRUE` on success,
#' `FALSE` on any failure. Used by integration tests to skip gracefully
#' when no tunnel/DB is available.
#'
#' @return Logical scalar.
#' @noRd
.frs_db_available <- function() {
  tryCatch({
    conn <- frs_db_conn()
    on.exit(DBI::dbDisconnect(conn))
    DBI::dbGetQuery(conn, "SELECT 1")
    TRUE
  }, error = function(e) FALSE)
}


#' Resolve an AOI specification to a SQL WHERE predicate
#'
#' Normalizes any AOI input into a SQL predicate string that can be appended
#' to a WHERE clause. Handles sf polygons, table+id lookups, character
#' shortcuts (via partition options), blk+measure watershed delineation,
#' and NULL (no filter).
#'
#' @param aoi AOI specification. One of:
#'   - `NULL` — no spatial filter
#'   - Character vector — shortcut for partition table lookup using
#'     `getOption("fresh.partition_table")` and
#'     `getOption("fresh.partition_col")`
#'   - `sf`/`sfc` polygon — spatial intersection
#'   - Named list with `table` and `id` (and optionally `id_col`) — lookup
#'     polygon from a pg table
#'   - Named list with `blk` and `measure` — delineate watershed via
#'     `fwa_watershedatmeasure()`
#' @param conn A [DBI::DBIConnection-class] object. Required for sf upload,
#'   table lookup, and blk+measure delineation. Not needed for character
#'   or NULL inputs.
#' @param geom_col Character. Name of the geometry column in the target
#'   table. Default `"geom"`.
#' @param alias Character. Table alias prefix for the predicate. Default
#'   `""` (no prefix).
#'
#' @return Character scalar. A SQL predicate (without leading WHERE/AND),
#'   or empty string `""` for NULL aoi.
#' @noRd
.frs_resolve_aoi <- function(aoi, conn = NULL, geom_col = "geom",
                             alias = "") {
  if (is.null(aoi)) return("")

  prefix <- if (nzchar(alias)) paste0(alias, ".") else ""

  # Character vector — partition table shortcut

  if (is.character(aoi)) {
    tbl <- getOption("fresh.partition_table",
                     "whse_basemapping.fwa_watershed_groups_poly")
    col <- getOption("fresh.partition_col", "watershed_group_code")
    .frs_validate_identifier(tbl, "partition table")
    .frs_validate_identifier(col, "partition column")
    quoted <- paste(vapply(aoi, .frs_quote_string, character(1)),
                    collapse = ", ")
    return(sprintf(
      "%s%s && (SELECT ST_Union(geom) FROM %s WHERE %s IN (%s))",
      prefix, geom_col, tbl, col, quoted
    ))
  }

  # sf/sfc polygon — spatial intersection
  if (inherits(aoi, c("sf", "sfc"))) {
    # Transform to BC Albers (3005) to match DB geometry
    aoi_3005 <- sf::st_transform(aoi, 3005)
    wkt <- sf::st_as_text(sf::st_union(sf::st_geometry(aoi_3005)))
    return(sprintf(
      "ST_Intersects(%s%s, ST_GeomFromText('%s', 3005))",
      prefix, geom_col, wkt
    ))
  }

  # Named list — table+id lookup or blk+measure delineation
  if (is.list(aoi)) {
    # blk + measure → watershed delineation
    if (!is.null(aoi$blk) && !is.null(aoi$measure)) {
      blk <- as.integer(aoi$blk)
      measure <- as.numeric(aoi$measure)
      return(sprintf(
        "ST_Intersects(%s%s, (SELECT ST_Union(geom) FROM whse_basemapping.fwa_watershedatmeasure(%d, %s)))",
        prefix, geom_col, blk, measure
      ))
    }

    # table + id → polygon lookup
    if (!is.null(aoi$table) && !is.null(aoi$id)) {
      .frs_validate_identifier(aoi$table, "AOI table")
      id_col <- if (!is.null(aoi$id_col)) aoi$id_col else "id"
      .frs_validate_identifier(id_col, "AOI id column")
      id_val <- if (is.character(aoi$id)) {
        .frs_quote_string(aoi$id)
      } else {
        as.character(aoi$id)
      }
      return(sprintf(
        "ST_Intersects(%s%s, (SELECT ST_Union(geom) FROM %s WHERE %s = %s))",
        prefix, geom_col, aoi$table, id_col, id_val
      ))
    }

    stop("list aoi must have 'blk'+'measure' or 'table'+'id'", call. = FALSE)
  }

  stop(
    sprintf("aoi must be NULL, character, sf, or list. Got: %s", class(aoi)[1]),
    call. = FALSE
  )
}


#' Execute a DDL/DML statement (CREATE, UPDATE, INSERT, DROP, ALTER)
#'
#' Complement to [frs_db_query()] which only handles SELECT via
#' [sf::st_read()]. This wraps [DBI::dbExecute()] for write operations.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param sql Character. SQL statement to execute.
#' @return The number of rows affected (invisibly).
#' @noRd
.frs_db_execute <- function(conn, sql) {
  DBI::dbExecute(conn, sql)
}


#' Write a data frame to a uniquely named temporary table
#'
#' Temporary tables live for the session of `conn`, so each mirai worker
#' gets its own. They do not survive a pooler that hands each statement
#' a different backend (pgbouncer transaction pooling). The caller drops
#' the table when done.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param df A plain data frame (no geometry column).
#' @return Character. The temporary table name.
#' @noRd
.frs_db_write_temp <- function(conn, df) {
  # tempfile() draws its suffix without touching the R RNG
  name <- gsub("[^a-z0-9_]", "", basename(tempfile("frs_tmp_")))
  DBI::dbWriteTable(conn, name, df, temporary = TRUE)
  name
}


#' Get column names for a schema-qualified table
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param table Character. Schema-qualified table name.
#' @param exclude_generated Logical. If `TRUE`, exclude PostgreSQL
#'   `GENERATED ALWAYS` columns. Default `FALSE`.
#' @return Character vector of column names.
#' @noRd
.frs_table_columns <- function(conn, table, exclude_generated = FALSE) {
  tbl_parts <- strsplit(table, "\\.")[[1]]
  tbl_schema <- if (length(tbl_parts) == 2) tbl_parts[1] else "public"
  tbl_name <- tbl_parts[length(tbl_parts)]
  gen_filter <- if (exclude_generated) " AND is_generated = 'NEVER'" else ""
  sql <- sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = '%s' AND table_name = '%s'%s
     ORDER BY ordinal_position",
    tbl_schema, tbl_name, gen_filter
  )
  DBI::dbGetQuery(conn, sql)$column_name
}


#' Align a persist target's columns with its source before INSERT
#'
#' Persisted tables (e.g. `to_streams` in [frs_habitat()]) are created once
#' with `CREATE TABLE IF NOT EXISTS ... AS SELECT * ... LIMIT 0` and then
#' appended to per run. When the source gains a column (e.g. `mad_m3s`,
#' fresh#114), a positional `INSERT ... SELECT *` into a target built by an
#' older run fails — after the partition DELETE has already run. This adds
#' any source columns the target lacks (same type) and returns the source
#' column names, for use as an explicit `INSERT (cols) SELECT cols` list.
#' Errors if a column both tables share has a different type.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param to Character. Schema-qualified persist target (must exist).
#' @param from Character. Schema-qualified source table.
#' @return Character scalar: the source column names, quoted and
#'   comma-joined, ready to splice into SQL.
#' @noRd
.frs_persist_columns <- function(conn, to, from) {
  .frs_validate_identifier(to, "persist target")
  .frs_validate_identifier(from, "persist source")
  col_types <- function(tbl) {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT a.attname AS col,
              format_type(a.atttypid, a.atttypmod) AS type
       FROM pg_attribute a
       WHERE a.attrelid = %s::regclass
         AND a.attnum > 0 AND NOT a.attisdropped
       ORDER BY a.attnum", .frs_quote_string(tbl)))
  }
  cols_from <- col_types(from)
  types_to <- col_types(to)
  # A shared column with a different type would be silently cast by the
  # INSERT (e.g. double into text) — fail before any ALTER or DELETE.
  shared <- merge(cols_from, types_to, by = "col",
                  suffixes = c("_from", "_to"))
  bad <- shared[shared$type_from != shared$type_to, , drop = FALSE]
  if (nrow(bad) > 0) {
    stop(sprintf(
      "%s column type differs from %s: %s. Drop or migrate %s and re-run.",
      to, from,
      paste0(bad$col, " (", bad$type_to, " vs ", bad$type_from, ")",
             collapse = ", "),
      to), call. = FALSE)
  }
  cols_to <- types_to$col
  cols_missing <- cols_from[!cols_from$col %in% cols_to, , drop = FALSE]
  for (i in seq_len(nrow(cols_missing))) {
    .frs_db_execute(conn, sprintf(
      "ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s %s",
      to, DBI::dbQuoteIdentifier(conn, cols_missing$col[i]),
      cols_missing$type[i]))
  }
  paste(DBI::dbQuoteIdentifier(conn, cols_from$col), collapse = ", ")
}


#' Drop a test table from the working schema
#'
#' Convenience wrapper for integration test teardown.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param table Character. Schema-qualified table name (e.g.
#'   `"working.test_extract"`).
#' @return NULL invisibly.
#' @noRd
.frs_test_drop <- function(conn, table) {
  .frs_validate_identifier(table, "test table")
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", table))
  invisible(NULL)
}


#' Transform sf result to a target CRS
#'
#' @param x An `sf` object.
#' @param crs Target CRS (integer EPSG code, character proj4/WKT, or
#'   `sf::st_crs()` object). `NULL` returns `x` unchanged.
#' @return `x`, optionally transformed.
#' @noRd
.frs_transform <- function(x, crs = NULL) {
  if (is.null(crs)) return(x)
  sf::st_transform(x, crs)
}


#' Resolve the habitat size model (cw / mad) per watershed group
#'
#' Looks up each watershed group in a bcfishpass-style
#' `parameters_habitat_method.csv` table. Groups missing from the table
#' (or `NA`, e.g. custom-network rows) default to `"cw"` (fresh#220).
#'
#' @param wsg_codes Character. Watershed group codes to resolve.
#' @param params_method Data frame with `watershed_group_code` and
#'   `model` columns. `model` must be `"cw"` or `"mad"`.
#' @return Named character vector of models, names = `wsg_codes`.
#' @noRd
.frs_habitat_models <- function(wsg_codes, params_method) {
  if (!is.data.frame(params_method) ||
      !all(c("watershed_group_code", "model") %in% names(params_method))) {
    stop("params_method must be a data frame with columns ",
         "watershed_group_code and model", call. = FALSE)
  }
  pm_model <- as.character(params_method$model)
  bad <- setdiff(unique(pm_model), c("cw", "mad"))
  if (length(bad) > 0) {
    stop(sprintf('params_method model must be "cw" or "mad", got: %s',
                 paste(bad, collapse = ", ")), call. = FALSE)
  }
  pm_wsg <- as.character(params_method$watershed_group_code)
  dup <- unique(pm_wsg[duplicated(pm_wsg)])
  if (length(dup) > 0) {
    stop(sprintf("params_method has duplicate watershed_group_code: %s",
                 paste(dup, collapse = ", ")), call. = FALSE)
  }
  wsg_codes <- as.character(wsg_codes)
  # incomparables: an NA key in params_method must not claim NULL-group rows
  models <- pm_model[match(wsg_codes, pm_wsg, incomparables = NA)]
  models[is.na(models)] <- "cw"
  stats::setNames(models, wsg_codes)
}


#' Combine per-model habitat predicates on watershed_group_code
#'
#' When every watershed group resolves to one model, returns that
#' model's predicates untouched (cw-only SQL is unchanged). When models
#' are mixed, each predicate becomes
#' `CASE WHEN s.watershed_group_code IN (<mad groups>) THEN (<mad>) ELSE
#' (<cw>) END`, so rows outside the listed groups (including NULL
#' `watershed_group_code`) use cw (fresh#220).
#'
#' @param preds_by_model Named list (`cw`, `mad`) of predicate lists from
#'   [frs_habitat_predicates()]. Entries for unused models may be NULL.
#' @param models Named character vector from [.frs_habitat_models()].
#' @return A predicate list with the same names as the inputs.
#' @noRd
.frs_preds_by_model <- function(preds_by_model, models) {
  wsg_mad <- names(models)[models == "mad"]
  if (length(wsg_mad) == 0) return(preds_by_model$cw)
  if (length(wsg_mad) == length(models)) return(preds_by_model$mad)
  in_sql <- paste(vapply(wsg_mad, .frs_quote_string, character(1)),
                  collapse = ", ")
  cw <- preds_by_model$cw
  mad <- preds_by_model$mad
  stats::setNames(lapply(names(cw), function(k) {
    sprintf(
      "CASE WHEN s.watershed_group_code IN (%s) THEN (%s) ELSE (%s) END",
      in_sql, mad[[k]], cw[[k]])
  }), names(cw))
}
