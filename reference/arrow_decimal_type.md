# Arrow type for a decimal column

Builds the Arrow extension type this package writes `decimal` vectors
as, with a chosen precision and scale rather than ones inferred from the
values. Use it to pin the type of a column that will be appended to, for
example through the `schema` argument of
[`arrow::arrow_table()`](https://arrow.apache.org/docs/r/reference/table.html)
or the `type` argument of
[`arrow::as_arrow_array()`](https://arrow.apache.org/docs/r/reference/as_arrow_array.html).
The storage is
[`arrow::decimal128()`](https://arrow.apache.org/docs/r/reference/data-type.html)
up to 38 digits of precision and
[`arrow::decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html)
above that.

## Usage

``` r
arrow_decimal_type(precision, scale = 0L)
```

## Arguments

- precision:

  Total number of digits, at most 76.

- scale:

  Number of fractional digits.

## Value

An Arrow extension type.

## See also

[decimal_arrow](https://pedrobtz.github.io/decimal/reference/decimal_arrow.md)
for how the type behaves.

## Examples

``` r
if (requireNamespace("arrow", quietly = TRUE)) {
  arrow_decimal_type(20, 2)
  arrow::as_arrow_array(decimal("1.25"), type = arrow_decimal_type(20, 2))
}
#> ExtensionArray
#> <decimal<decimal128(20, 2)>>
#> [
#>   1.25
#> ]
```
