# Compare decimal vector scales

`same_quantum()` tests whether `x` and `y` have the same shared vector
scale. Scale is a vector-level property in this package, so every
recycled element comparison receives the same result.

## Usage

``` r
same_quantum(x, y)
```

## Arguments

- x, y:

  Decimal-compatible vectors.

## Value

A logical vector with the common recycled size of `x` and `y`.

## Examples

``` r
same_quantum(decimal("1.00"), decimal("2.0"))
#> [1] FALSE
```
