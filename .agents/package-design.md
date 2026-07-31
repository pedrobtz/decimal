# Package Design

## Design Goals

`decimal` favors correctness and predictable R behavior over exposing every
libmpdec function. Values must be exact and serializable, work naturally as
data-frame columns, and make precision loss explicit.

## Public Model

The package has three cooperating concepts:

1. A `decimal` `vctrs_vctr` stores immutable values and one shared scale.
2. A session-scoped `decimal_context` controls precision, rounding, exponent
   limits, traps, and sticky flags.
3. Arithmetic and decimal-specific helpers delegate to vectorized native
   kernels.

The current surface includes construction and conversion; arithmetic,
comparison, Math, and Summary methods; context management; classification; and
helpers such as `quantize()`, `normalize()`, `fma()`, `same_quantum()`,
`adjusted()`, and `number_class()`. `_pkgdown.yml` is the authoritative public
API grouping.

## Behavioral Invariants

- Character and integer parsing is exact. Promotion to a finer scale is exact
  padding; an explicit coarser scale is a quantization request.
- Double conversion decodes the exact IEEE 754 value, requires an explicit
  `scale` or `options(decimal.default_scale = )`, and then quantizes.
- Scale is a vector property. Combining or assigning decimals promotes to a
  common scale without consulting the arithmetic context.
- Context affects operations and explicit scale reduction, not exact parsing
  or promotion to a finer scale.
- Decimal and integer vectors may mix. Decimal and double or character vectors
  require explicit conversion.
- R `NA` is distinct from qNaN and sNaN; signed zero, infinities, NaNs, and
  trailing zeros remain representable.
- Comparison, hashing, and ordering must never pass through double.
- Native routines use quiet `mpd_q*` functions so R can aggregate and report
  signals safely.
- Public signals follow the standard grouped conditions; internal libmpdec
  invalid-operation subconditions are not separate public trap names.
- Native correct-rounding mode is always enabled and is not user-configurable.

## Adding an Operation

Prefer extending an existing unary, binary, or ternary path:

1. Define the R-facing function and type/scale behavior in `R/`.
2. Recycle and cast in R before crossing the native boundary.
3. Add or reuse a wrapper in `R/native-core.R`.
4. Implement the kernel or dispatch branch in `src/core.c`.
5. Declare and register any new routine in `src/init.c`.
6. Add behavior, special-value, context, signal, and recycling tests.
7. Update roxygen, `_pkgdown.yml`, and `NEWS.md`.

Infer scale from native output when the operation can change the exponent.
Only promise behavior supported consistently by R semantics and libmpdec.

## Extension Priorities

Release-level direction belongs in [Product Roadmap](roadmap.md), with the
committed next-release scope in
[0.2.0 Release Plan](release-0.2.0-plan.md). The broader task sequence for
advanced libmpdec operations belongs in
[Feature Expansion Plan](feature-expansion-plan.md). Keep this document
focused on current package contracts rather than duplicating those plans.
