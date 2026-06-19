# decimal 0.1.0

- First functional release of arbitrary-precision decimal vectors for R.
- Added exact decimal construction, explicit exact conversion from doubles, and
  a character-backed `vctrs` vector class.
- Added active decimal contexts with rounding, exponent limits, traps, and
  sticky flags.
- Added vectorized arithmetic, comparison, equality/order proxies, and decimal
  summaries.
- Added decimal-specific helpers including `quantize()`, `normalize()`, `fma()`,
  `same_quantum()`, `adjusted()`, and `number_class()`.
- Added vignettes, compatibility documentation, and release metadata.
