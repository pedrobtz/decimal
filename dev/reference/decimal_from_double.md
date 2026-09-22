# Controlled conversion from double

Decodes each IEEE 754 double to its exact decimal value, then quantizes
that value to the requested scale. This differs from parsing a character
literal such as `"0.1"`. Because the exact binary value of a double can
require dozens of fractional digits, a scale must be given explicitly or
configured with `options(decimal.default_scale = )`. Quantization uses
the active context's rounding and trap settings.

## Usage

``` r
decimal_from_double(x, scale = NULL)
```

## Arguments

- x:

  A double vector.

- scale:

  An integer scalar giving the number of fractional digits to store, or
  `NULL` to use `getOption("decimal.default_scale")`.

## Value

A `decimal` vector.

## Examples

``` r
decimal_from_double(0.1, scale = 20)
#> <decimal[1]>
#> [1] 0.10000000000000000555
decimal_from_double(c(0.5, 0.25), scale = 2)
#> <decimal[2]>
#> [1] 0.50 0.25
```
