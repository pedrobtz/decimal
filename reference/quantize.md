# Quantize decimal values to a scale

`quantize()` rounds each value in `x` to the scale declared by
`quantum`. The operation uses the active context's rounding mode,
updates sticky flags, and raises any enabled traps. The arguments follow
normal vctrs recycling rules.

## Usage

``` r
quantize(x, quantum)
```

## Arguments

- x:

  A decimal-compatible vector to quantize.

- quantum:

  A decimal-compatible vector whose shared scale determines the result
  scale.

## Value

A `decimal` vector with the shared scale of `quantum`.

## Details

Reducing the scale is the explicit purpose of `quantize()` (and of
[`round()`](https://rdrr.io/r/base/Round.html) and
[`signif()`](https://rdrr.io/r/base/Round.html), both implemented on top
of it), so the `inexact` and `rounded` signals this commonly raises are
not reported as warnings the way other operations' signals are (see
[`decimal_context()`](https://pedrobtz.github.io/decimal/reference/decimal_context.md));
they still accumulate as sticky flags.

## Examples

``` r
quantize(decimal("1.23456"), decimal("0.01"))
#> <decimal[1]>
#> [1] 1.23
```
