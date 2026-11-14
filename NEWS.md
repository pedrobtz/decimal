# decimal 0.1.2

## Known issues

- Combining decimal Arrow columns of different scales or storage widths can
  silently misread values: 3.125 can come back as 31.25. This affects
  `arrow::concat_arrays()`, `arrow::concat_tables()` and
  `arrow::open_dataset()` over parts written separately, followed by
  `collect()` or `arrange()`, because arrow compares this package's extension
  types by name alone. Until this is fixed, pin one type with
  `arrow_decimal_type()` for every part that will be appended or combined
  (#37).

## Behaviour changes

- `as_decimal()` on a `decimal` vector without `scale` now returns it
  unchanged, rather than rescaling it to `decimal.default_scale`. Arrow
  decimal arrays likewise keep the scale of their Arrow type under that
  option, in `as_decimal()`, `arrow_as_data_frame()`, `as.data.frame()` and
  `arrow::read_parquet()`; before, with `default_scale = 1`, 1.25 and 2.75 read
  back as 1.2 and 2.8 (#43).

- `vctrs::vec_cast()` from a decimal to a coarser decimal
  type is now a lossy cast. When rounding would change a value it raises an
  error of class `vctrs_error_cast_lossy`, which `vctrs::allow_lossy_cast()`
  turns back into rounding; before, `vec_cast(decimal("1.55"),
  decimal("1.0"))` silently gave 1.6. Dropping trailing zeros, `NA` and
  special values still casts. This reaches functions that cast a replacement
  to an existing column: `tidyr::replace_na(decimal(c(NA, "1.5")),
  decimal("0.125"))` now errors rather than filling in 0.1. Combining vectors
  of different scales (`c()`, `vec_c()`, `rbind()`, `dplyr::bind_rows()`,
  `dplyr::if_else()`, `dplyr::coalesce()`) still takes the finer scale, and
  `as_decimal(x, scale = )` still rounds on request (#50).

- `vctrs::vec_cast()` from character to a decimal type now
  uses that type's scale (#51). `vec_c("1.123", "2", .ptype = decimal("1.0"))`
  used to return a vector labelled scale 1 that stored "1.123" and "2"
  unchanged. Text with fewer digits is padded exactly; text that would be
  rounded is a lossy cast, as for a coarser decimal, so `vec_cast("1.23",
  decimal())` now errors. `decimal()` and `as_decimal()` still infer the
  scale from the text.

## Bug fixes

- `as.double()` and casts to double are now correctly rounded. They went
  through R's internal string parser, which can be off by one unit in the
  last place (`decimal("83E25")`, `decimal("1e23", scale = 15)`), returned
  `Inf` for `1.7976931348623158E+308` instead of the largest double, and gave
  `NaN` or `Inf` once a value had more than about 4932 digits, as any value
  in a vector with `scale = 5000` does. Each result is now checked exactly
  against the midpoints to its neighbouring doubles, so it no longer depends
  on the platform's C library, and the conversion is tested against nearly
  4,000 values computed by Python (#45).

- `decimal()` and `as_decimal()` now refuse a value whose scale, its
  fractional digits minus its exponent, lies outside integer range, such as
  `"1E-2147483650"`, instead of storing it with the wrong scale. A value whose
  exponent alone is out of range but whose scale is not, such as
  `"1.5e+2147483648"`, is now accepted (#52).

- `adjusted()` now raises its "out of integer range" error for an adjusted
  exponent of -2147483648 instead of returning `NA` (#54).

- The native routines now check the type and length of every context
  argument and raise an error for a malformed one, instead of crashing R when
  called directly through `.Call()` with a zero-length vector (#41).

- Converting an Arrow column whose chunks carry different decimal storage now
  checks every chunk. Chunks that differ only in precision, such as dataset
  parts whose values had different magnitudes, now combine exactly, where
  arrow used to fail with "Array chunks must all be same type". Chunks that
  differ in scale or width raise an error of class
  `decimal_arrow_chunk_error` instead of being misread (#37).

- The bundled 'mpdecimal' now builds for WebAssembly (webR). Its configuration
  did not recognise the `wasm32` target and stopped with "unsupported
  platform".

- `floor()`, `ceiling()`, `trunc()`, `round()` and `signif()` now return
  infinities and quiet NaNs unchanged, payload included, and raise no signal,
  as base R and Python's `Decimal.to_integral_value()` do (#49). `signif()`
  turned them into `NA`, and the others trapped `invalid_operation`. A
  signaling NaN still raises `invalid_operation`. A `quantize()` trap on a
  special value no longer suggests raising the context precision.

- `mean()` on a `decimal` vector now honours `trim`, which it silently
  ignored (#53). It drops `floor(n * trim)` values from each end of the
  sorted vector, as `mean.default()` does, and returns the median once `trim`
  reaches 0.5.

- `is.unsorted()` now compares decimal values, honouring `strictly` and
  `na.rm`, instead of the stored text, which made
  `is.unsorted(decimal(c("9", "10")))` `TRUE` (#47). The "Decimal values"
  vignette now notes that `merge()` orders its result by a decimal key's text
  (#57).

- `pmax()` and `pmin()` now refuse a decimal argument whose scale is finer
  than the first argument's (#48). Base R gives the result the first
  argument's attributes, so `pmax(decimal(c("10", "9")), decimal("9.5"))`
  returned values held at one decimal place under a `scale` of zero. Bring
  the arguments to a common scale first, as in
  `pmax(as_decimal(x, scale = 1), y)`, or put the finest-scaled argument
  first. These functions are not generic, so with a non-decimal first
  argument they still return a character vector: write `pmax(x, 2L)` or
  `pmax(as_decimal(2L), x)` rather than `pmax(2L, x)`.

- New `?decimal-summaries` documents `sum()`, `prod()`, `mean()`, `min()`,
  `max()` and `range()` for `decimal` vectors, including a limit no method
  can lift (#42): R picks the method from the first argument alone, so when
  that is not a decimal, `min()`, `max()` and `range()` compare the stored
  text and return a character vector (`min(10L, decimal("9"))` is `"10"`),
  and `sum()` and `prod()` fail. Put a decimal first, `min(x, 10L)`, or
  convert the first argument, `min(as_decimal(10L), x)`.

- `options(decimal.default_scale = )` no longer leaks into the package's own
  conversions (#43). It is the default scale for `decimal()` and
  `as_decimal()` on character, integer and double input, but integer operands,
  rounding quantums, counts and constants picked it up too. Under
  `default_scale = 2`, `round(x, 3)` and `quantize(x, "0.001")` returned two
  digits and `x * 3L` gained two extra; under `default_scale = -2`, `x + 150L`
  added 200, `x * 3L` gave 0, `mean(x)` trapped `division_by_zero` and
  `summary()` reported no missing values; under `default_scale = 0`,
  `summary()` quartiles were wrong. Integers and character operands now
  convert exactly at the scale their value gives.

- `summary()` quartiles no longer depend on `options(digits)`, `OutDec`,
  `scipen` or the numeric locale (#44). The interpolation weight was built by
  formatting a double, so `options(digits = 1)` gave a 1st quartile of 1.8 for
  `c(1, 2, 4, 7.1)` instead of 1.75, and `OutDec = ","` raised an error. The
  weight is now chosen from exact text.

- `vctrs::vec_sort()`, `vctrs::vec_order()`, `dplyr::arrange(.locale = )` and
  `tidyr::expand()` now order negative decimals by value in every collation
  locale (#46). Under `en_US.UTF-8`, `vec_sort(decimal(c("-1.25", "-1.2")))`
  gave -1.20 before -1.25, because the order proxy was text that sorted
  correctly only byte by byte. It is now an integer rank. `sort()`, `order()`,
  `rank()` and `dplyr::arrange()` without `.locale` were already correct.

- `x[[i]] <- value` now widens `x` to the scale of a finer `value`, as
  `x[i] <- value` always did, instead of silently rounding: `y[[2]] <-
  decimal("9.123")` on a scale-2 `y` used to store 9.12 (#50).

- `arrow::as_arrow_array()` now refuses a value wider than a pinned decimal
  type with an error of class `decimal_arrow_precision_error`, naming the
  digits the value needs and the type's precision. Arrow's own cast silently
  wrapped a value too wide for the type's integer width: 39 nines pinned to
  `decimal128(38, 0)` became a negative number, and `2^128 + 7` pinned to
  `decimal128(5, 0)` became 7 (#38).

- A `decimal` vector with a negative scale is now written to Arrow at storage
  scale 0, which Parquet accepts and which holds the same values exactly; it
  reads back with scale 0, not its original negative scale. Before,
  `arrow::write_parquet()` and `arrow::write_dataset()` rejected the column
  only after opening the destination, emptying an existing file or leaving a
  0-byte part. `arrow_decimal_type()` now validates its arguments and refuses
  a scale above the precision, which Parquet rejects the same way. A table
  that already holds such a field can still empty the destination file,
  because arrow opens it before checking; this is documented in
  `?decimal_arrow` (#39).

- Documented that negative zero loses its sign through Arrow: an Arrow decimal
  has a single zero, so `-0.00` reads back as `0.00` (#40).

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

- `format()` on a `decimal` vector now accepts the extra arguments that table
  printers pass to every column, such as `digits`, `na.encode` and `justify`
  from `format.data.frame()`, `timezone` from 'data.table' and `trim` from
  `knitr::kable()`, so decimal columns print inside a base `data.frame`, a
  `data.table` and a `kable()` table. The arguments are ignored rather than
  honored, so an exact value is never silently rounded for display. Arguments
  that would change how a number is written, such as `nsmall`, `scientific`
  and `big.mark`, are an error.

- Fixed `rbind()` on data frames with `decimal` columns, which always failed
  with "Can't assign to elements past the end". Assigning past the end of a
  `decimal` vector now grows it with missing values, as it does a base vector,
  and binding columns of different scales takes the finer one. `x[] <- value`
  now replaces every element instead of failing.

- `match()`, `%in%` and base `merge()` now compare `decimal` values rather
  than their stored text, so `2.5` matches `2.50`, as `==` already said.
  Whole numbers still match integers and strings: `decimal("20") %in% 20L`
  stays `TRUE`.

- New section in `vignette("decimal-values")` on decimal columns in a
  'data.table': what works, and workarounds for the operations data.table runs
  on the stored text instead of the values, such as sorting and grouped
  `min()` and `max()`.

# decimal 0.1.0

- Initial version
