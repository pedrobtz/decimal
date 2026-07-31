# Test whether an object is a decimal vector

`is_decimal()` reports whether `x` inherits from the `decimal` vector
class. It does not attempt to parse or convert other objects.

## Usage

``` r
is_decimal(x)
```

## Arguments

- x:

  An object to test.

## Value

A single logical value.

## Examples

``` r
is_decimal(decimal("1.5"))
#> [1] TRUE
```
