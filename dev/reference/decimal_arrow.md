# Arrow interoperability

`decimal` vectors convert to and from Arrow decimal arrays exactly, in
both directions, when the arrow package is installed.

**Arrow to decimal.**
[`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
accepts an Arrow `Array` or `ChunkedArray`. A `decimal32()`,
`decimal64()`, `decimal128()` or `decimal256()` array converts exactly,
taking its scale from the Arrow type. An integer array of any width
converts exactly too. Other Arrow types convert to the equivalent R
vector first and follow the ordinary
[`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
rules.
[`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md)
applies the same conversion to every decimal field of a `Table` or
`RecordBatch`.

**Decimal to Arrow.** A `decimal` vector becomes a decimal field
wherever arrow infers types:
[`arrow::as_arrow_array()`](https://arrow.apache.org/docs/r/reference/as_arrow_array.html),
[`arrow::arrow_table()`](https://arrow.apache.org/docs/r/reference/table.html),
[`arrow::write_parquet()`](https://arrow.apache.org/docs/r/reference/write_parquet.html)
and
[`arrow::write_dataset()`](https://arrow.apache.org/docs/r/reference/write_dataset.html).
By default the field is an Arrow *extension type* whose storage is a
real `decimal128()` or `decimal256()` with the vector's scale and a
precision inferred from the values. Other readers see the storage, a
plain decimal column. In R the column returns as a `decimal` vector on
every read path,
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html),
[`arrow::read_parquet()`](https://arrow.apache.org/docs/r/reference/read_parquet.html)
and
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
included.
[`arrow_decimal_type()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_decimal_type.md)
pins a precision and scale.

Arrow's compute engine does not operate on extension columns, so
arrow-side arithmetic or filtering on such a column fails. To write a
plain field instead, pass a plain Arrow decimal type as `type` to
[`arrow::as_arrow_array()`](https://arrow.apache.org/docs/r/reference/as_arrow_array.html),
or set the option below. A plain field comes back from arrow's own
conversion as a `double` wearing the `decimal` class, because arrow
reapplies the column's recorded R attributes; the package refuses to
format such an object. Read those tables with
[`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md).

Infinities and NaNs have no Arrow decimal representation and raise an
error on conversion to Arrow.

## Options

`decimal.arrow_extension`: `TRUE` (the default) writes the extension
type; `FALSE` writes plain decimal fields everywhere.

## See also

[`vignette("arrow-decimal-types")`](https://pedrobtz.github.io/decimal/dev/articles/arrow-decimal-types.md).
