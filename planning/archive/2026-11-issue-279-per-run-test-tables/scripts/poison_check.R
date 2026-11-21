# Poison check for #279 (verification, not data): create | verify [cleanup] | leftover.
# Run from the repo root: Rscript <this> create <state.rds>; ... verify <state.rds> cleanup
# Poison check for #279. mode = create | verify | list.
# Names: every working.<name> literal in main's test files (git show origin/main), plus the
# frs_habitat()-derived names for each label main's live tests pass.
args <- commandArgs(TRUE); mode <- args[1]; out <- args[2]
pkgload::load_all(quiet = TRUE)
files <- system("git ls-tree --name-only origin/main tests/testthat/", intern = TRUE)
files <- grep("\\.R$", files, value = TRUE)
txt <- unlist(lapply(files, function(f) system2("git", c("show", paste0("origin/main:", f)), stdout = TRUE)))
lit <- unique(tolower(sub("^working\\.", "", regmatches(txt, gregexpr("working\\.[A-Za-z_][A-Za-z0-9_]*", txt)) |> unlist())))
lit <- lit[!grepl("_$", lit)]   # prefixes like streams_ / rt_streams_ are expanded below
labels <- c("brktest_a","brktest_b","brktest_d","brktest_e","brktest_110","brktest_110b",
            "b143","n143","p282a","p282b","p293a","p293b","p293c",
            "rt_sk","rt_co","rt_co_off","rt_pk","rt_off")
derived <- c(paste0("streams_", labels), paste0("barriers_", labels, "_gradient"),
             paste0("rt_streams_", labels), paste0("rt_habitat_", labels))
names_all <- sort(unique(c(lit, derived)))
conn <- frs_db_conn(); on.exit(DBI::dbDisconnect(conn))
oids <- function() {
  r <- DBI::dbGetQuery(conn, "SELECT c.relname, c.oid::bigint AS oid FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'working'")
  setNames(r$oid, r$relname)
}
if (mode == "create") {
  have <- oids()
  made <- setdiff(names_all, names(have))
  for (n in made) DBI::dbExecute(conn, sprintf("CREATE TABLE working.%s (poison_279 integer)", n))
  now <- oids()
  saveRDS(list(names = names_all, made = made, oid = now[names_all]), out)
  cat("names:", length(names_all), " poison created:", length(made), " pre-existing:", length(names_all) - length(made), "\n")
} else if (mode == "verify") {
  st <- readRDS(out); now <- oids()
  gone <- st$names[is.na(now[st$names])]
  changed <- st$names[!is.na(now[st$names]) & now[st$names] != st$oid[st$names]]
  cat("checked:", length(st$names), " destroyed:", length(gone), " recreated (oid changed):", length(changed), "\n")
  if (length(gone)) cat("destroyed:", head(gone, 20), "\n")
  if (length(changed)) cat("changed:", head(changed, 20), "\n")
  if (length(args) > 2 && args[3] == "cleanup") {
    for (n in intersect(st$made, names(now))) DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS working.%s", n))
    cat("dropped poison:", length(intersect(st$made, names(now))), "\n")
  }
} else if (mode == "leftover") {
  for (id in args[-(1:2)]) {
    r <- DBI::dbGetQuery(conn, sprintf("SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'working' AND strpos(c.relname, '%s_') > 0", id))
    cat("run", id, "relations left:", nrow(r), paste(r$relname, collapse = " "), "\n")
  }
}
