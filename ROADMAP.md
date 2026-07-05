# decimal roadmap

## Goal

`decimal` should provide immutable, arbitrary-precision decimal vectors for R,
powered by the vendored mpdecimal library and designed to behave naturally in
base R, tibbles, and other `vctrs` consumers.

Version 0.1.0 should be a useful, correctness-first release rather than a full
copy of Python's `decimal` module. It should cover exact construction, context
controlled arithmetic, comparison, common mathematical operations, missing and
special values, and normal vector behavior.

## Current state

The repository is a package scaffold at version 0.0.0.9000. It vendors
mpdecimal 4.0.1, compiles the library through `src/Makevars`, registers one
`.Call` routine, and can report the native mpdecimal version. There is not yet
an R vector class, context API, arithmetic wrapper, documentation suite, or test
suite.

## Design decisions

### R-native API, Python-compatible arithmetic model

- Follow Python's three-part model: decimal values, an arithmetic context, and
  signals.
- Use Python-compatible defaults: precision 28, round-half-even, `Emin =
  -999999`, `Emax = 999999`, no clamping, and traps for invalid operation,
  division by zero, and overflow.
- Keep values independent of the context. Construction from character and
  integer inputs is exact; the active context is applied by arithmetic and
  explicitly context-sensitive operations.
- Adapt behavior where R conventions are stronger, especially vector
  recycling, `NA`, `na.rm`, type stability, and lossy casts.

### Serializable character-backed vector

For v0.1.0, store each decimal as an exact mpdecimal string inside a character
vector and wrap it with `vctrs::new_vctr()`.

This is the same broad storage strategy used by the `bignum` package. Native C
code parses whole vectors, performs mpdecimal operations, and returns exact
strings. This has some parse/format overhead, but provides important first
release properties:

- objects work with `saveRDS()`, serialization, copying, and data frames;
- no external-pointer lifetime or finalizer problems;
- subsetting and concatenation are cheap and handled by `vctrs`;
- the storage representation can be optimized later without changing the
  public R API.

The stored representation must preserve trailing zeros, signed zero,
infinities, quiet NaNs, and signaling NaNs. R `NA` remains a separate missing
value represented by `NA_character_`.

### Fixed scale per vector

Each `decimal` vector carries a single shared **scale** (number of
fractional digits) as a vector-level attribute, in the spirit of SQL
`NUMERIC(p, s)`. This is a deliberate departure from the General Decimal
Arithmetic Specification's floating-decimal model, where every value carries
its own independent exponent: R is column-oriented, and a per-vector scale is
what makes trailing-zero display uniform within a column and what maps
cleanly onto SQL/Arrow decimal types (v0.3 integration goal).

- Scale is inferred at construction as the largest number of fractional
  digits present, unless given explicitly via `scale =`. Every element is
  padded (never rounded) to that shared scale.
- `decimal("1.2")` and `decimal("1.20")` are therefore the same value, and
  `1.2 == 1.20` is `TRUE` — a real divergence from the spec model, where they
  are distinct quanta.
- Arithmetic result scale follows the exact ideal-exponent rules where one
  exists (`max(sx, sy)` for `+`/`-`/`%%`, `sx + sy` for `*`, `0` for `%/%`).
  Operations with no exact terminating scale (`/`, `^`, `sqrt`, `exp`, `log`,
  `log10`) instead take the scale of whatever the native op actually computed
  under the active context's precision — never a precomputed target, since
  forcing one can demand more precision than the context allows even when the
  raw, context-rounded result is already correct.
- `same_quantum()` compares the two vectors' declared scales (a per-vector,
  not per-element, fact under this model). `normalize()` reduces to the
  finest scale the vector's elements collectively need, rather than an
  unconstrained per-element reduction.
- Explicit double conversion (`as_decimal()`, `decimal_from_double()`)
  requires a `scale` argument: the exact binary value of a double can need
  dozens of fractional digits, and defaulting silently would produce
  surprisingly wide vectors.
- Construction itself must stay exact and context-independent per the
  arithmetic model above: elements already at the target scale are never
  round-tripped through native quantize, so an ordinary low-precision active
  context cannot make plain construction spuriously trap.

This intentionally departs from the "serializable character-backed vector"
section above only in the *addition* of the scale attribute; storage
remains string-backed for v0.1.0. A future fixed-scale binary layout (limbs
plus a shared scale, no per-element exponent) is the natural v0.4 storage
optimization once this semantic model is in place.

### Native safety boundary

- Use mpdecimal's quiet, thread-safe `mpd_q*` functions. Do not call signaling
  functions whose default trap handler can raise `SIGFPE`.
- Initialize mpdecimal once when the DLL is loaded.
- Centralize decimal allocation, parsing, formatting, status handling, and
  cleanup in internal C helpers.
- Batch operations over `R_xlen_t` vectors, check user interrupts
  periodically, and ensure all allocations are released on R errors or
  interrupts.
- Recycle and cast arguments in R with `vctrs` before calling C, so native
  kernels receive compatible, equal-length inputs.

## v0.1.0 public API

The capabilities, names, and semantics below are the proposed release
contract.

### Values and conversion

- `decimal(x = character())`: user constructor.
- `as_decimal(x)`: explicit conversion generic.
- `is_decimal(x)`: class predicate.
- `decimal_from_double(x)`: exact conversion of the underlying IEEE 754 binary
  value, equivalent in spirit to Python's `Decimal.from_float()`.
- `as.character()`, `as.double()`, `as.integer()`, and `format()` methods.
- A zero-length `decimal()` prototype and an exported `NA_decimal_` constant.
- Exact parsing of decimal strings, including exponent notation, `Infinity`,
  `-Infinity`, `NaN`, `sNaN`, and signed zero.
- Double special values map as follows: `NA_real_` to decimal `NA`, `NaN` to
  decimal `NaN`, and positive or negative infinity to the corresponding
  decimal infinity.

Double conversion must never pretend that `decimal(0.1)` means the literal
decimal string `"0.1"`. `as_decimal(0.1)` and `decimal_from_double(0.1)` use
the exact binary value. Users who want decimal 0.1 should write
`decimal("0.1")`.

`as.character()` returns a lossless round-trip representation. `format()` is
the display API and may select fixed, scientific, or engineering notation
without changing the stored value.

### Context, rounding, and signals

- `decimal_context()` constructs and validates a context with precision,
  rounding, exponent limits, clamp, traps, and flags.
- `get_decimal_context()` and `set_decimal_context()` manage the active
  session context.
- `local_decimal_context()` and `with_decimal_context()` temporarily install a
  context and always restore the previous one.
- `decimal_flags()` returns sticky signal flags; `clear_decimal_flags()` resets
  them.
- Supported rounding names: `"up"`, `"down"`, `"ceiling"`, `"floor"`,
  `"half_up"`, `"half_down"`, `"half_even"`, and `"05up"`.
- User-facing signals: clamped, invalid operation, division by zero, inexact,
  rounded, subnormal, overflow, and underflow.
- Trapped signals raise classed R conditions such as
  `decimal_division_by_zero` and `decimal_invalid_operation`. Non-trapped
  signals update sticky flags and return the mpdecimal result.
- Allocation failures and invalid internal contexts are unconditional hard
  errors, not optional traps.
- For vectorized operations, flags are the union of all element statuses. A
  trapped signal reports the first failing element index.

The active context belongs to the R session, not to each decimal vector.
Values therefore remain immutable, small, and context-independent.
`decimal_context()` returns an ordinary validated S3 snapshot; the package
stores the active snapshot and its sticky flags in private package state.
`get_decimal_context()` returns a copy, so callers cannot corrupt active native
state by mutating an R object.

### Vector behavior with vctrs

- Class hierarchy: `c("decimal", "vctrs_vctr")`.
- Implement `format()`, `vec_ptype_abbr()`, `vec_ptype_full()`, and
  `pillar_shaft()` for compact tibble display.
- Implement `vec_ptype2()` and `vec_cast()` symmetrically.
- Decimal and integer vectors combine to decimal.
- Decimal and logical vectors are incompatible. The special `vctrs`
  unspecified `NA` type still combines as a missing decimal value.
- Decimal and double vectors do not combine implicitly. Explicit conversion is
  required because binary-to-decimal conversion is exact but often surprising.
- Decimal and character vectors do not combine implicitly; character parsing
  goes through `decimal()` or `as_decimal()`.
- Casts from decimal to integer or double detect loss. Base coercion methods
  warn on lossy conversion; `vctrs` casts use standard lossy-cast conditions.
- Subsetting, replacement, names, `rep()`, `c()`, `vec_c()`, zero-length
  vectors, and data-frame columns preserve the class.

### Arithmetic and comparison

Implement vectorized operators with normal `vctrs` recycling:

- unary `+` and `-`;
- binary `+`, `-`, `*`, `/`, `^`, `%%`, and `%/%`;
- `==`, `!=`, `<`, `<=`, `>`, and `>=`.

`%%` and `%/%` follow decimal specification semantics: quotient truncates
toward zero and remainder has the dividend's sign. This differs from base R
for some negative operands and must be prominent in the documentation.

Comparison, equality, matching, duplicate detection, and ordering must not
convert through double:

- use native mpdecimal comparison for comparison operators;
- provide an exact normalized key for `vec_proxy_equal()`;
- provide a native rank/order proxy for `vec_proxy_order()`;
- R `NA` propagates without changing decimal signal flags;
- qNaN propagates through arithmetic, while comparisons return logical `NA`;
- sNaN signals invalid operation and becomes qNaN when the signal is not
  trapped;
- `is.na()` is true for R `NA`, qNaN, and sNaN, while `is.nan()` is true only
  for qNaN and sNaN;
- `na.rm = TRUE` removes all values identified by `is.na()`;
- positive and negative zero compare equal, while formatting preserves the
  sign; total ordering of their representations is deferred.

### Mathematical and decimal-specific functions

Implement the following base R methods:

- `abs()`, `sign()`, `sqrt()`, `floor()`, `ceiling()`, `trunc()`, `round()`,
  and `signif()`;
- `exp()`, `log()`, and `log10()`;
- `sum()`, `prod()`, `min()`, `max()`, `range()`, and `mean()`, including
  empty inputs and `na.rm`;
- `is.na()`, `is.nan()`, `is.finite()`, and `is.infinite()`.

Implement a small decimal-specific layer:

- `quantize(x, quantum)`;
- `normalize(x)`;
- `fma(x, y, z)`;
- `same_quantum(x, y)`;
- `adjusted(x)` and `number_class(x)`;
- predicates for qNaN, sNaN, normal, subnormal, signed, and zero.

Document mpdecimal's rounding guarantees. In particular, `sqrt()` is correctly
rounded with half-even behavior, and non-integral power is not guaranteed to be
correctly rounded by libmpdec 4.0.1.

## Explicitly deferred

The following are useful, but not required for a coherent v0.1.0:

- logical digit operations, rotate, shift, `scaleb()`, `logb()`, `powmod()`,
  `remainder_near()`, and next-representable-number functions;
- total-order and total-magnitude comparison APIs;
- tuple/triple or integer-ratio decomposition;
- cumulative functions and sequence generation;
- matrices, arrays, and fixed-scale or money subclasses;
- database-driver integrations;
- a public C API for downstream packages;
- external-pointer, ALTREP, or cached native storage;
- multithreaded kernels or thread-local contexts;
- linking against a system mpdecimal instead of the vendored copy.

## Implementation stages

### Stage 0: Package and build foundation

Deliverables:

- replace placeholder `DESCRIPTION` metadata and choose the package license;
- retain mpdecimal's BSD-2-Clause notice in source distributions;
- declare `vctrs`, `rlang`, and `methods` imports plus test and documentation
  dependencies;
- make the vendored mpdecimal 4.0.1 build reproducibly on Linux, macOS, and
  Windows, including `Makevars.win` where required;
- expose an internal version function and add a package startup smoke test;
- set up testthat, roxygen2, CI, `R CMD check`, sanitizer, and valgrind jobs.

Exit criteria: a minimal source package builds, installs, loads, reports
mpdecimal 4.0.1, and passes checks on all three major platforms.

### Stage 1: Native value and context core

Deliverables:

- C helpers for exact parse, exact stringify, allocation, cleanup, context
  conversion, status aggregation, and classed error payloads;
- exact IEEE 754 double conversion by decoding sign, exponent, and significand;
  do not implement it with `as.character(double)` or a 17-digit approximation;
- vector kernels for validation, canonical equality keys, classification, and
  formatting;
- R context constructor, active/local context management, traps, and sticky
  flags;
- tests for every rounding mode, context boundary, signal, trap, and special
  value.

Exit criteria: internal native calls can round-trip every supported value and
produce the same context-sensitive results as Python/mpdecimal fixtures.

### Stage 2: Decimal vector class and conversion

Deliverables:

- `decimal`, `as_decimal`, `is_decimal`, `decimal_from_double`, and
  `NA_decimal_`;
- exact character and integer construction, explicit double conversion, and
  lossy reverse casts;
- formatting, printing, type labels, serialization, subsetting, replacement,
  concatenation, names, and tibble display;
- complete `vec_ptype2()` and `vec_cast()` matrix with symmetry tests.

Exit criteria: decimal vectors behave as stable atomic columns in base data
frames and tibbles, survive `saveRDS()` round trips, and reject unsafe implicit
coercions.

### Stage 3: Operators, comparison, and ordering

Deliverables:

- vectorized arithmetic kernels and `vec_arith()` methods;
- comparison operators without double conversion;
- exact equality and order proxies supporting `unique()`, `duplicated()`,
  `match()`, `sort()`, and joins;
- defined propagation behavior for `NA`, qNaN, sNaN, infinity, and signed zero.

Exit criteria: all operators are type-stable, recycle correctly, preserve
decimal significance, report element-indexed traps, and agree with checked
reference fixtures.

### Stage 4: Math, summaries, and decimal operations

Deliverables:

- the base Math and Summary methods listed in the v0.1.0 API;
- quantize, normalize, FMA, classification, and predicate functions;
- correct handling of `na.rm`, zero-length summaries, rounding flags, and
  context changes;
- performance baselines for construction, arithmetic, comparison, sorting,
  and summaries on representative vector sizes.

Exit criteria: the package supports complete everyday numeric workflows without
falling back to binary double arithmetic.

### Stage 5: Documentation and release

Deliverables:

- README examples showing why decimal differs from double;
- a "Decimal values" vignette covering construction, significance, special
  values, conversion, and vector behavior;
- a "Contexts and signals" vignette covering precision, rounding, flags, and
  traps;
- a compatibility table showing which Python `decimal` capabilities are
  implemented, adapted, or deferred;
- NEWS, lifecycle statement, API reference, license files, CRAN comments, and
  reverse-dependency-safe examples.

Exit criteria: full `R CMD check --as-cran` passes, native-code checks are
clean, public functions are documented and tested, and version is set to
0.1.0.

## Test strategy and release gates

### Reference correctness

- Generate deterministic expected-result fixtures with Python's `decimal`
  module using the same precision, rounding, exponent limits, and traps.
- Commit fixtures so tests do not require Python at runtime.
- Cover normal values, very large and small exponents, trailing zeros, signed
  zeros, every special value, every rounding mode, and every signal.
- Add a focused subset of General Decimal Arithmetic test cases if licensing
  and package size permit.

### R and vctrs behavior

- Test zero-length and length-one vectors, names, missing values, recycling,
  incompatible sizes, replacement, concatenation, serialization, and
  data-frame use.
- Test the full coercion matrix in both argument orders.
- Test exact equality, hashing, matching, duplicates, ordering, and sorting
  without conversion to double.
- Snapshot standalone and tibble printing.

### Native robustness

- Run AddressSanitizer and UndefinedBehaviorSanitizer where supported.
- Run valgrind for leaks and invalid access.
- Exercise allocation failures and interrupts in long vector loops.
- Keep all registered native routines behind `.Call` registration with dynamic
  symbols disabled.

### Definition of done for v0.1.0

- No known correctness bugs in core arithmetic, comparison, context, or signal
  handling.
- No implicit decimal/double mixing.
- No external pointers in user-visible values.
- Cross-platform source installation requires no external system library.
- All implemented API behavior is documented, tested, and represented in the
  Python compatibility table.

## After v0.1.0

### v0.2: Complete decimal toolbox

Add the deferred General Decimal Arithmetic operations, cumulative functions,
sequence helpers, total ordering, richer formatting, and decomposition APIs.

### v0.3: Integration

Add fixed-scale subclasses, database conversion helpers, Arrow or DBI
integration where feasible, and a stable C API for other R packages.

### v0.4: Performance

Profile real workloads and consider cached native representations, ALTREP, or a
compact binary encoding. Any storage change must preserve serialization and the
v0.1 public API.

## References

- [Python `decimal` documentation](https://docs.python.org/3/library/decimal.html)
- [mpdecimal 4.0.1 C API](https://www.bytereef.org/mpdecimal/doc/libmpdec/)
- [`vctrs` S3 vector vignette](https://vctrs.r-lib.org/articles/s3-vector.html)
- [`tidyverse/blob`](https://github.com/tidyverse/blob)
- [`davidchall/bignum`](https://github.com/davidchall/bignum)




## Lifecycle

`decimal` is usable for exact scalar and vector workflows in R, but it is still
early. The 0.1.0 API is designed to be coherent and testable rather than fully
feature-complete relative to Python's `decimal` module.

## Python compatibility

| Capability | Status in `decimal` 0.1.0 | Notes |
| --- | --- | --- |
| Exact construction and formatting | Implemented | Character/integer exact; double conversion is explicit and exact |
| Active contexts, traps, sticky flags | Implemented | `decimal_context()`, `get/set`, `with/local`, `decimal_flags()` |
| Arithmetic and comparison | Implemented | Vectorized with `vctrs`; no implicit decimal/double mixing |
| Math and summaries | Implemented | Core Math/Summary methods plus `round()` and `signif()` |
| Special values | Implemented | `NA`, infinities, qNaN, sNaN, signed zero |
| Decimal helpers | Implemented | `quantize()`, `normalize()`, `fma()`, `same_quantum()`, `adjusted()`, `number_class()` |
| Total ordering APIs | Deferred | Internal ordering exists for sorting and matching, but no public total-order API yet |
| Logical digit ops, `next_*`, `powmod()`, `scaleb()` | Deferred | Planned after 0.1.0 if demand warrants |