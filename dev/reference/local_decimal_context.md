# Install a decimal context for the current scope

Install a decimal context for the current scope

## Usage

``` r
local_decimal_context(x, .local_envir = parent.frame())
```

## Arguments

- x:

  A `decimal_context` object or compatible list.

- .local_envir:

  Environment whose scope should control restoration.

## Value

`x`, invisibly.

## Examples

``` r
f <- function() {
  local_decimal_context(decimal_context(precision = 2L, traps = character()))
  decimal("1.234") + decimal("0")
}
f()
#> Warning: Decimal `+` raised signals: inexact, rounded.
#> <decimal[1]>
#> [1] 1.2
```
