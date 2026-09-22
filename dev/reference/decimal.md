# Construct decimal vectors

`decimal()` creates an immutable decimal vector backed by exact strings,
at a single shared scale (number of fractional digits) for the whole
vector. Character and integer inputs are parsed exactly. Promotion to a
finer shared scale only appends zeros and is context-free; a requested
coarser scale quantizes using the active context. Double inputs are
decoded from their exact IEEE 754 binary value and require either an
explicit `scale` or the `decimal.default_scale` option before
quantization.

## Usage

``` r
decimal(x = character(), scale = NULL)
```

## Arguments

- x:

  A decimal, character, integer, or double vector.

- scale:

  An integer scalar giving the number of fractional digits to store.
  `NULL` uses the `decimal.default_scale` option when set, then falls
  back to input-specific inference. Negative values round into the
  integer part (e.g. `scale = -2` rounds to the nearest hundred).

## Value

A `decimal` vector.

## Details

When `scale` is `NULL`, `getOption("decimal.default_scale")` is used
when set. Otherwise, character input infers the largest number of
fractional digits present in `x`, and integer input uses scale zero.
Because scale is a property of the vector, not the element,
`decimal("1.2") == decimal("1.20")`, and combining them yields one
uniformly scaled vector.

## Examples

``` r
decimal(c("1.20", "2.30"))
#> <decimal[2]>
#> [1] 1.20 2.30
```
