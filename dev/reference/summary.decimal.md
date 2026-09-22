# Summarise a decimal vector

The six-number summary that
[`summary()`](https://rdrr.io/r/base/summary.html) gives for a numeric
vector, computed in exact decimal arithmetic and returned as a `decimal`
vector rather than a vector of doubles.

## Usage

``` r
# S3 method for class 'decimal'
summary(object, ..., maxsum = 100L, digits = NULL)
```

## Arguments

- object:

  A `decimal` vector.

- ...:

  These dots must be empty.

- maxsum, digits:

  Accepted for compatibility with
  [`summary.data.frame()`](https://rdrr.io/r/base/summary.html), which
  passes them to every column, and ignored. `digits` in particular is
  not honoured: rounding an exact decimal for display is the surprise
  this package exists to avoid.

## Value

A named `decimal` vector holding `Min.`, `1st Qu.`, `Median`, `Mean`,
`3rd Qu.` and `Max.`, followed by `NA's` when the input contains missing
values.

## Details

Missing values are removed before the statistics are computed and
reported as an `NA's` entry, matching
[`summary.default()`](https://rdrr.io/r/base/summary.html). As in base
R, `NaN` counts as missing here, because
[`is.na()`](https://rdrr.io/r/base/NA.html) is true for it.

The quartiles use the type 7 definition, the default of
[`stats::quantile()`](https://rdrr.io/r/stats/quantile.html). A quantile
that falls between two elements is interpolated, and the mean divides by
the number of elements, so both run under the active decimal context and
may raise `inexact` and `rounded` signals like any other division. The
minimum, the maximum, and any quantile that lands exactly on an element
are always exact.

Because a `decimal` vector carries one shared scale, every entry is
padded to the widest one present – including the `NA's` count, which is
a count rather than a measured value. Interpolating a quartile can need
more digits than the input carries, which widens that shared scale.

Interpolating between `-Infinity` and `Infinity` is an invalid
operation, and the default context traps it, so summarising a vector
that spans both signed infinities raises an error rather than returning
`NaN` quartiles. That is the same error
`decimal("Infinity") - decimal("Infinity")` raises. Clear the trap with
[`with_decimal_context()`](https://pedrobtz.github.io/decimal/dev/reference/with_decimal_context.md)
to get base R's `NaN` instead.

## Examples

``` r
summary(decimal(c("1.25", "2.50", "3.75", "10.00")))
#> <decimal[6]>
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>  1.2500  2.1875  3.1250  4.3750  5.3125 10.0000 

# Missing values are counted, not propagated.
summary(decimal(c("1.5", NA, "2.5")))
#> <decimal[7]>
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max.    NA's 
#>   1.500   1.750   2.000   2.000   2.250   2.500   1.000 
```
