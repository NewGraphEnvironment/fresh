# Live check for fresh#237: the W rule's wetland_ha_min now reaches the
# main `rear` predicate, not only `wetland_rearing`.
#
# Reads one WSG of link's persisted `fresh_default` (streams +
# streams_habitat_<sp>) from the local fwapg and compiles the species'
# full `rear` predicate from link's `default` config twice:
#   old - the W rear rule(s) with wetland_ha_min removed (what
#         .frs_rule_to_sql() compiled before #237)
#   new - the rules as written
# Both run on one checkout. Reports, on persisted `accessible` segments:
#   - segments / km the old predicate admits and the new one does not,
#     and how many wetland waterbodies (waterbody_key) they sit in
#   - the same intersected with persisted `rearing` (link applies
#     cluster_rearing and overrides after classification, so persisted
#     rearing is not exactly `accessible AND rear`)
#   - agreement of the old predicate with persisted rearing, as a check
#     that the reconstruction matches what link ran
#   - segments / km the new predicate still admits inside wetlands under
#     the floor, through rules other than the W rule (e.g. the 1050 /
#     1150 wetland-flow carve-out, or the stream rule). "Under the floor"
#     is the complement of the W rule's own test: a wetland key with no
#     polygon of area_ha >= floor (a key can have several polygons).
#     Reported for the new predicate (small_wetland_new_*), for
#     persisted rearing before the fix (small_wetland_persisted_*, which
#     still holds the dropped segments), and for persisted rearing the
#     new predicate keeps (small_wetland_kept_*). Split by edge type in
#     <wsg>_<sp>_edge.csv.
#
# Persisted rearing will lose at least dropped_persisted_n; link's
# cluster_rearing then reruns on the narrower set and can drop more.
#
# Usage (from the fresh repo root):
#   Rscript data-raw/rear_wetland_floor_check.R [WSG] [SPECIES]
#   Rscript data-raw/rear_wetland_floor_check.R NATR BT
# Writes data-raw/logs/rear_wetland_floor_237/<wsg>_<sp>.csv,
# <wsg>_<sp>_edge.csv and a .txt stamp.

pkgload::load_all(".", quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
wsg <- toupper(if (length(args) >= 1) args[[1]] else "NATR")
sp <- toupper(if (length(args) >= 2) args[[2]] else "BT")
stopifnot(grepl("^[A-Z]{4}$", wsg), grepl("^[A-Z]{2,3}$", sp))

cfg_dir <- path.expand("~/Projects/repo/link/inst/extdata/configs/default")
out_dir <- "data-raw/logs/rear_wetland_floor_237"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

params <- frs_params(csv = file.path(cfg_dir, "parameters_habitat_thresholds.csv"),
                     rules_yaml = file.path(cfg_dir, "rules.yaml"))
params_fresh <- utils::read.csv(file.path(cfg_dir, "parameters_fresh.csv"),
                                stringsAsFactors = FALSE)
params_method <- utils::read.csv(file.path(cfg_dir, "parameters_habitat_method.csv"),
                                 stringsAsFactors = FALSE)

# Same shape frs_habitat_classify() builds per species
ps <- params[[sp]]
fp <- params_fresh[params_fresh$species_code == sp, ]
if (is.null(ps) || nrow(fp) == 0) stop(sprintf("no %s params in %s", sp, cfg_dir))
sp_params <- list(
  species_code = sp,
  access_gradient = fp$access_gradient_max,
  spawn_gradient_max = ps$spawn_gradient_max,
  spawn_gradient_min = if (is.na(fp$spawn_gradient_min)) 0 else fp$spawn_gradient_min,
  params_sp = ps)

drop_w_floor <- function(rules) {
  lapply(rules, function(r) {
    if (identical(r[["waterbody_type"]], "W")) r[["wetland_ha_min"]] <- NULL
    r
  })
}
sp_params_old <- sp_params
sp_params_old$params_sp$rules$rear <- drop_w_floor(ps$rules$rear)

model <- .frs_habitat_models(wsg, params_method)[[wsg]]
pred_new <- frs_habitat_predicates(sp_params, model = model)$rear
pred_old <- frs_habitat_predicates(sp_params_old, model = model)$rear
if (identical(pred_new, pred_old)) {
  stop(sprintf("%s has no W rear rule with wetland_ha_min; nothing moves", sp))
}
w_floor <- .frs_rule_ha_min(.frs_find_waterbody_rule(ps$rules$rear, "W"))

conn <- frs_db_conn()
q <- function(sql) DBI::dbGetQuery(conn, sql)

hab_src <- sprintf("fresh_default.streams_habitat_%s", tolower(sp))
wsg_q <- .frs_quote_string(wsg)
if (model == "mad" && !"mad_m3s" %in% names(q(
    "SELECT * FROM fresh_default.streams LIMIT 0"))) {
  stop(sprintf("%s is on the mad model but fresh_default.streams has no mad_m3s", wsg))
}

# One CTE for both queries. small_wetland mirrors the W rule's test
# (any polygon of the key >= floor admits it) by complement.
x_cte <- sprintf(
  "WITH x AS (
     SELECT s.length_metre, s.waterbody_key, s.edge_type,
            h.rearing AS persisted,
            (EXISTS (SELECT 1 FROM whse_basemapping.fwa_wetlands_poly w
                     WHERE w.waterbody_key = s.waterbody_key)
             AND NOT EXISTS (
               SELECT 1 FROM whse_basemapping.fwa_wetlands_poly w
               WHERE w.waterbody_key = s.waterbody_key
                 AND w.area_ha >= %s)) AS small_wetland,
            COALESCE((%s), FALSE) AS old,
            COALESCE((%s), FALSE) AS new
     FROM fresh_default.streams s
     JOIN %s h ON h.id_segment = s.id_segment
              AND h.watershed_group_code = s.watershed_group_code
     WHERE s.watershed_group_code = %s AND h.accessible IS TRUE)",
  .frs_sql_num(w_floor), pred_old, pred_new, hab_src, wsg_q)

res <- q(paste(x_cte, "
   SELECT
     count(*) AS accessible_n,
     count(*) FILTER (WHERE old) AS old_n,
     count(*) FILTER (WHERE new) AS new_n,
     count(*) FILTER (WHERE new AND NOT old) AS gained_n,
     count(*) FILTER (WHERE old AND NOT new) AS dropped_n,
     round((coalesce(sum(length_metre) FILTER (WHERE old AND NOT new), 0)
            / 1000)::numeric, 1) AS dropped_km,
     count(DISTINCT waterbody_key) FILTER (WHERE old AND NOT new) AS dropped_wetlands,
     count(*) FILTER (WHERE old AND NOT new AND persisted) AS dropped_persisted_n,
     round((coalesce(sum(length_metre) FILTER (WHERE old AND NOT new AND persisted), 0)
            / 1000)::numeric, 1) AS dropped_persisted_km,
     count(*) FILTER (WHERE persisted) AS persisted_n,
     count(*) FILTER (WHERE old AND persisted) AS agree_both_n,
     count(*) FILTER (WHERE old AND NOT persisted) AS old_only_n,
     count(*) FILTER (WHERE persisted AND NOT old) AS persisted_only_n,
     count(*) FILTER (WHERE new AND small_wetland) AS small_wetland_new_n,
     round((coalesce(sum(length_metre) FILTER (WHERE new AND small_wetland), 0)
            / 1000)::numeric, 1) AS small_wetland_new_km,
     count(*) FILTER (WHERE persisted AND small_wetland) AS small_wetland_persisted_n,
     round((coalesce(sum(length_metre) FILTER (WHERE persisted AND small_wetland), 0)
            / 1000)::numeric, 1) AS small_wetland_persisted_km,
     count(*) FILTER (WHERE persisted AND new AND small_wetland) AS small_wetland_kept_n,
     round((coalesce(sum(length_metre) FILTER (WHERE persisted AND new AND small_wetland), 0)
            / 1000)::numeric, 1) AS small_wetland_kept_km
   FROM x"))
res <- cbind(data.frame(wsg = wsg, species = sp, model = model,
                        wetland_ha_min = w_floor), res)
print(t(res))

edge <- q(paste(x_cte, "
   SELECT edge_type,
     count(*) FILTER (WHERE new) AS new_n,
     round((coalesce(sum(length_metre) FILTER (WHERE new), 0) / 1000)::numeric, 1) AS new_km,
     count(*) FILTER (WHERE persisted) AS persisted_n,
     round((coalesce(sum(length_metre) FILTER (WHERE persisted), 0) / 1000)::numeric, 1)
       AS persisted_km,
     count(*) FILTER (WHERE persisted AND new) AS kept_n,
     round((coalesce(sum(length_metre) FILTER (WHERE persisted AND new), 0)
            / 1000)::numeric, 1) AS kept_km
   FROM x WHERE small_wetland AND (new OR persisted)
   GROUP BY edge_type ORDER BY edge_type"))
edge <- cbind(data.frame(wsg = rep(wsg, nrow(edge)), species = rep(sp, nrow(edge))), edge)
print(edge, row.names = FALSE)

stem <- file.path(out_dir, sprintf("%s_%s", tolower(wsg), tolower(sp)))
utils::write.csv(res, paste0(stem, ".csv"), row.names = FALSE, na = "")
utils::write.csv(edge, paste0(stem, "_edge.csv"), row.names = FALSE, na = "")
git_sha <- function(dir) {
  system2("git", c("-C", dir, "describe", "--always", "--dirty"), stdout = TRUE)
}
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("fresh: %s @ %s", utils::packageVersion("fresh"), git_sha(".")),
  sprintf("link config: %s @ %s", cfg_dir, git_sha(cfg_dir)),
  sprintf("db: %s", q("SELECT current_database() || ':' || inet_server_port()")[[1]]),
  sprintf("source: %s + fresh_default.streams, WSG %s, model %s", hab_src, wsg, model),
  sprintf("rear old: %s", gsub("\\s+", " ", pred_old)),
  sprintf("rear new: %s", gsub("\\s+", " ", pred_new))),
  paste0(stem, ".txt"))
DBI::dbDisconnect(conn)
