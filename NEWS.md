# decimal 0.1.0

- First functional release of arbitrary-precision decimal vectors for R.
- `as_decimal()` and `decimal_from_double()` now use the opt-in
  `decimal.default_scale` option when `scale` is not supplied. Explicit scale
  arguments continue to take precedence.
- Added exact decimal parsing, at a single shared scale (number of fractional
  digits) per vector, inferred from the widest input or given explicitly.
  Explicit double conversion decodes the exact IEEE value and quantizes it to
  a required `scale`. Values are backed by a character-backed `vctrs` vector
  class.
- Added active decimal contexts with rounding, exponent limits, traps, and
  sticky flags. Non-trapped signals are now reported as `decimal_flags_warning`
  warnings as they occur; set `options(decimal.report_flags = FALSE)` to silence
  them and rely on `decimal_flags()` alone. `quantize()`/`round()`/`signif()`
  and `sqrt()`/`exp()`/`log()`/`log10()` are exempt from the warning, since
  `inexact`/`rounded` is their expected outcome rather than a surprise.
- Grouped libmpdec's invalid-operation subconditions under the public
  `invalid_operation` signal, so the default trap now catches cases such as
  `0 / 0`. Correct-rounding mode is always enabled as an internal invariant.
- Made promotion to a finer shared scale exact and independent of the active
  context, including construction, concatenation, and assignment. Reducing
  scale remains an explicit, context-controlled quantization.
- Preserved names across construction, elementwise arithmetic, comparisons,
  Math methods, decimal helpers, predicates, formatting, and coercion.
- `format.decimal()` now rejects unsupported arguments in `...` instead of
  silently ignoring them. Richer formatting is planned for 0.2.0.
- Added vectorized arithmetic, comparison, equality/order proxies, and decimal
  summaries. Arithmetic result scale follows the ideal-exponent rules when
  the context does not constrain the result and is otherwise inferred from
  what was computed.
- Added decimal-specific helpers including `quantize()`, `normalize()`, `fma()`,
  `same_quantum()`, `adjusted()`, and `number_class()`.
- Added vignettes, compatibility documentation, and release metadata.
