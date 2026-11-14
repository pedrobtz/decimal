# Summaries of decimal vectors

[`sum()`](https://rdrr.io/r/base/sum.html),
[`prod()`](https://rdrr.io/r/base/prod.html),
[`mean()`](https://rdrr.io/r/base/mean.html),
[`min()`](https://rdrr.io/r/base/Extremes.html),
[`max()`](https://rdrr.io/r/base/Extremes.html) and
[`range()`](https://rdrr.io/r/base/range.html) compute in decimal
arithmetic and return a `decimal` vector. Integer vectors can be mixed
in; doubles and strings are refused, as they are in arithmetic.

## Usage

``` r
# S3 method for class 'decimal'
mean(x, trim = 0, na.rm = FALSE, ...)

# S3 method for class 'decimal'
Summary(..., na.rm = FALSE)

# S3 method for class 'decimal'
range(x, ..., na.rm = FALSE, finite = FALSE)

# S3 method for class 'decimal'
min(x, ..., na.rm = FALSE)

# S3 method for class 'decimal'
max(x, ..., na.rm = FALSE)
```

## Arguments

- x, ...:

  `decimal` or integer vectors. A decimal must come first; see "Put a
  decimal first".

- trim:

  The fraction of values to drop from each end before averaging.

- na.rm:

  Whether to remove missing values and NaNs first.

- finite:

  Not supported; `TRUE` is an error.

## Value

A `decimal` vector: of length two for
[`range()`](https://rdrr.io/r/base/range.html), otherwise of length one.

## Details

A missing value gives `NA` unless `na.rm = TRUE`. A `NaN` gives `NaN`,
and a signaling NaN raises `invalid_operation`. `na.rm = TRUE` removes
both missing values and NaNs, because
[`is.na()`](https://rdrr.io/r/base/NA.html) is true for a NaN.

[`mean()`](https://rdrr.io/r/base/mean.html) sums the values, then
divides under the active context. A `trim` between 0 and 0.5 drops
`floor(n * trim)` values from each end of the sorted vector before
averaging, and a `trim` of 0.5 or more gives the median, as in
[`mean.default()`](https://rdrr.io/r/base/mean.html).

## Put a decimal first

R picks the method for [`sum()`](https://rdrr.io/r/base/sum.html),
[`prod()`](https://rdrr.io/r/base/prod.html),
[`min()`](https://rdrr.io/r/base/Extremes.html),
[`max()`](https://rdrr.io/r/base/Extremes.html) and
[`range()`](https://rdrr.io/r/base/range.html) from the first argument
alone. When that argument is not a decimal, R never calls these methods
and treats a decimal as the text it stores. The package has no way to
intercept this, nor to make it an error. In each case, put a decimal
first or convert the first argument with
[`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md):

- `min(10L, x)` compares text, so `min(10L, decimal("9"))` is `"10"`.
  Write `min(x, 10L)` or `min(as_decimal(10L), x)`.

- `max(2L, x)` and `range(2L, x)` return a character vector. Write
  `max(x, 2L)` or `range(as_decimal(2L), x)`.

- `sum(1L, x)` and `prod(1L, x)` fail with "invalid 'type' (character)
  of argument". Write `sum(x, 1L)` or `prod(as_decimal(1L), x)`.

- `pmax(2L, x)` and `pmin(2L, x)` return a character vector. Write
  `pmax(x, 2L)` or `pmax(as_decimal(2L), x)`.

[`pmax()`](https://rdrr.io/r/base/Extremes.html) and
[`pmin()`](https://rdrr.io/r/base/Extremes.html) are not generic. With a
decimal first they compare values, and stop with an error when a later
argument has a finer scale than the first, because base R would give the
result the first argument's scale: `pmax(decimal("10"), decimal("9.5"))`
fails, while
`pmax(as_decimal(decimal("10"), scale = 1), decimal("9.5"))` and
`pmax(decimal("9.5"), decimal("10"))` work.

[`any()`](https://rdrr.io/r/base/any.html) and
[`all()`](https://rdrr.io/r/base/all.html) are not supported for decimal
vectors.

## Examples

``` r
x <- decimal(c("9.50", "10", "2.25"))
sum(x)
#> <decimal[1]>
#> [1] 21.75
max(x, 12L)
#> <decimal[1]>
#> [1] 12.00
range(x)
#> <decimal[2]>
#> [1] 2.25  10.00
mean(decimal(c("1", "2", "3", "100")), trim = 0.25)
#> <decimal[1]>
#> [1] 2.5
```
