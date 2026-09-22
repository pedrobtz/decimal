# Missing decimal scalar

A length-one missing decimal value.

## Usage

``` r
NA_decimal_
```

## Value

A length-one `decimal` vector containing the typed R missing value.

## Examples

``` r
c(decimal("1"), NA_decimal_)
#> <decimal[2]>
#> [1] 1    <NA>
```
