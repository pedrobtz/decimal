# Remove unnecessary trailing zeros

`normalize()` reduces each finite value to its shortest equivalent
decimal representation, then chooses the finest scale required by any
element so the result remains a valid shared-scale decimal vector.
Special values pass through unchanged.

## Usage

``` r
normalize(x)
```

## Arguments

- x:

  A decimal-compatible vector.

## Value

A normalized `decimal` vector.

## Examples

``` r
normalize(decimal(c("1.2300", "1.2")))
#> <decimal[2]>
#> [1] 1.23 1.20
```
