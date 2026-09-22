# Identify decimal zeros

`is_zero()` identifies both positive and negative zero, regardless of
the vector's scale.

## Usage

``` r
is_zero(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

A logical vector with the same length as `x`.

## Examples

``` r
is_zero(decimal(c("0.00", "-0", "1")))
#> [1]  TRUE  TRUE FALSE
```
