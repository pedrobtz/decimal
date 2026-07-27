# ADR 003: Session-Scoped Arithmetic Context

- **Status:** Accepted and implemented in 0.1.0
- **Scope:** Precision, rounding, traps, and sticky flags

## Context

General Decimal Arithmetic operations need precision, rounding, exponent
limits, and signal handling. Embedding that configuration in every vector
would make otherwise identical values differ by operational policy and would
increase object size. Passing a context to every public function would make
ordinary arithmetic cumbersome.

## Decision

Maintain one active `decimal_context` snapshot in the package-private
`.decimal_state` environment.

- Values remain context-independent and immutable.
- Defaults are precision 28, half-even rounding, `Emin = -999999`,
  `Emax = 999999`, no clamp, and traps for division by zero, invalid operation,
  and overflow.
- `get_decimal_context()` returns a validated copy.
- `set_decimal_context()` replaces the active snapshot.
- `with_decimal_context()` and `local_decimal_context()` provide scoped
  overrides and guaranteed restoration.
- Untrapped signals accumulate as sticky flags. Unexpected signals also
  produce classed warnings unless `options(decimal.report_flags = FALSE)`.
- A trapped signal raises a classed error for the first failing vector element.

## Consequences

Arithmetic syntax remains natural and values serialize without ambient
configuration. Callers can make a computation reproducible by scoping an
explicit context. The active context is mutable session state, so tests and
library code must restore changes and must not assume another caller's context.

## Code References

- `R/context.R`: context construction, defaults, state, and scoping.
- `R/native-core.R`: context injection, flag updates, warnings, and traps.
- `tests/testthat/test-context.R`: lifecycle and signal behavior.
