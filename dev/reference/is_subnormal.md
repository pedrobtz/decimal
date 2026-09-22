# Identify subnormal decimal values

`is_subnormal()` reports whether each finite, nonzero value is subnormal
under the active decimal context. A value can therefore be subnormal in
one context and normal in another.

## Usage

``` r
is_subnormal(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

A logical vector with the same length as `x`.

## Examples

``` r
x <- decimal("0.001")
with_decimal_context(
  decimal_context(precision = 3L, emin = -2L),
  is_subnormal(x)
)
#> [1] TRUE
```
