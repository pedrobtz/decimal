# Identify quiet NaN values

`is_qnan()` identifies quiet not-a-number values. Signaling NaNs and R
missing values are not quiet NaNs.

## Usage

``` r
is_qnan(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

A logical vector with the same length as `x`.

## Examples

``` r
is_qnan(decimal(c("NaN", "sNaN", "1")))
#> [1]  TRUE FALSE FALSE
```
