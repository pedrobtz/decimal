# Get the active decimal arithmetic context

Get the active decimal arithmetic context

## Usage

``` r
get_decimal_context()
```

## Value

A `decimal_context` object.

## Examples

``` r
get_decimal_context()
#> <decimal_context>
#>   precision: 28
#>   rounding:  half_even
#>   emin:      -999999
#>   emax:      999999
#>   clamp:     FALSE
#>   traps:     [division_by_zero, invalid_operation, overflow]
#>   flags:     [inexact, rounded]
```
