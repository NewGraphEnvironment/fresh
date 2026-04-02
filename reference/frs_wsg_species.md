# Species Present in a Watershed Group

Look up which species have bcfishpass habitat models for a given
watershed group code. Returns species codes and their corresponding
bcfishpass view names. Based on the
[wsg_species_presence.csv](https://github.com/smnorris/bcfishpass/blob/main/data/wsg_species_presence.csv)
bundled in the package.

## Usage

``` r
frs_wsg_species(watershed_group_code)
```

## Arguments

- watershed_group_code:

  Character. One or more watershed group codes (e.g. `"BULK"`,
  `c("BULK", "MORR")`).

## Value

A data frame with columns:

- watershed_group_code:

  Watershed group code

- species_code:

  Uppercase species code (e.g. `"CO"`, `"BT"`)

- view:

  bcfishpass view name (e.g. `"bcfishpass.streams_co_vw"`), or `NA` for
  species without a view

## Details

Some species share a combined view in bcfishpass: cutthroat trout
(`ct`), Dolly Varden (`dv`), and rainbow trout (`rb`) all use
`streams_ct_dv_rb_vw`. Arctic grayling (`gr`) has no bcfishpass view and
is excluded from view mapping.

## See also

Other parameters:
[`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md)

## Examples

``` r
# Which species are modelled in the Bulkley watershed group?
frs_wsg_species("BULK")
#>   watershed_group_code species_code                           view
#> 1                 BULK           BT       bcfishpass.streams_bt_vw
#> 2                 BULK           CH       bcfishpass.streams_ch_vw
#> 3                 BULK           CO       bcfishpass.streams_co_vw
#> 4                 BULK           CT bcfishpass.streams_ct_dv_rb_vw
#> 5                 BULK           DV bcfishpass.streams_ct_dv_rb_vw
#> 6                 BULK           PK       bcfishpass.streams_pk_vw
#> 7                 BULK           RB bcfishpass.streams_ct_dv_rb_vw
#> 8                 BULK           SK       bcfishpass.streams_sk_vw
#> 9                 BULK           ST       bcfishpass.streams_st_vw

# Multiple watershed groups
frs_wsg_species(c("BULK", "MORR"))
#>    watershed_group_code species_code                           view
#> 1                  BULK           BT       bcfishpass.streams_bt_vw
#> 2                  BULK           CH       bcfishpass.streams_ch_vw
#> 3                  BULK           CO       bcfishpass.streams_co_vw
#> 4                  BULK           CT bcfishpass.streams_ct_dv_rb_vw
#> 5                  BULK           DV bcfishpass.streams_ct_dv_rb_vw
#> 6                  BULK           PK       bcfishpass.streams_pk_vw
#> 7                  BULK           RB bcfishpass.streams_ct_dv_rb_vw
#> 8                  BULK           SK       bcfishpass.streams_sk_vw
#> 9                  BULK           ST       bcfishpass.streams_st_vw
#> 10                 MORR           BT       bcfishpass.streams_bt_vw
#> 11                 MORR           CH       bcfishpass.streams_ch_vw
#> 12                 MORR           CO       bcfishpass.streams_co_vw
#> 13                 MORR           CT bcfishpass.streams_ct_dv_rb_vw
#> 14                 MORR           DV bcfishpass.streams_ct_dv_rb_vw
#> 15                 MORR           PK       bcfishpass.streams_pk_vw
#> 16                 MORR           RB bcfishpass.streams_ct_dv_rb_vw
#> 17                 MORR           SK       bcfishpass.streams_sk_vw
#> 18                 MORR           ST       bcfishpass.streams_st_vw

# Just the unique views needed for BULK
sp <- frs_wsg_species("BULK")
unique(sp$view[!is.na(sp$view)])
#> [1] "bcfishpass.streams_bt_vw"       "bcfishpass.streams_ch_vw"      
#> [3] "bcfishpass.streams_co_vw"       "bcfishpass.streams_ct_dv_rb_vw"
#> [5] "bcfishpass.streams_pk_vw"       "bcfishpass.streams_sk_vw"      
#> [7] "bcfishpass.streams_st_vw"      
```
