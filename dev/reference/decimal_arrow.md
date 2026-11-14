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
error on conversion to Arrow. A value wider than a pinned type raises an
error of class `decimal_arrow_precision_error`, never a rounded or
wrapped value. Negative zero has no Arrow representation either and
becomes zero: `-0.00` reads back as `0.00`.

Arrow accepts a negative scale but Parquet does not, so a vector with a
negative scale is written at scale 0, which holds the same values
exactly, and reads back with scale 0. A negative scale pinned through
`type` is kept in memory, but
[`arrow::write_parquet()`](https://arrow.apache.org/docs/r/reference/write_parquet.html)
rejects such a column only after it has opened, and so emptied, the
destination file; the same holds for a table already carrying a decimal
field whose scale exceeds its precision.

## Known issue

combining columns of different types: Combining decimal extension
columns that arrow typed differently, with different scales or storage
widths, can silently misread values (#37). This includes
[`arrow::concat_arrays()`](https://arrow.apache.org/docs/r/reference/concat_arrays.html),
[`arrow::concat_tables()`](https://arrow.apache.org/docs/r/reference/concat_tables.html)
and
[`arrow::open_dataset()`](https://arrow.apache.org/docs/r/reference/open_dataset.html)
over parts written separately, followed by
[`collect()`](https://dplyr.tidyverse.org/reference/compute.html) or
[`arrange()`](https://dplyr.tidyverse.org/reference/arrange.html). arrow
compares two of this package's extension types by name alone, so it can
reinterpret one part's stored integers at the other part's scale: 3.125
reads back as 31.25.

**Workaround:** pin one type with
[`arrow_decimal_type()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_decimal_type.md)
for every part that will be appended or combined.

The package checks every chunk it converts and raises an error of class
`decimal_arrow_chunk_error` for a column whose chunks differ in scale or
width. Chunks that differ only in precision are combined exactly. A
misread that arrow's own kernels have already produced, as in
[`arrow::concat_arrays()`](https://arrow.apache.org/docs/r/reference/concat_arrays.html),
cannot be detected.

## Options

`decimal.arrow_extension`: `TRUE` (the default) writes the extension
type; `FALSE` writes plain decimal fields everywhere.

## See also

[`vignette("arrow-decimal-types")`](https://pedrobtz.github.io/decimal/dev/articles/arrow-decimal-types.md).
