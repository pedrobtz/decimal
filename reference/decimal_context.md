# Create a decimal arithmetic context

Constructs a validated arithmetic context for native `mpdecimal`
operations. The context controls precision, rounding, exponent limits,
traps, sticky flags, and classification of normal versus subnormal
values.

## Usage

``` r
decimal_context(
  precision = 28L,
  rounding = "half_even",
  emax = 999999L,
  emin = -999999L,
  traps = decimal_default_traps(),
  flags = character(),
  clamp = FALSE
)
```

## Arguments

- precision:

  Integer scalar precision.

- rounding:

  One of `"up"`, `"down"`, `"ceiling"`, `"floor"`, `"half_up"`,
  `"half_down"`, `"half_even"`, or `"05up"`.

- emax:

  Integer scalar maximum exponent.

- emin:

  Integer scalar minimum exponent.

- traps:

  Character vector of trapped signals. Trapped signals raise an error;
  all other raised signals are recorded as flags and, unless
  `options(decimal.report_flags = FALSE)`, reported as warnings.

- flags:

  Character vector of sticky signal flags.

- clamp:

  Logical scalar clamp mode.

## Value

A `decimal_context` object.

## Details

Each operation may raise one or more signals (see
[`decimal_flags()`](https://pedrobtz.github.io/decimal/reference/decimal_flags.md)).
Their disposition depends on `traps`:

- A raised signal that is in `traps` stops the operation with an error.

- Any other raised signal is recorded as a sticky flag and, by default,
  also surfaced as a warning of class `decimal_flags_warning`.

The warnings are purely informational; sticky flags accumulate either
way. Set `options(decimal.report_flags = FALSE)` to silence them and
rely on
[`decimal_flags()`](https://pedrobtz.github.io/decimal/reference/decimal_flags.md)
alone.

Public signal names are `"clamped"`, `"division_by_zero"`, `"inexact"`,
`"invalid_operation"`, `"overflow"`, `"rounded"`, `"subnormal"`, and
`"underflow"`. The standard `invalid_operation` condition groups
lower-level invalid subconditions such as undefined division (`0 / 0`).

A few operations are exempt from the warning because `inexact`/`rounded`
is their guaranteed, expected outcome rather than a surprise:
[`quantize()`](https://pedrobtz.github.io/decimal/reference/quantize.md)
(and
[`round()`](https://rdrr.io/r/base/Round.html)/[`signif()`](https://rdrr.io/r/base/Round.html),
built on it), and [`sqrt()`](https://rdrr.io/r/base/MathFun.html),
[`exp()`](https://rdrr.io/r/base/Log.html),
[`log()`](https://rdrr.io/r/base/Log.html), and
[`log10()`](https://rdrr.io/r/base/Log.html), which are irrational for
nearly every input. These still accumulate sticky flags as usual.

## Examples

``` r
decimal_context(precision = 10L)
#> <decimal_context>
#>   precision: 10
#>   rounding:  half_even
#>   emin:      -999999
#>   emax:      999999
#>   clamp:     FALSE
#>   traps:     [division_by_zero, invalid_operation, overflow]
#>   flags:     []
decimal_context(precision = 3L, rounding = "floor", traps = character())
#> <decimal_context>
#>   precision: 3
#>   rounding:  floor
#>   emin:      -999999
#>   emax:      999999
#>   clamp:     FALSE
#>   traps:     []
#>   flags:     []
```
