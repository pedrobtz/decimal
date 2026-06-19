# decimal

`decimal` is an R package for arbitrary-precision decimal vectors backed by
the vendored [`mpdecimal`](https://www.bytereef.org/mpdecimal/doc/libmpdec/) C library.

Version `0.1.0` is a correctness-first release focused on exact values,
context-aware arithmetic, vector behavior, and special-value semantics.

## Installation

Once on CRAN:

```r
install.packages("decimal")
```

Development version from GitHub:

```r
# install.packages("pak")
pak::pak("pedrobtz/decimal")
```

## Why decimal?

Binary doubles are fast, but many decimal quantities are not represented
exactly:

```r
library(decimal)

format(0.1 + 0.2, digits = 17)
#> [1] "0.30000000000000004"

decimal("0.1") + decimal("0.2")
#> <decimal[1]>
#> [1] 0.3

as_decimal(0.1)
#> <decimal[1]>
#> [1] 0.1000000000000000055511151231257827021181583404541015625
```

`decimal("0.1")` means the decimal literal `0.1`. `as_decimal(0.1)` means the
exact underlying IEEE 754 double value.

## Main features

- exact construction from character and integer vectors;
- explicit, exact conversion from doubles via `as_decimal()` and
  `decimal_from_double()`;
- active contexts with precision, rounding, traps, and sticky flags;
- vectorized arithmetic, comparison, sorting, matching, and summaries;
- support for `NA`, signed zero, infinities, qNaN, and sNaN;
- decimal-specific helpers such as `quantize()`, `normalize()`, `fma()`,
  `same_quantum()`, `adjusted()`, and `number_class()`.

## Quick examples

```r
library(decimal)

x <- decimal(c("1.20", "2.30", "3.40"))
sum(x)
#> <decimal[1]>
#> [1] 6.90

ctx <- decimal_context(precision = 3L, traps = character())
with_decimal_context(ctx, decimal("1.25") + decimal("0"))
#> <decimal[1]>
#> [1] 1.25

set_decimal_context(decimal_context(precision = 2L, traps = character()))
clear_decimal_flags()
decimal("1.25") + decimal("0")
#> <decimal[1]>
#> [1] 1.2
decimal_flags()
#> [1] "inexact" "rounded"
```

## Documentation

- `vignette("decimal-values", package = "decimal")`
- `vignette("contexts-and-signals", package = "decimal")`

## License

The R package is MIT licensed. The vendored `mpdecimal` library retains its
own BSD-2-Clause terms; see `inst/COPYRIGHTS`.
