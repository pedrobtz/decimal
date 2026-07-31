# Read sticky decimal flags

Sticky flags accumulate the signals raised by operations that were not
trapped (see
[`decimal_context()`](https://pedrobtz.github.io/decimal/reference/decimal_context.md)).
They persist until
[`clear_decimal_flags()`](https://pedrobtz.github.io/decimal/reference/clear_decimal_flags.md)
is called. By default the same non-trapped signals are also reported as
warnings as they occur; set `options(decimal.report_flags = FALSE)` to
silence the warnings and inspect flags only through this function.

## Usage

``` r
decimal_flags()
```

## Value

A character vector of active sticky flags.

## Examples

``` r
decimal_flags()
#> character(0)
```
