# decimal 0.2.0 Release Plan

**Status:** Planned after the 0.1.0 CRAN release.

## Objective

Make the next release a focused expansion of the decimal toolbox, guided by
Python's `decimal.Decimal` without promising method-for-method parity.
Every addition must retain R vector semantics, the shared-scale model,
standard grouped signals, exact finer-scale promotion, name preservation, and
the prohibition on implicit double conversion.

The broader implementation backlog remains in
[Feature Expansion Plan](feature-expansion-plan.md). This file defines the
smaller set that is committed to 0.2.0.

## Scope Compared with Python

| Python capability | Proposed R API | 0.2.0 outcome |
| --- | --- | --- |
| Format specification and engineering notation | `format.decimal()` | Add validated fixed, scientific, engineering, and general forms; precision, sign, width, zero padding, and grouping |
| `next_minus`, `next_plus`, `next_toward` | `next_minus()`, `next_plus()`, `next_toward()` | Add context-sensitive adjacent-value operations |
| `remainder_near` | `remainder_near()` | Add nearest-even remainder |
| `copy_sign` | `copy_sign()` | Add exact sign transfer, including negative zero |
| `min_mag`, `max_mag` | `min_mag()`, `max_mag()` | Add magnitude extrema without double conversion |
| `scaleb` | `scaleb()` | Add integer power-of-ten exponent shifts |
| `compare_total`, `compare_total_mag` | `compare_total()`, `compare_total_mag()` | Add vectorized integer results `-1L`, `0L`, or `1L` |
| `divmod` | `divmod()` | Add one-pass quotient and remainder returned as a named list of decimal vectors |

The API is intentionally function-based rather than mirroring Python methods.
Arguments recycle with vctrs, outputs preserve names from the longest input
(first input on ties), and R `NA` remains distinct from decimal NaNs.

## Explicit Exclusions

The following Python/libmpdec capabilities are not part of 0.2.0:

- `powmod()` and `invroot()`;
- digit-logical operations, shifts, and rotates;
- coefficient tuple import/export and radix conversion;
- Python-specific context, tuple, canonicality, and radix methods;
- fixed-scale money subclasses, database/Arrow integration, and a downstream
  C API;
- storage redesign, caching, ALTREP, or performance work without profiling.

These remain candidates for later releases. Exclusion is deliberate: 0.2.0
should deepen common decimal workflows without turning Python surface area
into the product definition.

## Delivery Sequence

### 1. Rich formatting

- Keep `format(x)` byte-for-byte lossless by default.
- Replace the 0.1.0 rejection of nonempty `...` with explicit, documented
  arguments for notation, precision, sign, width, zero padding, and grouping.
- Retain `engineering = TRUE` as a compatibility shortcut.
- Build validated libmpdec format specifications in R; do not expose an
  unchecked native format string as the primary API.
- Test names, `NA`, signed zero, infinities, qNaN/sNaN, invalid argument
  combinations, locale-independent defaults, and pillar display.

### 2. Adjacent values

- Add `next_minus()`, `next_plus()`, and `next_toward()`.
- Infer the result scale from native output because the active context defines
  the adjacent representable value.
- Cover precision/exponent boundaries, recycling, names, missing values,
  infinities, NaNs, flags, and traps.

### 3. Binary decimal helpers

- Add `remainder_near()`, `copy_sign()`, `min_mag()`, `max_mag()`, and
  `scaleb()`.
- Require integer-valued decimal or integer exponents for `scaleb()`; do not
  accept doubles implicitly.
- Specify ties, signed zeros, NaNs, scale inference, and signal behavior before
  implementation.

### 4. Total comparison

- Add `compare_total()` and `compare_total_mag()` returning integer vectors.
- Preserve representation ordering for different exponents, signed zeros, and
  NaN forms while propagating R `NA`.
- Keep these distinct from ordinary comparison and vctrs ordering, which are
  value-oriented.

### 5. Combined division

- Add `divmod()` backed by one `mpd_qdivmod()` pass.
- Return `list(quotient = <decimal>, remainder = <decimal>)`, with each
  component carrying its inferred shared scale and input-derived names.
- Ensure one operation produces one aggregated flag/trap report and identifies
  the first failing element.

## Implementation Contract

- Put public advanced operations and small shared helpers in `R/advanced.R`.
- Put tests in `tests/testthat/test-advanced.R`.
- Reuse the existing unary, binary, and ternary native paths where their
  result shape and signal behavior fit.
- Register every new `.Call` entry with fixed arity and keep dynamic symbols
  disabled.
- Use quiet `mpd_q*` routines, clean up native allocations before raising R
  conditions, and check user interrupts in vector loops.
- Add roxygen documentation, `_pkgdown.yml` entries, `NEWS.md` bullets, and
  vignette examples with each public slice.
- Update the broader feature-expansion plan when implementation details or
  sequencing change, so the two plans do not drift.

## Release Gates

0.2.0 is ready only when:

- default 0.1.0 formatting and arithmetic behavior remain backward
  compatible;
- every new elementwise output has recycling, names, zero-length, `NA`,
  signed-zero, infinity, qNaN, and sNaN coverage where applicable;
- every context-aware operation has exact, rounded, flagged, and trapped
  cases;
- `air format .`, `devtools::document()`, `devtools::test()`,
  `devtools::check()`, `urlchecker::url_check()`, and
  `pkgdown::check_pkgdown()` pass;
- sanitizer, Valgrind, LTO, gctorture, and rchk workflows pass for the native
  changes;
- the built tarball installs and loads in a clean library, and generated
  README/reference/vignette output has been reviewed.

The release target is zero errors, warnings, and actionable notes attributable
to the package.
