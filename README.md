# decimal

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/decimal/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/decimal/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/decimal/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/decimal/actions/workflows/coverage.yaml)
<!-- badges: end -->

The package brings exact, arbitrary-precision decimal numbers to R. It is built
on top of the [`mpdecimal`](https://www.bytereef.org/mpdecimal/doc/libmpdec/)
C library for the underlying arithmetic, and on the R package
[`vctrs`](https://vctrs.r-lib.org/) so the values work naturally as vectors
and in data frames and tibbles.

## Main features

- element-wise arithmetic: `+`, `-`, `*`, `/`, `^`, `%%`, and `%/%`;
- math functions `abs()`, `sign()`, `sqrt()`, `exp()`, `log()`, `log10()`,
  `floor()`, `ceiling()`, and `trunc()`, plus a fused multiply-add `fma()`;
- reductions `sum()`, `prod()`, `min()`, `max()`, and `mean()`;
- exact comparison, sorting, and matching;
- exact construction from character and integer vectors, at a single shared
  vector scale;
- explicit, exact conversion from doubles via `as_decimal()` and
  `decimal_from_double()`, using an explicit or globally configured scale;
- active contexts with precision, rounding, traps, and sticky flags that
  control how signals such as overflow or division by zero are handled;
- support for `NA`, signed zero, infinities, qNaN, and sNaN;
- decimal-specific helpers such as `quantize()`, `normalize()`,
  `same_quantum()`, `adjusted()`, and `number_class()`.

## Installation

Install the released version from CRAN with:

```r
install.packages("decimal")
```

Or install the development version from GitHub with pak:

```r
# install.packages("pak")
pak::pak("pedrobtz/decimal")
```

## Quick examples

```r
library(decimal)

x <- decimal(c("1.20", "2.30", "3.40"))
sum(x)
#> <decimal[1]>
#> [1] 6.90

# 5% annual interest compounded over 4 years, kept exact
principal <- decimal(c("1000.00", "2500.00", "500.00"))
rate <- decimal("0.05")

balance <- principal * (1L + rate)^4L
balance
#> <decimal[3]>
#> [1] 1215.5062500000 3038.7656250000  607.7531250000

# round to cents for reporting
quantize(balance, decimal("0.01"))
#> <decimal[3]>
#> [1] 1215.51 3038.77  607.75
```

## Documentation

- `vignette("decimal-values", package = "decimal")`
- `vignette("contexts-and-signals", package = "decimal")`
- To learn more about decimal arithmetic itself, see the
  [General Decimal Arithmetic specification](https://speleotrove.com/decimal/decarith.pdf),
  which `mpdecimal` implements and this package follows.

## License

The R package is MIT licensed. The vendored `mpdecimal` library retains its
own BSD-2-Clause terms; see `inst/COPYRIGHTS`.
