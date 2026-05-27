# WSG Drainage Closure (FWA Topology)

Given a focal set of FWA watershed groups, return the **drainage
closure** — every WSG that any focal WSG drains through — ordered
downstream-first by outlet ltree depth (`nlevel(outlet) ASC`). Pure FWA
topology; no species or bundle knowledge.

## Usage

``` r
frs_wsg_drainage(conn, watershed_group_code, table = "public.wsg_outlet")
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  (e.g. from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- watershed_group_code:

  Character vector of focal WSG codes (e.g. `c("BULK", "MORR")`). Must
  be non-empty and free of `NA`. Codes are upper-cased internally. Focal
  codes that don't exist in `table` trigger a warning and are dropped
  from the result; if no codes match, the function errors.

- table:

  Character scalar. Fully-qualified table name holding the WSG outlet
  ltree topology. Default `"public.wsg_outlet"`.

## Value

Character vector of WSG codes — focal plus every WSG they flow through —
ordered downstream-first.

## Details

Sources the FWA WSG outlet table (default `public.wsg_outlet` in fwapg).
The closure predicate is `f.outlet <@ w.outlet` — i.e. every WSG whose
outlet ltree is an ancestor of (or equal to) any focal WSG's outlet.

Order: `depth ASC, wsg ASC` — so the most downstream WSGs come first and
ties within a depth are alphabetical. Running per-WSG work in this order
persists downstream barriers before upstream WSGs read them, which makes
cross-WSG accessibility flags settle correctly within a single pass.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Skeena + Peace focal — returns the 15-WSG drainage closure DS-first
frs_wsg_drainage(conn, c("PARS", "BULK"))
#> [1] "KISP" "KLUM" "LKEL" "LSKE" "MSKE" "USKE" "BULK" "FINA"
#>     "LBTN" "LPCE" "MORR" "PARA" "PCEA" "UPCE" "PARS"

DBI::dbDisconnect(conn)
} # }
```
