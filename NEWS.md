# decimal 0.1.1

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
