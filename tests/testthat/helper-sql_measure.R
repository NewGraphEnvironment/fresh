# The literal each `downstream_route_measure <= <x>` segment pick sends, in
# order, from SQL captured by a mocked frs_db_query() (#274).
sql_measure_picks <- function(sql) {
  unlist(regmatches(sql, gregexpr("(?<=downstream_route_measure <= )[^\n]+",
                                  sql, perl = TRUE)))
}
