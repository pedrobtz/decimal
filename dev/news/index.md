# Changelog

## decimal (development version)

## decimal 0.1.1

CRAN release: 2026-09-23

- `decimal` vectors now convert to and from ‘Arrow’ decimal arrays
  directly.
  [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
  gained methods for `Array` and `ChunkedArray`. An Arrow decimal column
  of any width converts exactly, taking its scale from the Arrow type:
  Arrow’s own decimal-to-string cast produces this package’s canonical
  storage form once the exponent letter is folded to lowercase, so the
  strings need no re-parsing, and a property test guards that invariant.
  For 1,000,000
  [`decimal128()`](https://arrow.apache.org/docs/r/reference/data-type.html)
  values that takes 0.27s against 0.78s for casting to string and
  calling
  [`decimal()`](https://pedrobtz.github.io/decimal/dev/reference/decimal.md).
  Arrow integer columns convert exactly at every width, including
  `int64` and `uint64` values a double cannot hold. Other Arrow types
  convert through the ordinary
  [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
  rules for the equivalent R vector.

- A `decimal` column now becomes an Arrow decimal field in
  [`arrow::arrow_table()`](https://arrow.apache.org/docs/r/reference/table.html),
  [`arrow::write_parquet()`](https://arrow.apache.org/docs/r/reference/write_parquet.html)
  and
  [`arrow::write_dataset()`](https://arrow.apache.org/docs/r/reference/write_dataset.html).
  The field is an Arrow extension type whose storage is a real
  [`decimal128()`](https://arrow.apache.org/docs/r/reference/data-type.html)
  or
  [`decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html),
  so Spark, DuckDB, pandas and other readers see a plain decimal column,
  while in R it returns as a `decimal` vector on every read path:
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html),
  [`arrow::read_parquet()`](https://arrow.apache.org/docs/r/reference/read_parquet.html)
  and
  [`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
  included. New
  [`arrow_decimal_type()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_decimal_type.md)
  pins a precision and scale for a column that will be appended to.
  Infinities and NaNs, which no Arrow decimal can represent, now raise
  an error on conversion instead of round-tripping through the ‘vctrs’
  extension type; keep such a column as a string if you need them.

- Arrow’s compute engine does not operate on extension columns. For
  arrow-side arithmetic or filtering on a decimal column, write a plain
  field by passing a plain Arrow decimal type to
  [`arrow::as_arrow_array()`](https://arrow.apache.org/docs/r/reference/as_arrow_array.html)
  or by setting `options(decimal.arrow_extension = FALSE)`. A plain
  field comes back from arrow’s own conversion as a double wearing the
  `decimal` class, because arrow reapplies the column’s recorded R
  attributes; [`format()`](https://rdrr.io/r/base/format.html) and
  [`as.character()`](https://rdrr.io/r/base/character.html) now refuse
  such an object rather than print rounded values. New
  [`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md)
  converts an Arrow `Table` or `RecordBatch` to a data frame, reading
  plain decimal fields, including those in files written by other
  systems, as `decimal` vectors, and leaving every other column to
  arrow.

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
  now accepts the extra arguments that table printers pass to every
  column, such as `digits`, `na.encode` and `justify` from
  [`format.data.frame()`](https://rdrr.io/r/base/format.html),
  `timezone` from ‘data.table’ and `trim` from
  [`knitr::kable()`](https://rdrr.io/pkg/knitr/man/kable.html), so
  decimal columns print inside a base `data.frame`, a `data.table` and a
  `kable()` table. The arguments are ignored rather than honored, so an
  exact value is never silently rounded for display. Arguments that
  would change how a number is written, such as `nsmall`, `scientific`
  and `big.mark`, are an error.

- Fixed [`rbind()`](https://rdrr.io/r/base/cbind.html) on data frames
  with `decimal` columns, which always failed with “Can’t assign to
  elements past the end”. Assigning past the end of a `decimal` vector
  now grows it with missing values, as it does a base vector, and
  binding columns of different scales takes the finer one.
  `x[] <- value` now replaces every element instead of failing.

- [`match()`](https://rdrr.io/r/base/match.html), `%in%` and base
  [`merge()`](https://rdrr.io/r/base/merge.html) now compare `decimal`
  values rather than their stored text, so `2.5` matches `2.50`, as `==`
  already said. Whole numbers still match integers and strings:
  `decimal("20") %in% 20L` stays `TRUE`.

- New section in
  [`vignette("decimal-values")`](https://pedrobtz.github.io/decimal/dev/articles/decimal-values.md)
  on decimal columns in a ‘data.table’: what works, and workarounds for
  the operations data.table runs on the stored text instead of the
  values, such as sorting and grouped
  [`min()`](https://rdrr.io/r/base/Extremes.html) and
  [`max()`](https://rdrr.io/r/base/Extremes.html).

## decimal 0.1.0

CRAN release: 2026-08-24

- Initial version
