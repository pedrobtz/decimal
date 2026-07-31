# Convert a vector to decimal

`as_decimal()` is the conversion generic for decimal vectors. Character
values are parsed exactly, integer values are converted exactly, and
existing decimal vectors are returned or rescaled. Promotion to a finer
shared scale is exact and context-free; reduction to a coarser scale is
quantized. Double values are decoded from their exact IEEE 754
representation and therefore require an explicit or globally configured
scale before quantization.

## Usage

``` r
as_decimal(x, scale = NULL)

# S3 method for class 'decimal'
as_decimal(x, scale = NULL)

# S3 method for class 'character'
as_decimal(x, scale = NULL)

# S3 method for class 'integer'
as_decimal(x, scale = NULL)

# S3 method for class 'numeric'
as_decimal(x, scale = NULL)

# Default S3 method
as_decimal(x, scale = NULL)
```

## Arguments

- x:

  A decimal, character, integer, or double vector.

- scale:

  An integer scalar giving the number of fractional digits to store, or
  `NULL` to use the global default or input-specific inference.

## Value

A `decimal` vector.

## Details

When `scale` is `NULL`, `getOption("decimal.default_scale")` is used
when set. Without that option, character input uses the largest number
of fractional digits found in the input, integer input uses scale zero,
and double input raises an error. Quantization uses the active
[`decimal_context()`](https://pedrobtz.github.io/decimal/reference/decimal_context.md).

## Examples

``` r
as_decimal(c("1.2", "3.45"))
#> <decimal[2]>
#> [1] 1.20 3.45
```
