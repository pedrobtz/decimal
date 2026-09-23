# decimal 0.1.1

- `decimal` vectors now convert to and from 'Arrow' decimal arrays directly.
  `as_decimal()` gained methods for `Array` and `ChunkedArray`. An Arrow
  decimal column of any width converts exactly, taking its scale from the
  Arrow type: Arrow's own decimal-to-string cast produces this package's
  canonical storage form once the exponent letter is folded to lowercase, so
  the strings need no re-parsing, and a property test guards that invariant.
  For 1,000,000 `decimal128()` values that takes 0.27s against
  0.78s for casting to string and calling `decimal()`. Arrow integer
  columns convert exactly at every width, including `int64` and `uint64`
  values a double cannot hold. Other Arrow types convert through the ordinary
  `as_decimal()` rules for the equivalent R vector.

- A `decimal` column now becomes an Arrow decimal field in
  `arrow::arrow_table()`, `arrow::write_parquet()` and
  `arrow::write_dataset()`. The field is an Arrow extension type whose storage
  is a real `decimal128()` or `decimal256()`, so Spark, DuckDB, pandas and
  other readers see a plain decimal column, while in R it returns as a
  `decimal` vector on every read path: `as.data.frame()`,
  `arrow::read_parquet()` and `dplyr::collect()` included. New
  `arrow_decimal_type()` pins a precision and scale for a column that will be
  appended to. Infinities and NaNs, which no Arrow decimal can represent, now
  raise an error on conversion instead of round-tripping through the 'vctrs'
  extension type; keep such a column as a string if you need them.

- Arrow's compute engine does not operate on extension columns. For arrow-side
  arithmetic or filtering on a decimal column, write a plain field by passing
  a plain Arrow decimal type to `arrow::as_arrow_array()` or by setting
  `options(decimal.arrow_extension = FALSE)`. A plain field comes back from
  arrow's own conversion as a double wearing the `decimal` class, because
  arrow reapplies the column's recorded R attributes; `format()` and
  `as.character()` now refuse such an object rather than print rounded
  values. New `arrow_as_data_frame()` converts an Arrow `Table` or
  `RecordBatch` to a data frame, reading plain decimal fields, including
  those in files written by other systems, as `decimal` vectors, and leaving
  every other column to arrow.

- Fixed memory leaks on the error paths of the native kernels. An R error
  raised while an `mpd_t` was allocated abandoned it, because R's error
  handling unwinds past the code that would have freed it. Parsing an invalid
  decimal string leaked every handle the operation held, and an allocation
  failure part-way through setting up an operation leaked the handles already
  allocated. An R allocation failure while storing a result string leaked the
  formatted text too; that text is now released under `R_UnwindProtect()`.

- `summary()` now works on `decimal` vectors. It reports the same six
  statistics as [summary.default()] plus an `NA's` count, computed in decimal
  arithmetic and returned as a `decimal` vector, so figures that a double would
  round are preserved. Quartiles use the type 7 definition, matching
  `stats::quantile()`.

- Fixed `is.na()`, `is.nan()`, `is.infinite()`, `is_qnan()` and `is_snan()`
  returning malformed logical vectors. They forwarded mpdecimal's flag bits --
  4 for `NaN`, 8 for `sNaN`, 2 for `Infinity` -- instead of `TRUE`. The results
  printed correctly and compared equal with `==`, but `which()` found no
  matching elements, `sum()` over-counted, and `identical()` was false against
  the obvious expectation.

- `DESCRIPTION` now declares `URL` and `BugReports`, so the CRAN page links to
  the source repository and the issue tracker.

- Building a `decimal` vector from character is substantially faster. The
  fractional-digit scan that `decimal()` performs on every element moved from R
  to C, which for 100,000 values takes construction from 1.13s to 0.05s when
  `scale` is supplied (about 22x) and from 2.28s to 0.05s when it is inferred
  (about 45x). Inferring the scale now costs the same as supplying it. This
  matters most when loading decimal data from 'Arrow' or a database, where the
  values arrive as a character vector in one call.

- New vignette `vignette("arrow-decimal-types")`, covering lossless conversion
  between `decimal` vectors and Arrow's `decimal128()` / `decimal256()` types
  in both directions, including chunked arrays, Parquet columns, and the cases
  Arrow decimals cannot represent.

- `format()` on a `decimal` vector no longer errors when it is given the
  `digits`, `na.encode` and `justify` arguments that `format.data.frame()`
  passes to every column. Decimal columns can now be printed inside a base
  `data.frame`. The arguments are tolerated rather than honored, so an exact
  value is never silently rounded for display, and any other unused argument
  is still an error.

# decimal 0.1.0

- Initial version
