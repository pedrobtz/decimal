# ADR 002: Character-Backed Storage with Shared Scale

- **Status:** Accepted and implemented in 0.1.0
- **Scope:** In-memory representation and serialization

## Context

The first release needs exact values that survive copying, subsetting,
concatenation, data frames, and `saveRDS()` without native-lifetime hazards.
An external-pointer representation would require ownership, finalizers, and a
custom serialization format. Plain character storage is simpler, but native
operations must parse and format values repeatedly.

## Decision

Store each decimal as an exact canonical string inside a `vctrs_vctr`, with a
single integer `scale` attribute for the entire vector.

- Finite strings retain declared significance through trailing zeros.
- Signed zero, positive and negative infinity, qNaN, and sNaN are stored as
  decimal strings.
- R missing values use `NA_character_`, distinct from decimal NaNs.
- Combining vectors promotes them to a common scale. Rescaling uses native
  quantization and the active context.
- Character and integer construction is exact. Double conversion reconstructs
  the exact IEEE 754 value in C, then quantizes to a required scale.
- Native kernels parse whole vectors into temporary `mpd_t` values, operate,
  and return exact strings. No `mpd_t` pointer escapes to R.

The implementation centers on `new_decimal()`, `decimal_scale()`,
`decimal_rescale_strings()`, and `decimal_new_result()` in `R/decimal.R`, with
parsing and formatting helpers in `src/core.c`.

## Consequences

Objects are ordinary, serializable R values with cheap vctrs subsetting and no
finalizers. The representation preserves exact textual significance and keeps
package installation self-contained. The tradeoff is repeated parse/format
overhead and one shared scale rather than per-element scale metadata.

A future compact, cached, ALTREP, or native representation is permitted only
if it preserves public behavior, exact round trips, serialization
compatibility, special values, and the shared-scale contract—or introduces an
explicit migration plan.
