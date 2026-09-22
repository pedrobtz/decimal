# Convert an Arrow table to a data frame, keeping decimal columns exact

[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) on an
Arrow `Table` or `RecordBatch` converts decimal columns through
`double`, which silently drops digits beyond the seventeenth.
`arrow_as_data_frame()` converts the decimal columns with
[`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
instead, so they arrive as `decimal` vectors with the scale declared by
their Arrow type. Every other column is converted by arrow in the usual
way.

## Usage

``` r
arrow_as_data_frame(x)
```

## Arguments

- x:

  An Arrow `Table` or `RecordBatch`.

## Value

A data frame whose decimal columns are `decimal` vectors.

## Examples

``` r
if (requireNamespace("arrow", quietly = TRUE)) {
  tab <- arrow::arrow_table(
    id = 1:2,
    amount = arrow::Array$create(
      c("100.05", "99999999999999999999.99")
    )$cast(arrow::decimal128(25, 2))
  )
  arrow_as_data_frame(tab)
}
#>   id                  amount
#> 1  1                  100.05
#> 2  2 99999999999999999999.99
```
