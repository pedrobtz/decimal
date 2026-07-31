# Use a decimal context within a block

Use a decimal context within a block

## Usage

``` r
with_decimal_context(x, code)
```

## Arguments

- x:

  A `decimal_context` object or compatible list.

- code:

  Code evaluated with `x` installed as the active context.

## Value

The result of `code`.

## Examples

``` r
with_decimal_context(
  decimal_context(precision = 3L, traps = character()),
  decimal("1.25") + decimal("0")
)
#> <decimal[1]>
#> [1] 1.25
```
