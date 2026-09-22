# Identify normal decimal values

`is_normal()` reports whether each finite, nonzero value is normal under
the active decimal context. Normality depends on the context's exponent
limits and precision.

## Usage

``` r
is_normal(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

A logical vector with the same length as `x`.

## Examples

``` r
is_normal(decimal(c("1", "0", "Infinity")))
#> [1]  TRUE FALSE FALSE
```
