# Arithmetic for decimal vectors

Implements the vctrs arithmetic group generic
([`vctrs::vec_arith()`](https://vctrs.r-lib.org/reference/vec_arith.html))
for decimal vectors. It is not normally called directly; it dispatches
when decimals are combined with operators such as `+`, `-`, `*`, and
`/`.

## Usage

``` r
# S3 method for class 'decimal'
vec_arith(op, x, y, ...)
```

## Arguments

- op:

  A length-one character vector giving the arithmetic operator.

- x, y:

  A pair of vectors, at least one of which is a `decimal`.

- ...:

  Passed on to methods.

## Value

A `decimal` vector with the result of the operation.

## Examples

``` r
decimal("1.5") + decimal("2.5")
#> <decimal[1]>
#> [1] 4.0
decimal(c("10", "20")) * 3L
#> <decimal[2]>
#> [1] 30 60
```
