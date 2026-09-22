# decimal (development version)

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
