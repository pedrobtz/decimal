# ADR 005: Trust Arrow's Decimal-to-String Cast

- **Status:** Accepted and implemented in 0.2.0
- **Scope:** Arrow interoperability boundary

## Context

`decimal` vectors store canonical decimal strings produced by `mpd_to_sci()`
plus one shared scale (ADR 002). Arrow stores a decimal as a fixed-width
two's-complement integer plus a type-level scale. The exact bridge between the
two is the decimal string: Arrow's `cast` to `utf8` and `mpd_to_sci()` both
implement the General Decimal Arithmetic "to-scientific-string" rule, using
plain notation when the scale is non-negative and the adjusted exponent is at
least -6, and scientific notation otherwise.

Re-parsing those strings through `decimal()` is correct but wasteful. For
1,000,000 `decimal128(20, 2)` values, with every string materialized (arrow
returns strings as ALTREP vectors, so a call can return before any string
exists in R), the trusted path takes 0.27s against 0.78s for
casting to string and calling `decimal()`, almost all of the difference being
`decimal_c_canonicalize_strings()` validating text that is already canonical.
The lossy `as.vector()` conversion to double takes 0.07s.

A property comparison over roughly 5,200 random values, eleven scales from -5
to 70, both `decimal128` and `decimal256`, including negatives, zeros, and
trailing zeros, found exactly one systematic difference: Arrow writes the
exponent letter as `E` and the package writes `e`, because the package calls
`mpd_to_sci(dec, 0)`. After folding the letter there were zero mismatches.

## Decision

Treat Arrow's decimal-to-string cast, with the exponent letter folded to
lowercase, as already being this package's canonical storage form.

- `as_decimal()` on an Arrow decimal array casts to `arrow::string()`, folds
  the letter with Arrow's `utf8_lower` compute kernel, and hands the result to
  `new_decimal(validate = FALSE)`.
- The vector's scale comes from the Arrow type, so it is right even when a
  chunk happens to hold only whole numbers.
- The invariant is a tested property, not an assumption: `test-arrow.R`
  compares the trusted path against a full re-parse across several scales and
  both widths on every run.

The alternative, a native verification pass over the returned strings, was
rejected. It would add roughly 0.3s per 1,000,000 values, giving back most of the
gain, to re-check a deterministic C++ cast that follows a published
specification and is already covered by the property test.

## Consequences

Arrow decimal columns of any width convert in about a third of the time a
re-parse would take, with the remainder being Arrow's own cast and the
materialization of the strings in R. Nothing native is involved, so the native check gates do not
apply to this path.

If a future Arrow release changed its formatting, the property test would fail
rather than the package silently admitting non-canonical storage; the fix
would be to widen the fold or fall back to `decimal()`.

## Code References

- `R/arrow.R`: `decimal_from_arrow_decimal()` and the `as_decimal()` methods.
- `tests/testthat/test-arrow.R`: the canonical-form property test.
- ADR 002 for the storage invariant this preserves.
