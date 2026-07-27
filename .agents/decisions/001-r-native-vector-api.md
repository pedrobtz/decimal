# ADR 001: R-Native Vector API

- **Status:** Accepted and implemented in 0.1.0
- **Scope:** Public API, type compatibility, and vector semantics

## Context

libmpdec and Python's `decimal` module provide a mature decimal arithmetic
model, but a direct port would not behave like an R vector. The package must
combine exact decimal semantics with recycling, missing values, S3 dispatch,
data-frame use, and explicit lossy conversion.

## Decision

Expose an R-native API built on `vctrs`, while following the General Decimal
Arithmetic model for numerical behavior.

- Public values use class `c("decimal", "vctrs_vctr")`.
- R performs casting, recycling, scale resolution, and missing-value handling
  before calling C.
- Decimal and integer values interoperate implicitly. Double and character
  values require explicit conversion.
- Package helpers are added for common R workflows; the public surface does
  not mirror every libmpdec function.

## Consequences

Decimal vectors work predictably with `vctrs`, tibbles, summaries, and R
serialization. Precision loss and binary-to-decimal conversion remain
explicit. Some Python APIs are renamed, adapted, or intentionally deferred.

## Code References

- `R/decimal.R`: constructors, casts, operators, Math/Summary methods.
- `NAMESPACE`: registered S3 methods and exported functions.
- `_pkgdown.yml`: public API groupings.
