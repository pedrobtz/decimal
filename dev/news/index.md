# Changelog

## decimal 0.1.1

- `decimal` vectors now convert to and from ‘Arrow’ decimal arrays
  directly.
  [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
  gained methods for `Array` and `ChunkedArray`: an Arrow
  [`decimal128()`](https://arrow.apache.org/docs/r/reference/data-type.html)
  or
  [`decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html)
  column converts exactly, taking its scale from the Arrow type, and
  several times faster than casting to string and re-parsing (0.20s
  against 1.44s for 1,000,000 values, which is the cost of the lossy
  [`as.vector()`](https://rdrr.io/r/base/vector.html) double path).
  Arrow’s own decimal-to-string cast produces this package’s canonical
  storage form once the exponent letter is folded to lowercase, so the
  strings need no re-parsing; a property test guards that invariant.
  Arrays of any other type convert through the ordinary
  [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
  rules for the equivalent R vector.

- A `decimal` column now becomes a real Arrow decimal field in
  [`arrow::arrow_table()`](https://arrow.apache.org/docs/r/reference/table.html),
  [`arrow::write_parquet()`](https://arrow.apache.org/docs/r/reference/write_parquet.html)
  and
  [`arrow::write_dataset()`](https://arrow.apache.org/docs/r/reference/write_dataset.html)
  rather than a string column carrying ‘vctrs’ metadata, so Spark,
  DuckDB, pandas and other readers see a decimal. The type is
  [`decimal128()`](https://arrow.apache.org/docs/r/reference/data-type.html)
  when the inferred precision fits in 38 digits and
  [`decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html)
  up to 76; pass `type` to pin a wider one for a column that will be
  appended to. Two behavior changes follow. Infinities and NaNs, which
  no Arrow decimal can represent, now raise an error instead of
  round-tripping through the ‘vctrs’ extension type; keep such a column
  as a string if you need them. And because ‘Arrow’ reapplies an R
  column’s attributes on the way back,
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) on a
  table built from a `decimal` column returns a double wearing the
  `decimal` class – use
  [`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md)
  instead.

- New
  [`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md)
  converts an Arrow `Table` or `RecordBatch` to a data frame, reading
  decimal fields as `decimal` vectors instead of letting
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) round
  them through `double`. Every other column is converted by ‘Arrow’ as
  usual.

- Fixed memory leaks on the error paths of the native kernels. An R
  error raised while an `mpd_t` was allocated abandoned it, because R’s
  error handling unwinds past the code that would have freed it. Parsing
  an invalid decimal string leaked every handle the operation held, and
  an allocation failure part-way through setting up an operation leaked
  the handles already allocated. An R allocation failure while storing a
  result string leaked the formatted text too; that text is now released
  under `R_UnwindProtect()`.

- [`summary()`](https://rdrr.io/r/base/summary.html) now works on
  `decimal` vectors. It reports the same six statistics as
  \[summary.default()\] plus an `NA's` count, computed in decimal
  arithmetic and returned as a `decimal` vector, so figures that a
  double would round are preserved. Quartiles use the type 7 definition,
  matching [`stats::quantile()`](https://rdrr.io/r/stats/quantile.html).

- Fixed [`is.na()`](https://rdrr.io/r/base/NA.html),
  [`is.nan()`](https://rdrr.io/r/base/is.finite.html),
  [`is.infinite()`](https://rdrr.io/r/base/is.finite.html),
  [`is_qnan()`](https://pedrobtz.github.io/decimal/dev/reference/is_qnan.md)
  and
  [`is_snan()`](https://pedrobtz.github.io/decimal/dev/reference/is_snan.md)
  returning malformed logical vectors. They forwarded mpdecimal’s flag
  bits – 4 for `NaN`, 8 for `sNaN`, 2 for `Infinity` – instead of
  `TRUE`. The results printed correctly and compared equal with `==`,
  but [`which()`](https://rdrr.io/r/base/which.html) found no matching
  elements, [`sum()`](https://rdrr.io/r/base/sum.html) over-counted, and
  [`identical()`](https://rdrr.io/r/base/identical.html) was false
  against the obvious expectation.

- `DESCRIPTION` now declares `URL` and `BugReports`, so the CRAN page
  links to the source repository and the issue tracker.

- Building a `decimal` vector from character is substantially faster.
  The fractional-digit scan that
  [`decimal()`](https://pedrobtz.github.io/decimal/dev/reference/decimal.md)
  performs on every element moved from R to C, which for 100,000 values
  takes construction from 1.13s to 0.05s when `scale` is supplied (about
  22x) and from 2.28s to 0.05s when it is inferred (about 45x).
  Inferring the scale now costs the same as supplying it. This matters
  most when loading decimal data from ‘Arrow’ or a database, where the
  values arrive as a character vector in one call.

- New vignette
  [`vignette("arrow-decimal-types")`](https://pedrobtz.github.io/decimal/dev/articles/arrow-decimal-types.md),
  covering lossless conversion between `decimal` vectors and Arrow’s
  [`decimal128()`](https://arrow.apache.org/docs/r/reference/data-type.html)
  /
  [`decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html)
  types in both directions, including chunked arrays, Parquet columns,
  and the cases Arrow decimals cannot represent.

- [`format()`](https://rdrr.io/r/base/format.html) on a `decimal` vector
  no longer errors when it is given the `digits`, `na.encode` and
  `justify` arguments that
  [`format.data.frame()`](https://rdrr.io/r/base/format.html) passes to
  every column. Decimal columns can now be printed inside a base
  `data.frame`. The arguments are tolerated rather than honoured, so an
  exact value is never silently rounded for display, and any other
  unused argument is still an error.

## decimal 0.1.0

CRAN release: 2026-08-24

- Initial version
