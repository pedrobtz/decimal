# Changelog

## decimal (development version)

### Known issues

- Combining decimal Arrow columns of different scales or storage widths
  can silently misread values: 3.125 can come back as 31.25. This
  affects
  [`arrow::concat_arrays()`](https://arrow.apache.org/docs/r/reference/concat_arrays.html),
  [`arrow::concat_tables()`](https://arrow.apache.org/docs/r/reference/concat_tables.html)
  and
  [`arrow::open_dataset()`](https://arrow.apache.org/docs/r/reference/open_dataset.html)
  over parts written separately, followed by
  [`collect()`](https://dplyr.tidyverse.org/reference/compute.html) or
  [`arrange()`](https://dplyr.tidyverse.org/reference/arrange.html),
  because arrow compares this package’s extension types by name alone.
  Until this is fixed, pin one type with
  [`arrow_decimal_type()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_decimal_type.md)
  for every part that will be appended or combined
  ([\#37](https://github.com/pedrobtz/decimal/issues/37)).

### Bug fixes

- [`as.double()`](https://rdrr.io/r/base/double.html) and casts to
  double are now correctly rounded. They went through R’s internal
  string parser, which can be off by one unit in the last place
  (`decimal("83E25")`, `decimal("1e23", scale = 15)`), returned `Inf`
  for `1.7976931348623158E+308` instead of the largest double, and gave
  `NaN` or `Inf` once a value had more than about 4932 digits, as any
  value in a vector with `scale = 5000` does. Each result is now checked
  exactly against the midpoints to its neighbouring doubles, so it no
  longer depends on the platform’s C library, and the conversion is
  tested against nearly 4,000 values computed by Python
  ([\#45](https://github.com/pedrobtz/decimal/issues/45)).

- [`decimal()`](https://pedrobtz.github.io/decimal/dev/reference/decimal.md)
  and
  [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
  now refuse a value whose scale, its fractional digits minus its
  exponent, lies outside integer range, such as `"1E-2147483650"`,
  instead of storing it with the wrong scale. A value whose exponent
  alone is out of range but whose scale is not, such as
  `"1.5e+2147483648"`, is now accepted
  ([\#52](https://github.com/pedrobtz/decimal/issues/52)).

- [`adjusted()`](https://pedrobtz.github.io/decimal/dev/reference/adjusted.md)
  now raises its “out of integer range” error for an adjusted exponent
  of -2147483648 instead of returning `NA`
  ([\#54](https://github.com/pedrobtz/decimal/issues/54)).

- The native routines now check the type and length of every context
  argument and raise an error for a malformed one, instead of crashing R
  when called directly through
  [`.Call()`](https://rdrr.io/r/base/CallExternal.html) with a
  zero-length vector
  ([\#41](https://github.com/pedrobtz/decimal/issues/41)).

- Converting an Arrow column whose chunks carry different decimal
  storage now checks every chunk. Chunks that differ only in precision,
  such as dataset parts whose values had different magnitudes, now
  combine exactly, where arrow used to fail with “Array chunks must all
  be same type”. Chunks that differ in scale or width raise an error of
  class `decimal_arrow_chunk_error` instead of being misread
  ([\#37](https://github.com/pedrobtz/decimal/issues/37)).

- The bundled ‘mpdecimal’ now builds for WebAssembly (webR). Its
  configuration did not recognise the `wasm32` target and stopped with
  “unsupported platform”.

- [`floor()`](https://rdrr.io/r/base/Round.html),
  [`ceiling()`](https://rdrr.io/r/base/Round.html),
  [`trunc()`](https://rdrr.io/r/base/Round.html),
  [`round()`](https://rdrr.io/r/base/Round.html) and
  [`signif()`](https://rdrr.io/r/base/Round.html) now return infinities
  and quiet NaNs unchanged, payload included, and raise no signal, as
  base R and Python’s `Decimal.to_integral_value()` do
  ([\#49](https://github.com/pedrobtz/decimal/issues/49)).
  [`signif()`](https://rdrr.io/r/base/Round.html) turned them into `NA`,
  and the others trapped `invalid_operation`. A signaling NaN still
  raises `invalid_operation`. A
  [`quantize()`](https://pedrobtz.github.io/decimal/dev/reference/quantize.md)
  trap on a special value no longer suggests raising the context
  precision.

- [`mean()`](https://rdrr.io/r/base/mean.html) on a `decimal` vector now
  honours `trim`, which it silently ignored
  ([\#53](https://github.com/pedrobtz/decimal/issues/53)). It drops
  `floor(n * trim)` values from each end of the sorted vector, as
  [`mean.default()`](https://rdrr.io/r/base/mean.html) does, and returns
  the median once `trim` reaches 0.5.

- [`is.unsorted()`](https://rdrr.io/r/base/is.unsorted.html) now
  compares decimal values, honouring `strictly` and `na.rm`, instead of
  the stored text, which made `is.unsorted(decimal(c("9", "10")))`
  `TRUE` ([\#47](https://github.com/pedrobtz/decimal/issues/47)). The
  “Decimal values” vignette now notes that
  [`merge()`](https://rdrr.io/r/base/merge.html) orders its result by a
  decimal key’s text
  ([\#57](https://github.com/pedrobtz/decimal/issues/57)).

- [`pmax()`](https://rdrr.io/r/base/Extremes.html) and
  [`pmin()`](https://rdrr.io/r/base/Extremes.html) now refuse a decimal
  argument whose scale is finer than the first argument’s
  ([\#48](https://github.com/pedrobtz/decimal/issues/48)). Base R gives
  the result the first argument’s attributes, so
  `pmax(decimal(c("10", "9")), decimal("9.5"))` returned values held at
  one decimal place under a `scale` of zero. Bring the arguments to a
  common scale first, as in `pmax(as_decimal(x, scale = 1), y)`, or put
  the finest-scaled argument first. These functions are not generic, so
  with a non-decimal first argument they still return a character
  vector: write `pmax(x, 2L)` or `pmax(as_decimal(2L), x)` rather than
  `pmax(2L, x)`.

- New `?decimal-summaries` documents
  [`sum()`](https://rdrr.io/r/base/sum.html),
  [`prod()`](https://rdrr.io/r/base/prod.html),
  [`mean()`](https://rdrr.io/r/base/mean.html),
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html) and
  [`range()`](https://rdrr.io/r/base/range.html) for `decimal` vectors,
  including a limit no method can lift
  ([\#42](https://github.com/pedrobtz/decimal/issues/42)): R picks the
  method from the first argument alone, so when that is not a decimal,
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html) and
  [`range()`](https://rdrr.io/r/base/range.html) compare the stored text
  and return a character vector (`min(10L, decimal("9"))` is `"10"`),
  and [`sum()`](https://rdrr.io/r/base/sum.html) and
  [`prod()`](https://rdrr.io/r/base/prod.html) fail. Put a decimal
  first, `min(x, 10L)`, or convert the first argument,
  `min(as_decimal(10L), x)`.

- `options(decimal.default_scale = )` no longer leaks into the package’s
  own conversions
  ([\#43](https://github.com/pedrobtz/decimal/issues/43)). It is the
  default scale for
  [`decimal()`](https://pedrobtz.github.io/decimal/dev/reference/decimal.md)
  and
  [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
  on character, integer and double input, but integer operands, rounding
  quantums, counts and constants picked it up too. Under
  `default_scale = 2`, `round(x, 3)` and `quantize(x, "0.001")` returned
  two digits and `x * 3L` gained two extra; under `default_scale = -2`,
  `x + 150L` added 200, `x * 3L` gave 0, `mean(x)` trapped
  `division_by_zero` and
  [`summary()`](https://rdrr.io/r/base/summary.html) reported no missing
  values; under `default_scale = 0`,
  [`summary()`](https://rdrr.io/r/base/summary.html) quartiles were
  wrong. Integers and character operands now convert exactly at the
  scale their value gives.

- [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
  on a `decimal` vector without `scale` now returns it unchanged, rather
  than rescaling it to `decimal.default_scale`. Arrow decimal arrays
  likewise keep the scale of their Arrow type under that option, in
  [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md),
  [`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md),
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) and
  [`arrow::read_parquet()`](https://arrow.apache.org/docs/r/reference/read_parquet.html);
  before, with `default_scale = 1`, 1.25 and 2.75 read back as 1.2 and
  2.8 ([\#43](https://github.com/pedrobtz/decimal/issues/43)).

- [`summary()`](https://rdrr.io/r/base/summary.html) quartiles no longer
  depend on `options(digits)`, `OutDec`, `scipen` or the numeric locale
  ([\#44](https://github.com/pedrobtz/decimal/issues/44)). The
  interpolation weight was built by formatting a double, so
  `options(digits = 1)` gave a 1st quartile of 1.8 for `c(1, 2, 4, 7.1)`
  instead of 1.75, and `OutDec = ","` raised an error. The weight is now
  chosen from exact text.

- [`arrow::as_arrow_array()`](https://arrow.apache.org/docs/r/reference/as_arrow_array.html)
  now refuses a value wider than a pinned decimal type with an error of
  class `decimal_arrow_precision_error`, naming the digits the value
  needs and the type’s precision. Arrow’s own cast silently wrapped a
  value too wide for the type’s integer width: 39 nines pinned to
  `decimal128(38, 0)` became a negative number, and `2^128 + 7` pinned
  to `decimal128(5, 0)` became 7
  ([\#38](https://github.com/pedrobtz/decimal/issues/38)).

- A `decimal` vector with a negative scale is now written to Arrow at
  storage scale 0, which Parquet accepts and which holds the same values
  exactly; it reads back with scale 0, not its original negative scale.
  Before,
  [`arrow::write_parquet()`](https://arrow.apache.org/docs/r/reference/write_parquet.html)
  and
  [`arrow::write_dataset()`](https://arrow.apache.org/docs/r/reference/write_dataset.html)
  rejected the column only after opening the destination, emptying an
  existing file or leaving a 0-byte part.
  [`arrow_decimal_type()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_decimal_type.md)
  now validates its arguments and refuses a scale above the precision,
  which Parquet rejects the same way. A table that already holds such a
  field can still empty the destination file, because arrow opens it
  before checking; this is documented in
  [`?decimal_arrow`](https://pedrobtz.github.io/decimal/dev/reference/decimal_arrow.md)
  ([\#39](https://github.com/pedrobtz/decimal/issues/39)).

- Documented that negative zero loses its sign through Arrow: an Arrow
  decimal has a single zero, so `-0.00` reads back as `0.00`
  ([\#40](https://github.com/pedrobtz/decimal/issues/40)).

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
