# decimal 0.1.1

- `decimal` vectors now convert to and from 'Arrow' decimal arrays directly.
  `as_decimal()` gained methods for `Array` and `ChunkedArray`: an Arrow
  `decimal128()` or `decimal256()` column converts exactly, taking its scale
  from the Arrow type, and several times faster than casting to string and
  re-parsing (0.20s against 1.44s for 1,000,000 values, which is the cost of
  the lossy `as.vector()` double path). Arrow's own
  decimal-to-string cast produces this package's canonical storage form once
  the exponent letter is folded to lowercase, so the strings need no
  re-parsing; a property test guards that invariant. Arrays of any other type
  convert through the ordinary `as_decimal()` rules for the equivalent R
  vector.

- A `decimal` column now becomes a real Arrow decimal field in
  `arrow::arrow_table()`, `arrow::write_parquet()` and `arrow::write_dataset()`
  rather than a string column carrying 'vctrs' metadata, so Spark, DuckDB,
  pandas and other readers see a decimal. The type is `decimal128()` when the
  inferred precision fits in 38 digits and `decimal256()` up to 76; pass `type`
  to pin a wider one for a column that will be appended to. Two behavior
  changes follow. Infinities and NaNs, which no Arrow decimal can represent,
  now raise an error instead of round-tripping through the 'vctrs' extension
  type; keep such a column as a string if you need them. And because 'Arrow'
  reapplies an R column's attributes on the way back, `as.data.frame()` on a
  table built from a `decimal` column returns a double wearing the `decimal`
  class -- use `arrow_as_data_frame()` instead.

- New `arrow_as_data_frame()` converts an Arrow `Table` or `RecordBatch` to a
  data frame, reading decimal fields as `decimal` vectors instead of letting
  `as.data.frame()` round them through `double`. Every other column is
  converted by 'Arrow' as usual.

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
  `data.frame`. The arguments are tolerated rather than honoured, so an exact
  value is never silently rounded for display, and any other unused argument
  is still an error.

# decimal 0.1.0

- Initial version
