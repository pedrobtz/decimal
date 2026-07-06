# mpdecimal Feature Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the most useful remaining `mpdecimal` operations through a
vectorized, context-aware R API without treating bundled-library coverage as
package feature coverage.

**Architecture:** Extend the existing generic unary, binary, and ternary C
kernels in `src/core.c`, preserving exact character-backed storage and the
current R-managed trap/flag model. Add user-facing helpers in a focused
`R/advanced.R` file and tests in `tests/testthat/test-advanced.R`; infer result
scale from native output whenever an operation can change the exponent.

**Tech Stack:** R 4.2+, vctrs, rlang, testthat 3, roxygen2, C99, libmpdec 4.0.1

---

## What the coverage report actually says

The 38.59% figure mixes package code with all bundled `mpdecimal` internals.
It is not evidence that the package links dead or unnecessary modules.


- `convolute.c`, `crt.c`, `difradix2.c`, `fnt.c`, `fourstep.c`,
  `numbertheory.c`, `sixstep.c`, `transpose.c`, and their headers implement
  fast number-theoretic-transform multiplication. `mpd_qmul()` selects these
  paths automatically for very large coefficients. Ordinary unit-test inputs
  stay on base or Karatsuba multiplication paths; there is no separate R
  feature that should call these files directly.
- `mpsignal.c` contains signaling wrappers. The package deliberately calls
  the quiet `mpd_q*` functions instead, because vector kernels must aggregate
  status flags and report the first trapped element after cleaning up native
  allocations. Calling the signaling wrappers would weaken that design.
- `mpalloc.c`, `basearith.c`, `context.c`, `io.c`, and most of `mpdecimal.c`
  are shared implementation machinery. Line coverage depends heavily on
  operand size, precision, special values, and error paths.
- `R/zzz.R` is load-time setup, while `R/mpdecimal-version.R` is mostly a
  startup compatibility check. Their low reported percentages are test-harness
  concerns, not missing arithmetic features.

Coverage should therefore be reported in two views: first-party package code
(`R/`, `src/core.c`, `src/decimal.c`, and `src/init.c`) and bundled upstream
code. Do not add artificial giant-number tests merely to increase the combined
percentage.

## Current native surface

The package already uses exact parsing and conversion, contexts, signals,
classification, formatting to scientific/engineering notation, arithmetic,
power, remainder, integer division, comparison, square root, exp/log/log10,
quantize, normalize, fused multiply-add, and decimal predicates.

The following public libmpdec operations are not yet exposed.

| Priority | Candidate R API | Native operation | User value |
| --- | --- | --- | --- |
| P1 | `next_minus()`, `next_plus()`, `next_toward()` | `mpd_qnext_*` | Bounds, interval algorithms, and finding adjacent values under the active context |
| P1 | `remainder_near()` | `mpd_qrem_near` | IEEE-style remainder using the nearest-even quotient |
| P1 | `divmod()` | `mpd_qdivmod` | Quotient and remainder in one native pass |
| P1 | `compare_total()`, `compare_total_mag()` | `mpd_cmp_total*` | Deterministic ordering of signed zeros, NaNs, and different representations |
| P1 | `copy_sign()` | `mpd_qcopy_sign` | Copy signs exactly, including negative zero and NaN signs |
| P1 | `min_mag()`, `max_mag()` | `mpd_qmin_mag`, `mpd_qmax_mag` | Choose values by absolute magnitude without converting to double |
| P1 | `scaleb()` | `mpd_qscaleb` | Shift a decimal exponent by an integer power of ten |
| P2 | `powmod()` | `mpd_qpowmod` | Exact arbitrary-precision modular exponentiation for integer-valued decimals |
| P2 | `invroot()` | `mpd_qinvroot` | Reciprocal square root with one final rounding operation |
| P2 | richer `format()` arguments | `mpd_qformat` | Width, sign, grouping, fixed/scientific/general notation, and precision |
| P3 | `decimal_and()`, `decimal_or()`, `decimal_xor()`, `decimal_invert()` | `mpd_qand/or/xor/invert` | General Decimal Arithmetic digit-logical operations |
| P3 | `decimal_shift()`, `decimal_rotate()` | `mpd_qshift`, `mpd_qrotate` | Logical digit manipulation under the active precision |
| P3 | integer base import/export | `mpd_qimport_*`, `mpd_qexport_*` | Efficient conversion of large integer coefficients to and from other bases |

`logb()` and integral-rounding wrappers are intentionally not prioritized:
`adjusted()` already supplies the useful exponent information, base R already
uses `logb()` to mean logarithm with a selectable base, and `round()`,
`signif()`, `floor()`, `ceiling()`, `trunc()`, and `quantize()` already cover
R's normal integral-rounding workflows.

## Files

- Create `R/advanced.R`: public advanced decimal operations and their small
  shared R helpers.
- Create `tests/testthat/test-advanced.R`: value, vectorization, context,
  special-value, flag, and trap tests for the new API.
- Modify `R/native-core.R`: internal `.Call` wrappers and status handling.
- Modify `src/core.c`: native dispatch entries plus kernels for total compare,
  two-result division, and modular power.
- Modify `src/init.c`: declarations and fixed-arity native registration.
- Modify `_pkgdown.yml`: add a dedicated advanced-operations reference group.
- Modify `NEWS.md`: list each new user-facing function.
- Modify `README.md`: add a compact advanced-arithmetic example only after the
  first P1 slice is complete.

## Phase 1: High-value, low-complexity operations

### Task 1: Add neighboring representable values

**Files:**

- Create: `R/advanced.R`
- Modify: `src/core.c:418-470`
- Test: `tests/testthat/test-advanced.R`

- [ ] **Step 1: Write failing tests for context-sensitive neighbors**

```r
test_that("next values use the active context", {
  ctx <- decimal_context(precision = 3L, traps = character())

  with_decimal_context(ctx, {
    expect_identical(as.character(next_plus(decimal("1.00"))), "1.01")
    expect_identical(as.character(next_minus(decimal("1.00"))), "0.999")
    expect_identical(
      as.character(next_toward(decimal("1.00"), decimal("2.00"))),
      "1.01"
    )
  })
})

test_that("next values recycle and preserve missing values", {
  ctx <- decimal_context(precision = 3L, traps = character())

  with_decimal_context(ctx, {
    x <- decimal(c("1.00", NA_character_))
    out <- next_toward(x, decimal("2.00"))
    expect_identical(as.character(out), c("1.01", NA_character_))
  })
})
```

- [ ] **Step 2: Run the focused tests and verify that the functions are absent**

Run: `Rscript -e "devtools::test(filter = '^advanced$')"`

Expected: FAIL because `next_plus()`, `next_minus()`, and `next_toward()` do
not exist.

- [ ] **Step 3: Extend native dispatch**

Add these exact branches to `decimal_math_fun_from_name()`:

```c
if (strcmp(op, "next_minus") == 0) {
  return mpd_qnext_minus;
}
if (strcmp(op, "next_plus") == 0) {
  return mpd_qnext_plus;
}
```

Add this branch to `decimal_binary_fun_from_name()`:

```c
if (strcmp(op, "next_toward") == 0) {
  return mpd_qnext_toward;
}
```

- [ ] **Step 4: Add vectorized R functions**

```r
decimal_advanced_unary <- function(x, op) {
  x <- decimal_math_input(x)
  raw <- .decimal_math_op_strings(vctrs::vec_data(x), op)
  decimal_new_result(raw, decimal_infer_scale(raw))
}

decimal_advanced_binary <- function(x, y, op) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(x, "x"),
    decimal_math_input(y, "y")
  )
  raw <- .decimal_binary_op_strings(
    vctrs::vec_data(args[[1]]),
    vctrs::vec_data(args[[2]]),
    op
  )
  decimal_new_result(raw, decimal_infer_scale(raw))
}

#' @export
next_minus <- function(x) decimal_advanced_unary(x, "next_minus")

#' @export
next_plus <- function(x) decimal_advanced_unary(x, "next_plus")

#' @export
next_toward <- function(x, y) {
  decimal_advanced_binary(x, y, "next_toward")
}
```

Expand the roxygen blocks with purpose, context dependence, parameters,
return value, special-value behavior, and examples before documenting.

- [ ] **Step 5: Format, document, and test**

Run: `air format .`

Run: `Rscript -e "devtools::document(); devtools::test(filter = '^advanced$')"`

Expected: the advanced test file passes and the three functions are exported.

- [ ] **Step 6: Commit**

```bash
git add R/advanced.R src/core.c tests/testthat/test-advanced.R NAMESPACE man
git commit -m "feat: add adjacent decimal values"
```

### Task 2: Add remainder-near, magnitude extrema, exponent shifting, and sign copying

**Files:**

- Modify: `R/advanced.R`
- Modify: `src/core.c:418-442`
- Test: `tests/testthat/test-advanced.R`

- [ ] **Step 1: Add failing value and recycling tests**

```r
test_that("remainder_near uses the nearest-even quotient", {
  expect_identical(
    as.character(remainder_near(decimal("18"), decimal("10"))),
    "-2"
  )
  expect_identical(
    as.character(remainder_near(decimal("25"), decimal("10"))),
    "5"
  )
})

test_that("magnitude extrema retain the selected value", {
  expect_identical(as.character(min_mag(decimal("-2"), decimal("3"))), "-2")
  expect_identical(as.character(max_mag(decimal("-2"), decimal("3"))), "3")
})

test_that("scaleb shifts by powers of ten", {
  expect_identical(
    as.character(scaleb(decimal(c("1.23", "4.56")), c(2L, -1L))),
    c("123.000", "0.456")
  )
})

test_that("copy_sign handles negative zero", {
  out <- copy_sign(decimal("1.25"), decimal("-0"))
  expect_identical(as.character(out), "-1.25")
  expect_identical(is_signed(out), TRUE)
})
```

- [ ] **Step 2: Verify the tests fail because the functions are absent**

Run: `Rscript -e "devtools::test(filter = '^advanced$')"`

Expected: FAIL on the first undefined advanced function.

- [ ] **Step 3: Add native binary dispatch entries**

```c
static void decimal_copy_sign_op(mpd_t *result, const mpd_t *a,
                                 const mpd_t *b,
                                 const mpd_context_t *ctx,
                                 uint32_t *status) {
  (void)ctx;
  mpd_qcopy_sign(result, a, b, status);
}
```

Add the following mappings to `decimal_binary_fun_from_name()`:

```c
if (strcmp(op, "remainder_near") == 0) {
  return mpd_qrem_near;
}
if (strcmp(op, "min_mag") == 0) {
  return mpd_qmin_mag;
}
if (strcmp(op, "max_mag") == 0) {
  return mpd_qmax_mag;
}
if (strcmp(op, "scaleb") == 0) {
  return mpd_qscaleb;
}
if (strcmp(op, "copy_sign") == 0) {
  return decimal_copy_sign_op;
}
```

- [ ] **Step 4: Add exported R wrappers using `decimal_advanced_binary()`**

```r
#' @export
remainder_near <- function(x, y) {
  decimal_advanced_binary(x, y, "remainder_near")
}

#' @export
min_mag <- function(x, y) decimal_advanced_binary(x, y, "min_mag")

#' @export
max_mag <- function(x, y) decimal_advanced_binary(x, y, "max_mag")

#' @export
scaleb <- function(x, exponent) {
  decimal_advanced_binary(x, exponent, "scaleb")
}

#' @export
copy_sign <- function(x, sign_source) {
  decimal_advanced_binary(x, sign_source, "copy_sign")
}
```

Document that `scaleb()` requires integer-valued exponent operands and lets
libmpdec raise `invalid_operation` for invalid decimal exponents. Document the
nearest-even quotient rule for `remainder_near()`.

- [ ] **Step 5: Test normal, missing, NaN, infinity, flag, and trapped cases**

Add snapshot tests for invalid `scaleb()` exponents and division by zero, then
run:

`Rscript -e "devtools::document(); devtools::test(filter = '^advanced$')"`

Expected: PASS, with reviewed snapshots containing the operation name and
one-based failing element index.

- [ ] **Step 6: Commit**

```bash
git add R/advanced.R src/core.c tests/testthat/test-advanced.R NAMESPACE man
git commit -m "feat: add advanced decimal arithmetic"
```

### Task 3: Add representation-total comparisons

**Files:**

- Modify: `R/advanced.R`
- Modify: `R/native-core.R`
- Modify: `src/core.c`
- Modify: `src/init.c`
- Test: `tests/testthat/test-advanced.R`

- [ ] **Step 1: Add failing tests for representation distinctions**

```r
test_that("compare_total distinguishes representations", {
  expect_identical(compare_total(decimal("12.0"), decimal("12")), -1L)
  expect_identical(compare_total(decimal("-0"), decimal("0")), -1L)
  expect_identical(compare_total(decimal("NaN"), decimal("sNaN")), 1L)
})

test_that("compare_total_mag ignores signs but retains representation order", {
  expect_identical(compare_total_mag(decimal("-12"), decimal("12")), 0L)
  expect_identical(compare_total_mag(decimal("12.0"), decimal("12")), -1L)
})

test_that("total comparisons recycle and propagate R missing values", {
  out <- compare_total(decimal(c("1", NA_character_)), decimal("1"))
  expect_identical(out, c(0L, NA_integer_))
})
```

- [ ] **Step 2: Implement `decimal_c_compare_total_strings()`**

Use this native signature:

```c
SEXP decimal_c_compare_total_strings(SEXP x, SEXP y, SEXP magnitude);
```

The kernel must require equal-length character vectors, allocate `INTSXP`,
check interrupts every 1024 elements, emit `NA_INTEGER` if either R value is
missing, parse both operands exactly, call `mpd_cmp_total_mag()` when
`magnitude` is true and `mpd_cmp_total()` otherwise, then free both operands.
These operations are context-free and must not update decimal flags.

- [ ] **Step 3: Register and wrap the native kernel**

Add an arity-three declaration and registration in `src/init.c`, then add:

```r
.decimal_compare_total_strings <- function(x, y, magnitude = FALSE) {
  .Call(decimal_c_compare_total_strings, x, y, magnitude)
}
```

- [ ] **Step 4: Add exported R functions**

```r
#' @export
compare_total <- function(x, y) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(x, "x"),
    decimal_math_input(y, "y")
  )
  .decimal_compare_total_strings(
    vctrs::vec_data(args[[1]]),
    vctrs::vec_data(args[[2]])
  )
}

#' @export
compare_total_mag <- function(x, y) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(x, "x"),
    decimal_math_input(y, "y")
  )
  .decimal_compare_total_strings(
    vctrs::vec_data(args[[1]]),
    vctrs::vec_data(args[[2]]),
    magnitude = TRUE
  )
}
```

- [ ] **Step 5: Document, run tests, and commit**

Run: `air format .`

Run: `Rscript -e "devtools::document(); devtools::test(filter = '^advanced$')"`

Expected: PASS.

```bash
git add R/advanced.R R/native-core.R src/core.c src/init.c \
  tests/testthat/test-advanced.R NAMESPACE man
git commit -m "feat: add total decimal comparisons"
```

### Task 4: Add combined quotient and remainder

**Files:**

- Modify: `R/advanced.R`
- Modify: `R/native-core.R`
- Modify: `src/core.c`
- Modify: `src/init.c`
- Test: `tests/testthat/test-advanced.R`

- [ ] **Step 1: Add failing tests for the two-result contract**

```r
test_that("divmod returns quotient and remainder", {
  out <- divmod(decimal(c("7", "-7")), decimal("3"))

  expect_named(out, c("quotient", "remainder"))
  expect_s3_class(out$quotient, "decimal")
  expect_s3_class(out$remainder, "decimal")
  expect_identical(as.character(out$quotient), c("2", "-2"))
  expect_identical(as.character(out$remainder), c("1", "-1"))
})
```

- [ ] **Step 2: Implement and register `decimal_c_divmod_strings()`**

Use the same context arguments as `decimal_c_binary_op_strings()`, but allocate
two character vectors. For each element call:

```c
mpd_qdivmod(quotient, remainder, lhs, rhs, &ctx, &status);
```

Place the two character vectors in a named list called `values`, pass that list
to `decimal_result_list()`, and preserve the existing aggregate-status,
first-trap-index, interrupt, missing-value, formatting, and cleanup rules.
Register the routine with arity ten: `x`, `y`, and the eight context fields.

- [ ] **Step 3: Add the internal wrapper**

```r
.decimal_divmod_strings <- function(x, y) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_divmod_strings, x, y),
    op = "divmod"
  )
}
```

- [ ] **Step 4: Add the public wrapper**

```r
#' @export
divmod <- function(x, y) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(x, "x"),
    decimal_math_input(y, "y")
  )
  raw <- .decimal_divmod_strings(
    vctrs::vec_data(args[[1]]),
    vctrs::vec_data(args[[2]])
  )
  list(
    quotient = decimal_new_result(
      raw$quotient,
      decimal_infer_scale(raw$quotient)
    ),
    remainder = decimal_new_result(
      raw$remainder,
      decimal_infer_scale(raw$remainder)
    )
  )
}
```

- [ ] **Step 5: Test traps, special values, recycling, and zero-length input**

Run: `Rscript -e "devtools::document(); devtools::test(filter = '^advanced$')"`

Expected: PASS, and division-by-zero snapshots identify `divmod` and the first
failing element.

- [ ] **Step 6: Commit**

```bash
git add R/advanced.R R/native-core.R src/core.c src/init.c \
  tests/testthat/test-advanced.R NAMESPACE man
git commit -m "feat: add decimal divmod"
```

## Phase 2: Specialized numerical operations

### Task 5: Add modular power and inverse root

**Files:**

- Modify: `R/advanced.R`
- Modify: `R/native-core.R`
- Modify: `src/core.c`
- Modify: `src/init.c`
- Test: `tests/testthat/test-advanced.R`

- [ ] **Step 1: Add failing correctness and validation tests**

```r
test_that("powmod computes exact modular powers", {
  expect_identical(
    as.character(powmod(decimal("4"), decimal("13"), decimal("497"))),
    "445"
  )
})

test_that("powmod rejects non-integer operands through decimal signals", {
  expect_snapshot(error = TRUE, {
    powmod(decimal("4.5"), decimal("3"), decimal("7"))
  })
})

test_that("invroot rounds once under the active context", {
  ctx <- decimal_context(precision = 10L, traps = character())
  expect_identical(
    with_decimal_context(ctx, as.character(invroot(decimal("4")))),
    "0.5"
  )
})
```

- [ ] **Step 2: Add inverse-root unary dispatch**

```c
if (strcmp(op, "invroot") == 0) {
  return mpd_qinvroot;
}
```

Expose it through `decimal_advanced_unary(x, "invroot")`.

- [ ] **Step 3: Generalize the ternary native kernel**

Replace the FMA-only native entry with this 12-argument entry:

```c
SEXP decimal_c_ternary_op_strings(
    SEXP x, SEXP y, SEXP z, SEXP op, SEXP precision, SEXP rounding,
    SEXP emax, SEXP emin, SEXP traps, SEXP flags, SEXP clamp, SEXP allcr);
```

Dispatch exactly two operations:

```c
if (strcmp(op_name, "fma") == 0) {
  mpd_qfma(result, lhs, rhs, third, &ctx, &status);
} else if (strcmp(op_name, "powmod") == 0) {
  mpd_qpowmod(result, lhs, rhs, third, &ctx, &status);
} else {
  Rf_error("Unsupported decimal ternary operation");
}
```

Register the new routine with 12 arguments: three inputs, operation name, and
eight context fields. Add the shared internal wrapper and route the existing
FMA wrapper through it so current behavior remains covered:

```r
.decimal_ternary_op_strings <- function(x, y, z, op) {
  decimal_native_result(
    decimal_context_call(
      .Call,
      decimal_c_ternary_op_strings,
      x,
      y,
      z,
      op
    ),
    op = op
  )
}

.decimal_fma_strings <- function(x, y, z) {
  .decimal_ternary_op_strings(x, y, z, "fma")
}
```

- [ ] **Step 4: Add the R wrapper for modular power**

```r
#' @export
powmod <- function(base, exponent, modulus) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(base, "base"),
    decimal_math_input(exponent, "exponent"),
    decimal_math_input(modulus, "modulus")
  )
  raw <- .decimal_ternary_op_strings(
    vctrs::vec_data(args[[1]]),
    vctrs::vec_data(args[[2]]),
    vctrs::vec_data(args[[3]]),
    "powmod"
  )
  decimal_new_result(raw, decimal_infer_scale(raw))
}
```

- [ ] **Step 5: Run regression and focused tests**

Run: `Rscript -e "devtools::document(); devtools::test()"`

Expected: all existing FMA tests and all new advanced tests pass.

- [ ] **Step 6: Commit**

```bash
git add R/advanced.R R/native-core.R src/core.c src/init.c \
  tests/testthat/test-advanced.R NAMESPACE man
git commit -m "feat: add modular power and inverse root"
```

### Task 6: Add libmpdec-backed formatting

**Files:**

- Modify: `R/decimal.R:525-534`
- Modify: `R/native-core.R:141-144`
- Modify: `src/core.c:723-768`
- Test: `tests/testthat/test-decimal.R`

- [ ] **Step 1: Specify formatting behavior with tests**

Add tests for fixed, scientific, engineering, and general notation; precision;
explicit signs; zero padding; grouping; width; missing values; infinity; and
NaN. Retain this regression:

```r
test_that("default formatting remains lossless", {
  x <- decimal(c("1.2300", "-0.00", "Infinity", "NaN"))
  expect_identical(format(x), as.character(x))
})
```

- [ ] **Step 2: Extend the native formatter with `mpd_qformat()`**

Keep the current no-format fast path. When a non-missing format specification
is supplied, call `mpd_qformat(dec, format_spec, &ctx, &status)`, convert
allocation failure to an R error, and return flags/trap data through
`decimal_result_list()`.

- [ ] **Step 3: Extend `format.decimal()` without changing defaults**

Use explicit R arguments `type`, `digits`, `width`, `sign`, `grouping`, and
`zero_pad`. Build a validated libmpdec format string internally; do not expose
an unchecked native format string as the primary public API. Preserve
`engineering = TRUE` as a compatibility shortcut for `type = "engineering"`.

- [ ] **Step 4: Document and test**

Run: `Rscript -e "devtools::document(); devtools::test(filter = '^decimal$')"`

Expected: PASS with unchanged default `format()` output.

- [ ] **Step 5: Commit**

```bash
git add R/decimal.R R/native-core.R src/core.c tests/testthat/test-decimal.R \
  NAMESPACE man
git commit -m "feat: expand decimal formatting"
```

## Phase 3: Documentation and release gates

### Task 7: Publish and validate the advanced API

**Files:**

- Modify: `_pkgdown.yml`
- Modify: `NEWS.md`
- Modify: `README.md`
- Modify: `vignettes/decimal-values.Rmd`

- [ ] **Step 1: Add a pkgdown reference group**

Add `Advanced decimal operations` containing all functions completed from
Phases 1 and 2. Do not list P3 backlog functions until implemented.

- [ ] **Step 2: Add NEWS entries**

Write one alphabetized bullet per function family, beginning each bullet with
the function names in backticks.

- [ ] **Step 3: Add a concise README example**

Show `next_plus()`, `remainder_near()`, and `powmod()` under a heading that
links to the decimal-values vignette. Keep the README focused on first use.

- [ ] **Step 4: Explain representation order and context-sensitive neighbors**

Add examples to `vignettes/decimal-values.Rmd` that contrast numeric equality
with `compare_total()` and show that changing precision changes `next_plus()`.

- [ ] **Step 5: Run package quality gates**

Run: `air format .`

Run: `Rscript -e "devtools::document(); devtools::test(); pkgdown::check_pkgdown()"`

Run: `Rscript -e "devtools::check()"`

Expected: all tests pass, every exported topic appears in pkgdown, and R CMD
check reports zero errors, warnings, or notes attributable to these changes.

- [ ] **Step 6: Commit**

```bash
git add README.md NEWS.md _pkgdown.yml vignettes R src tests NAMESPACE man
git commit -m "docs: publish advanced decimal operations"
```

## Deferred P3 backlog

Implement the following only after concrete user demand:

1. Digit-logical operations (`and`, `or`, `xor`, `invert`) because they accept
   only non-negative, exponent-zero operands made solely of digits 0 and 1.
   These are decimal-spec logical digits, not R bitwise integer operations.
2. Decimal rotate and shift, which share the same unusual logical-operand
   domain and active-precision semantics.
3. Base import/export, which needs an R representation for arbitrary-length
   limb vectors and a clear use case beyond character conversion.
4. A public C API, native object caching, or ALTREP. These are integration and
   performance projects, not missing numerical functions.

## References

- [libmpdec function index](https://www.bytereef.org/mpdecimal/doc/libmpdec/functions.html)
- [libmpdec arithmetic functions](https://www.bytereef.org/mpdecimal/doc/libmpdec/arithmetic.html)
- [Python decimal API](https://docs.python.org/3/library/decimal.html)
