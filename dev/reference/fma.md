# Fused multiply-add

`fma()` computes `x * y + z` with a single final rounding step. This can
be more accurate than evaluating multiplication and addition separately
under a limited-precision context. The arguments follow normal vctrs
recycling rules.

## Usage

``` r
fma(x, y, z)
```

## Arguments

- x, y, z:

  Decimal-compatible vectors.

## Value

A `decimal` vector.

## Examples

``` r
fma(decimal("2"), decimal("3"), decimal("4"))
#> <decimal[1]>
#> [1] 10
```
