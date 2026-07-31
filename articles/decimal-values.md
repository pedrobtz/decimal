# Decimal Values

R’s doubles are binary fractions. They’re fast and almost always good
enough, but they can’t represent most decimal numbers exactly — which is
why this happens:

``` r

0.1 + 0.2 == 0.3
#> [1] FALSE
```

Most of the time you can shrug this off. But if you’re adding up
invoices, reconciling accounts, or storing prices, “almost 0.3” doesn’t
cut it. The decimal package gives you vectors that hold decimal numbers
*exactly* and compute with them exactly, following the same [General
Decimal Arithmetic](https://speleotrove.com/decimal/decarith.pdf)
standard as Python’s `decimal` module.

This vignette shows you how to create decimal vectors and work with them
day-to-day. A companion vignette,
[`vignette("contexts-and-signals")`](https://pedrobtz.github.io/decimal/articles/contexts-and-signals.md),
covers the arithmetic context: precision, rounding modes, and how
conditions like overflow are handled.

``` r

library(decimal)
```

## Creating decimal vectors

The best way to create a decimal is from a string, because a string can
say *exactly* what you mean:

``` r

x <- decimal(c("1.20", "2.30", "3.40"))
x
#> <decimal[3]>
#> [1] 1.20 2.30 3.40
```

Integers work too, and special values are written the way the standard
spells them:

``` r

decimal(c(1L, 2L, NA_integer_))
#> <decimal[3]>
#> [1] 1    2    <NA>
decimal(c("1.20", "-0", "Infinity", "NaN"))
#> <decimal[4]>
#> [1] 1.20     -0.00    Infinity NaN
```

Values are immutable and stored as text internally, so converting back
with [`format()`](https://rdrr.io/r/base/format.html) or
[`as.character()`](https://rdrr.io/r/base/character.html) always
reproduces them exactly — nothing is lost round-tripping through a CSV
file or a database column:

``` r

as.character(x)
#> [1] "1.20" "2.30" "3.40"
```

## Scale: how many decimal places?

Every decimal vector has a single shared **scale**: the number of
fractional digits stored for every element. If you don’t specify it,
decimal infers the largest number of fractional digits present, and pads
(never rounds!) the other elements to match:

``` r

decimal(c("1.2", "1.20", "1.234"))
#> <decimal[3]>
#> [1] 1.200 1.200 1.234
```

Because scale belongs to the vector rather than to each element,
`decimal("1.2")` and `decimal("1.20")` are the same value:

``` r

decimal("1.2") == decimal("1.20")
#> [1] TRUE
```

## What about doubles?

You might expect `decimal(0.1)` to work. It doesn’t, and that’s
deliberate: the double `0.1` is not actually 0.1 — its exact binary
value needs 55 fractional digits to write out in decimal! So converting
a double is explicit, via
[`as_decimal()`](https://pedrobtz.github.io/decimal/reference/as_decimal.md)
or
[`decimal_from_double()`](https://pedrobtz.github.io/decimal/reference/decimal_from_double.md),
and you have to say how many digits you want to keep:

``` r

decimal_from_double(0.1, scale = 25)
#> <decimal[1]>
#> [1] 0.1000000000000000055511151
```

If what you want is decimal `0.1`, write `decimal("0.1")`:

``` r

decimal("0.1")
#> <decimal[1]>
#> [1] 0.1
```

If your workflow consistently uses one scale — say, you always want 7
digits — set the opt-in default so you don’t have to repeat yourself. An
explicit `scale` argument still wins:

``` r

withr::with_options(
  list(decimal.default_scale = 7L),
  as_decimal(0.002)
)
#> <decimal[1]>
#> [1] 0.0020000
```

Set it globally with `options(decimal.default_scale = 7L)`, or use
[`withr::local_options()`](https://withr.r-lib.org/reference/with_options.html)
when the default should apply only within a function or a test.

## Decimals are well-behaved vectors

Decimal vectors are built on [vctrs](https://vctrs.r-lib.org), so they
behave the way you’d hope inside data frames and tibbles, and with
sorting, matching, and friends:

``` r

tibble::tibble(
  item  = c("coffee", "bagel", "juice"),
  price = decimal(c("2.50", "1.25", "3.95"))
)
#> # A tibble: 3 × 2
#>   item   price
#>   <chr>  <dec>
#> 1 coffee  2.50
#> 2 bagel   1.25
#> 3 juice   3.95
```

They combine freely with integers, promoting to the common (largest)
scale:

``` r

vctrs::vec_c(decimal("1.20"), 2L, NA)
#> <decimal[3]>
#> [1] 1.20 2.00 <NA>
```

But they refuse to *implicitly* combine with doubles or character
strings:

``` r

vctrs::vec_c(decimal("1.20"), 0.5)
#> Error in `vctrs::vec_c()`:
#> ! Can't combine `..1` <decimal> and `..2` <double>.
```

That’s the same design decision as above, applied consistently: a double
needs a scale decided for it, and a string needs to be parsed (which can
fail), so neither is a lossless, always-safe promotion the way integer
is. When you mean it, say it — call
[`decimal()`](https://pedrobtz.github.io/decimal/reference/decimal.md)
or
[`as_decimal()`](https://pedrobtz.github.io/decimal/reference/as_decimal.md)
explicitly.

## Arithmetic

Arithmetic is vectorized, context-controlled, and keeps track of
significance:

``` r

decimal("1.20") + decimal("2.3")
#> <decimal[1]>
#> [1] 3.50
sum(decimal(c("1.20", "2.30", "3.40")))
#> <decimal[1]>
#> [1] 6.90
mean(decimal(c("1", "2", "3")))
#> <decimal[1]>
#> [1] 2
```

One difference from base R worth knowing about: `%%` and `%/%`. Base R
floors integer division toward negative infinity, while General Decimal
Arithmetic truncates toward zero, so results differ for negative
operands:

``` r

-7 %% 4                        # base R: floored, remainder takes divisor's sign
#> [1] 1
decimal("-7") %% decimal("4")  # decimal: truncated, remainder takes dividend's sign
#> <decimal[1]>
#> [1] -3

-7 %/% 4
#> [1] -2
decimal("-7") %/% decimal("4")
#> <decimal[1]>
#> [1] -1
```

## Special values

decimal supports the full menagerie: `NA`, NaNs, infinities, and signed
zero — and it keeps R’s missing value distinct from decimal’s
not-a-number:

``` r

x <- decimal(c(NA_character_, "NaN", "sNaN", "Infinity", "-0"))
x
#> <decimal[5]>
#> [1] <NA>     NaN      sNaN     Infinity -0
is.na(x)
#> [1]  TRUE  TRUE  TRUE FALSE FALSE
is.nan(x)
#> [1] FALSE  TRUE  TRUE FALSE FALSE
number_class(x)
#> [1] NA          "NaN"       "sNaN"      "+Infinity" "-Zero"
```

A few things to note:

- `NA` is an R missing value — it’s absent from the computation
  entirely.

- `NaN` (quiet NaN) and `sNaN` (signaling NaN) are decimal not-a-number
  values that participate in arithmetic. A quiet NaN propagates
  silently; an sNaN raises the `invalid_operation` signal, which is an
  error under the default context — see
  [`vignette("contexts-and-signals")`](https://pedrobtz.github.io/decimal/articles/contexts-and-signals.md).

- [`is.na()`](https://rdrr.io/r/base/NA.html) returns `TRUE` for both
  `NA` and decimal NaNs, matching base R’s own `is.na(NaN)`. Use
  [`is.nan()`](https://rdrr.io/r/base/is.finite.html) to tell a decimal
  NaN apart from a missing value.

- Signed zero survives formatting: `-0` prints as `-0`, not `0`.

## Rounding and other decimal tools

[`quantize()`](https://pedrobtz.github.io/decimal/reference/quantize.md)
is the workhorse for rounding: it rescales `x` to the scale declared by
`quantum`, using the active context’s rounding mode. It’s the operation
behind [`round()`](https://rdrr.io/r/base/Round.html) and
[`signif()`](https://rdrr.io/r/base/Round.html), and it reads naturally
for the most common case — rounding to cents:

``` r

quantize(decimal("1.2345"), decimal("0.01"))
#> <decimal[1]>
#> [1] 1.23
```

[`normalize()`](https://pedrobtz.github.io/decimal/reference/normalize.md)
strips shared trailing zeros down to the finest scale the vector
actually needs, without discarding any element’s significance:

``` r

normalize(decimal(c("1.2300", "1.2")))
#> <decimal[2]>
#> [1] 1.23 1.20
```

`fma(a, b, c)` computes `a * b + c` as one fused operation with a single
rounding at the end, instead of rounding after the multiplication and
again after the addition:

``` r

fma(decimal("2"), decimal("3"), decimal("4"))
#> <decimal[1]>
#> [1] 10
```

[`same_quantum()`](https://pedrobtz.github.io/decimal/reference/same_quantum.md)
reports whether two vectors share the same declared scale (remember,
scale is a per-vector property):

``` r

same_quantum(decimal(c("1.20", "2.0")), decimal(c("2.30", "3.00")))
#> [1] TRUE TRUE
```

And
[`adjusted()`](https://pedrobtz.github.io/decimal/reference/adjusted.md)
returns each value’s adjusted exponent — the exponent it would have in
scientific notation with a single digit before the point:

``` r

adjusted(decimal(c("1.2300", "1E-3")))
#> [1]  0 -3
```

## Where to next

Everything above used the default arithmetic settings: 28 digits of
precision, round-half-even, and errors on division by zero, invalid
operations, and overflow. All of that is configurable through the
decimal *context* — read on in
[`vignette("contexts-and-signals")`](https://pedrobtz.github.io/decimal/articles/contexts-and-signals.md).
