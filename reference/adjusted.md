# Compute the adjusted exponent

`adjusted()` returns the position of the most significant digit after
accounting for the stored exponent. For a finite nonzero value, this is
equivalent to the base-10 order of magnitude. The representation of zero
retains its exponent, so differently scaled zeros can have different
adjusted exponents.

## Usage

``` r
adjusted(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

An integer vector with the same length as `x`. Infinities, NaNs, and R
missing values produce `NA_integer_`.

## Examples

``` r
adjusted(decimal(c("123", "0.01")))
#> [1]  2 -2
```
