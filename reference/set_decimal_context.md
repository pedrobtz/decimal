# Set the active decimal arithmetic context

Set the active decimal arithmetic context

## Usage

``` r
set_decimal_context(x)
```

## Arguments

- x:

  A `decimal_context` object or compatible list.

## Value

The previously active `decimal_context`, invisibly.

## Examples

``` r
old <- set_decimal_context(decimal_context(precision = 5L))
set_decimal_context(old)
```
