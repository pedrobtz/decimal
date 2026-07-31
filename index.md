# decimal

## Overview

decimal provides exact, arbitrary-precision decimal vectors for R. If
you’ve ever been surprised that `0.1 + 0.2 == 0.3` is `FALSE`, this
package is for you:

``` r

library(decimal)

0.1 + 0.2 == 0.3
#> [1] FALSE
decimal("0.1") + decimal("0.2") == decimal("0.3")
#> [1] TRUE
```

Doubles are binary fractions, so they can’t represent most decimal
numbers exactly, and tiny errors accumulate as you compute. That’s
usually fine — but not when you’re working with money, invoices,
exchange rates, or anything else where cents have to add up. decimal
uses a decimal representation and performs arithmetic under an explicit
decimal context, so any rounding is controlled and observable.

Under the hood, decimal is built on:

- [mpdecimal](https://www.bytereef.org/mpdecimal/doc/libmpdec/), the
  battle-tested C library behind Python’s `decimal` module, implementing
  the [General Decimal
  Arithmetic](https://speleotrove.com/decimal/decarith.pdf) standard.

- [vctrs](https://vctrs.r-lib.org), so decimal vectors work naturally in
  data frames, tibbles, `dplyr::mutate()`, joins, sorting, and
  everything else you already do with vectors.

Highlights:

- **Exact values.** Strings and integers are parsed exactly; promotion
  to a finer shared scale only adds trailing zeros. Values round-trip
  through [`as.character()`](https://rdrr.io/r/base/character.html)
  without loss — nothing changes on the way to a CSV file or database
  column and back.

- **Full arithmetic.** `+`, `-`, `*`, `/`, `^`, `%%`, `%/%`,
  comparisons, and math functions like
  [`abs()`](https://rdrr.io/r/base/MathFun.html),
  [`sqrt()`](https://rdrr.io/r/base/MathFun.html),
  [`exp()`](https://rdrr.io/r/base/Log.html), and
  [`log()`](https://rdrr.io/r/base/Log.html), plus reductions
  [`sum()`](https://rdrr.io/r/base/sum.html),
  [`prod()`](https://rdrr.io/r/base/prod.html),
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html), and
  [`mean()`](https://rdrr.io/r/base/mean.html).

- **Decimal-aware tools.**
  [`quantize()`](https://pedrobtz.github.io/decimal/reference/quantize.md)
  to round to a fixed number of digits (say, cents),
  [`normalize()`](https://pedrobtz.github.io/decimal/reference/normalize.md),
  [`fma()`](https://pedrobtz.github.io/decimal/reference/fma.md),
  [`same_quantum()`](https://pedrobtz.github.io/decimal/reference/same_quantum.md),
  [`adjusted()`](https://pedrobtz.github.io/decimal/reference/adjusted.md),
  and
  [`number_class()`](https://pedrobtz.github.io/decimal/reference/number_class.md).

- **You control the rules.** A decimal context sets the precision,
  rounding mode, and which conditions (overflow, division by zero, …)
  are errors — see
  [`vignette("contexts-and-signals")`](https://pedrobtz.github.io/decimal/articles/contexts-and-signals.md).

- **Special values.** `NA`, signed zeros, infinities, and quiet and
  signaling NaNs are supported throughout.

## Installation

Install the released version from CRAN:

``` r

install.packages("decimal")
```

## Usage

Create decimal vectors from strings (exact, and the recommended way) or
integers, and use them like any other numeric vector:

``` r

library(decimal)

x <- decimal(c("1.20", "2.30", "3.40"))
x
#> <decimal[3]>
#> [1] 1.20 2.30 3.40

sum(x)
#> <decimal[1]>
#> [1] 6.90
mean(x)
#> <decimal[1]>
#> [1] 2.30
```

Decimal vectors are first-class citizens in tibbles and dplyr pipelines:

``` r

library(dplyr)

sales <- tibble::tibble(
  item  = c("coffee", "bagel", "juice"),
  price = decimal(c("2.50", "1.25", "3.95")),
  qty   = c(3L, 2L, 1L)
)

sales |>
  mutate(total = price * qty) |>
  summarise(revenue = sum(total))
#> # A tibble: 1 × 1
#>   revenue
#>     <dec>
#> 1   13.95
```

Exactness matters most when small errors compound — literally, in the
case of interest:

``` r

principal <- decimal(c("1000.00", "2500.00", "500.00"))
rate <- decimal("0.05")

balance <- principal * (1L + rate)^4L
balance
#> <decimal[3]>
#> [1] 1215.5062500000 3038.7656250000 607.7531250000

# round to cents for reporting
quantize(balance, decimal("0.01"))
#> <decimal[3]>
#> [1] 1215.51 3038.77 607.75
```

## Learning more

- [`vignette("decimal-values")`](https://pedrobtz.github.io/decimal/articles/decimal-values.md)
  introduces decimal vectors: how to create them, how scale works, and
  the everyday operations.

- [`vignette("contexts-and-signals")`](https://pedrobtz.github.io/decimal/articles/contexts-and-signals.md)
  covers the arithmetic context: precision, rounding modes, traps, and
  flags.

- The [General Decimal Arithmetic
  specification](https://speleotrove.com/decimal/decarith.pdf) is the
  standard that mpdecimal implements and this package follows.

## License

decimal is MIT licensed. The vendored mpdecimal library retains its own
BSD-2-Clause terms; see `inst/COPYRIGHTS`.
