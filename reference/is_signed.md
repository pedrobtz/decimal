# Identify values with a negative sign

`is_signed()` inspects the stored sign bit rather than comparing with
zero. It therefore identifies negative zero as signed.

## Usage

``` r
is_signed(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

A logical vector with the same length as `x`.

## Examples

``` r
is_signed(decimal(c("-2", "2", "-0", "0")))
#> [1]  TRUE FALSE  TRUE FALSE
```
