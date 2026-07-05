# decimal 0.1.0

- First functional release of arbitrary-precision decimal vectors for R.
- `as_decimal()` and `decimal_from_double()` now use the opt-in
  `decimal.default_scale` option when `scale` is not supplied. Explicit scale
  arguments continue to take precedence.
- Added exact decimal construction, at a single shared scale (number of
  fractional digits) per vector, inferred from the widest input or given
  explicitly. Explicit exact conversion from doubles requires a `scale`.
  Values are backed by a character-backed `vctrs` vector class.
- Added active decimal contexts with rounding, exponent limits, traps, and
  sticky flags. Non-trapped signals are now reported as `decimal_flags_warning`
  warnings as they occur; set `options(decimal.report_flags = FALSE)` to silence
  them and rely on `decimal_flags()` alone. `quantize()`/`round()`/`signif()`
  and `sqrt()`/`exp()`/`log()`/`log10()` are exempt from the warning, since
  `inexact`/`rounded` is their expected outcome rather than a surprise.
- Added vectorized arithmetic, comparison, equality/order proxies, and decimal
  summaries. Arithmetic result scale follows the exact ideal-exponent rules
  for `+`, `-`, and `*`, and is inferred from the computed result for `/`,
  `^`, and other operations with no exact terminating scale.
- Added decimal-specific helpers including `quantize()`, `normalize()`, `fma()`,
  `same_quantum()`, `adjusted()`, and `number_class()`.
- Added vignettes, compatibility documentation, and release metadata.
