# Classify decimal values

`number_class()` returns the General Decimal Arithmetic class of each
value. Possible finite classes include `"+Normal"`, `"-Normal"`,
`"+Subnormal"`, `"-Subnormal"`, `"+Zero"`, and `"-Zero"`; infinities and
NaNs have their corresponding class names. Normal and subnormal classes
depend on the active decimal context.

## Usage

``` r
number_class(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

A character vector with the same length as `x`. R missing values produce
`NA_character_`.

## Examples

``` r
number_class(decimal(c("1", "-0", "Infinity", "NaN")))
#> [1] "+Normal"   "-Zero"     "+Infinity" "NaN"      
```
