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

- Character and integer construction is exact.
- Double conversion reflects the exact IEEE 754 value and requires an explicit
  `scale` or `options(decimal.default_scale = )`.
- Scale is a vector property. Combining decimals promotes to a common scale.
- Context affects operations and quantization, not the stored identity of a
  value.
- Decimal and integer vectors may mix. Decimal and double or character vectors
  require explicit conversion.
- R `NA` is distinct from qNaN and sNaN; signed zero, infinities, NaNs, and
  trailing zeros remain representable.
- Comparison, hashing, and ordering must never pass through double.
- Native routines use quiet `mpd_q*` functions so R can aggregate and report
  signals safely.

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

Release-level direction belongs in [Product Roadmap](roadmap.md). The full
task sequence for advanced libmpdec operations belongs in
[Feature Expansion Plan](feature-expansion-plan.md). Keep this document
focused on current package contracts rather than duplicating either plan.
