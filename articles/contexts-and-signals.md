# Contexts and Signals

When you add two decimals, how many digits should the result keep? What
happens when it doesn’t fit — round it, or error? And which way should
it round? In decimal arithmetic, these are not hard-coded answers: they
come from the **context**, an explicit, session-wide setting that
governs every operation.

This vignette shows you how to inspect the context, change it (safely!),
and work with the *signals* that operations raise along the way —
conditions like `inexact`, `division_by_zero`, and `overflow`.

If you haven’t yet, start with
[`vignette("decimal-values")`](https://pedrobtz.github.io/decimal/articles/decimal-values.md):
values themselves are immutable. Parsing and promotion to a finer shared
scale are exact; an explicit coarser scale is a quantization request.
The context shapes arithmetic and quantization, so changing it never
changes values already created.

``` r

library(decimal)
```

## The default context

You can look at the active context at any time:

``` r

get_decimal_context()
#> <decimal_context>
#>   precision: 28
#>   rounding:  half_even
#>   emin:      -999999
#>   emax:      999999
#>   clamp:     FALSE
#>   traps:     [division_by_zero, invalid_operation, overflow]
#>   flags:     []
```

The defaults are sensible for most work:

- **precision 28** — results keep up to 28 significant digits;
- **round half even** — banker’s rounding, the same default as Python;
- **`Emin = -999999` and `Emax = 999999`** — generous exponent limits;
- **traps on `invalid_operation`, `division_by_zero`, and `overflow`** —
  the conditions most likely to mean a genuine bug are errors, while
  routine rounding is not.

## Changing the context, temporarily

You’ll rarely want to change the context for a whole session. Instead,
scope the change, in the same spirit as `withr::with_*()` and
`withr::local_*()`.

[`with_decimal_context()`](https://pedrobtz.github.io/decimal/reference/with_decimal_context.md)
applies a context to a single expression, then restores the previous
one:

``` r

ctx <- decimal_context(precision = 2L, traps = character())

with_decimal_context(ctx, decimal("1.25") + decimal("0"))
#> <decimal[1]>
#> [1] 1.2
get_decimal_context()
#> <decimal_context>
#>   precision: 28
#>   rounding:  half_even
#>   emin:      -999999
#>   emax:      999999
#>   clamp:     FALSE
#>   traps:     [division_by_zero, invalid_operation, overflow]
#>   flags:     []
```

[`local_decimal_context()`](https://pedrobtz.github.io/decimal/reference/local_decimal_context.md)
applies a context until the calling function returns, which is handy
when several statements need it:

``` r

f <- function() {
  local_decimal_context(decimal_context(precision = 2L, traps = character()))
  decimal("1.234") + decimal("0")
}
f()
#> <decimal[1]>
#> [1] 1.2
get_decimal_context()
#> <decimal_context>
#>   precision: 28
#>   rounding:  half_even
#>   emin:      -999999
#>   emax:      999999
#>   clamp:     FALSE
#>   traps:     [division_by_zero, invalid_operation, overflow]
#>   flags:     []
```

Either way, the previous context comes back automatically when the scope
ends — even if an error interrupts it.

## Signals and sticky flags

Decimal operations *signal* noteworthy conditions: a result was rounded,
a division hit zero, a value overflowed. What happens next depends on
the context, and each signal gets one of three dispositions:

- **Trapped** — the operation raises a classed R error.
- **Reported** — the signal is recorded as a flag *and* surfaced as a
  warning. This is the default for any signal you haven’t trapped.
- **Silent** — the signal is recorded as a flag only.

The flags are *sticky*: once raised, they stay raised until you clear
them, so you can run a whole computation and check afterwards what
happened along the way:

``` r

ctx <- decimal_context(precision = 2L, traps = character())
with_decimal_context(ctx, {
  clear_decimal_flags()
  decimal("1.25") + decimal("0")
  decimal("1") / decimal("8")
  decimal_flags()
})
#> [1] "inexact" "rounded"
```

Both operations had to round to fit two significant digits, raising
`inexact` and `rounded`; the flags simply stay raised across the whole
block. Use
[`clear_decimal_flags()`](https://pedrobtz.github.io/decimal/reference/clear_decimal_flags.md)
to start a fresh slate before a computation you want to audit.

## Reporting signals

By default, any signal that isn’t trapped is also *reported* — surfaced
as a warning as it occurs, so precision loss never passes silently:

``` r

withr::with_options(
  list(decimal.report_flags = TRUE),
  with_decimal_context(
    decimal_context(precision = 2L, traps = character()),
    decimal("1.25") + decimal("0")
  )
)
#> Warning: Decimal `+` raised signals: inexact, rounded.
#> <decimal[1]>
#> [1] 1.2
```

The warning is purely informational; the sticky flags accumulate either
way. If you’d rather check flags on your own schedule, set
`options(decimal.report_flags = FALSE)` and inspect
[`decimal_flags()`](https://pedrobtz.github.io/decimal/reference/decimal_flags.md)
directly — that’s what this vignette does behind the scenes to keep the
output focused.

A few operations are exempt from the warning, because for them
`inexact`/`rounded` is the *requested* outcome, not a surprise:
[`quantize()`](https://pedrobtz.github.io/decimal/reference/quantize.md)
(and [`round()`](https://rdrr.io/r/base/Round.html) and
[`signif()`](https://rdrr.io/r/base/Round.html), which build on it)
exist precisely to drop digits you named, and
[`sqrt()`](https://rdrr.io/r/base/MathFun.html),
[`exp()`](https://rdrr.io/r/base/Log.html),
[`log()`](https://rdrr.io/r/base/Log.html), and
[`log10()`](https://rdrr.io/r/base/Log.html) are irrational for nearly
every input. Division is *not* exempt — it’s only sometimes inexact, so
the warning there is genuinely informative:

``` r

withr::with_options(
  list(decimal.report_flags = TRUE),
  with_decimal_context(decimal_context(precision = 10L, traps = character()), {
    sqrt(decimal("2"))          # inexact, but silent -- expected of sqrt()
    decimal("1") / decimal("3") # inexact, and warns -- not every division is
  })
)
#> Warning: Decimal `/` raised signals: inexact, rounded.
#> <decimal[1]>
#> [1] 0.3333333333
```

Exempted operations still update the sticky flags as usual; only the
warning is suppressed.

## Traps: turning signals into errors

A trapped signal stops the computation with a classed R error you can
handle with [`tryCatch()`](https://rdrr.io/r/base/conditions.html):

``` r

with_decimal_context(decimal_context(traps = "division_by_zero"), {
  decimal("1") / decimal("0")
})
#> Error in decimal_native_result(decimal_context_call(.Call, decimal_c_binary_op_strings, : Decimal trap during `/` at element 1: division_by_zero.
```

The default traps (`division_by_zero`, `invalid_operation`, `overflow`)
catch the conditions that usually indicate a bug. `invalid_operation`
groups the standard invalid subconditions, including undefined division
such as `0 / 0`. You can go stricter: for example, in a context where
*any* loss of precision should be an error — reconciling ledgers, say —
trap `inexact` too:

``` r

strict <- decimal_context(
  traps = c("division_by_zero", "invalid_operation", "overflow", "inexact")
)
with_decimal_context(strict, decimal("1") / decimal("3"))
#> Error in decimal_native_result(decimal_context_call(.Call, decimal_c_binary_op_strings, : Decimal trap during `/` at element 1: inexact.
```

## Classifying values

The context even shapes how values are *classified*. A finite, nonzero
value is **subnormal** when its exponent falls below the context’s
`emin`, meaning fewer significant digits are available to it than
`precision` allows; otherwise it’s **normal**. So classification depends
on the active context, not on the value alone — below, `1E-3` is
subnormal only because `emin = -2L` puts it out of the normal range:

``` r

ctx <- decimal_context(precision = 3L, emin = -2L)
with_decimal_context(ctx, {
  x <- decimal(c("1E-2", "1E-3", "-0", "NaN", "sNaN"))
  number_class(x)
})
#> [1] "+Normal"    "+Subnormal" "-Zero"      "NaN"        "sNaN"
```

For quick checks there’s a family of predicates:

``` r

x <- decimal(c("NaN", "sNaN", "Infinity", "-0", "1E-3"))
is_qnan(x)
#> [1]  TRUE FALSE FALSE FALSE FALSE
is_snan(x)
#> [1] FALSE  TRUE FALSE FALSE FALSE
is.infinite(x)
#> [1] FALSE FALSE  TRUE FALSE FALSE
is_zero(x)
#> [1] FALSE FALSE FALSE  TRUE FALSE
is_signed(x)
#> [1] FALSE FALSE FALSE  TRUE FALSE
```

[`is_signed()`](https://pedrobtz.github.io/decimal/reference/is_signed.md)
reports the sign bit directly, including on zero — it’s how you tell
`-0` apart from `0`, since [`sign()`](https://rdrr.io/r/base/sign.html)
treats both as `0`.
