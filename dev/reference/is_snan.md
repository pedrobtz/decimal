# Identify signaling NaN values

`is_snan()` identifies signaling not-a-number values without performing
an arithmetic operation or raising the `invalid_operation` signal.

## Usage

``` r
is_snan(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

A logical vector with the same length as `x`.

## Examples

``` r
is_snan(decimal(c("sNaN", "NaN", "1")))
#> [1]  TRUE FALSE FALSE
```
