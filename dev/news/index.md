# Changelog

## decimal 0.1.1

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
