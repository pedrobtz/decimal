# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/native-code.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

## What this is

`decimal` is an R package for exact, arbitrary-precision decimal vectors. It
combines an R and `vctrs` interface with registered C kernels backed by the
vendored `mpdecimal` 4.0.1 library. Arithmetic is governed by an explicit,
session-scoped decimal context (precision, rounding, traps, sticky flags), and
the model follows Cowlishaw's "General Decimal Arithmetic". Hard runtime
dependencies are `methods`, `rlang`, `vctrs` and `withr`; Arrow, data.table,
dplyr, pillar and tibble are optional integrations in `Suggests`.
Correctness and a coherent R API take priority over feature parity with
Python's `decimal` module.

The documents in `.agents/` are the specification and outrank this file.
Read the ones relevant to a change before editing:

- [Architecture](.agents/architecture.md) — runtime layers, native boundary,
  and data flow.
- [Package design](.agents/package-design.md) — public API, invariants, and
  extension points.
- [Product roadmap](.agents/roadmap.md) — current baseline, next releases, and
  deferred themes.
- [0.2.0 release plan](.agents/release-0.2.0-plan.md) — committed scope,
  exclusions, sequencing, and release gates for the next release.
- [Feature expansion plan](.agents/feature-expansion-plan.md) — detailed,
  task-by-task work for advanced libmpdec operations.
- [Arrow integration plan](.agents/arrow-integration-plan.md) — exact
  conversion to and from Arrow decimal arrays, with measurements.
- [Testing](.agents/testing.md) — test layout, commands, and coverage policy.
- [Release process](.agents/release-process.md) — documentation, CI, and CRAN
  release gates.
- [Conventions](.agents/conventions.md) — R, C, documentation, Git, and
  vendored-code rules.
- [ADR 001](.agents/decisions/001-r-native-vector-api.md) — R-native vector
  interface and type compatibility.
- [ADR 002](.agents/decisions/002-character-backed-shared-scale.md) —
  character-backed storage and shared scale.
- [ADR 003](.agents/decisions/003-session-scoped-arithmetic-context.md) —
  session context, traps, and sticky flags.
- [ADR 004](.agents/decisions/004-quiet-native-kernels.md) — native safety and
  signal aggregation.
- [ADR 005](.agents/decisions/005-arrow-string-cast-canonical.md) — trusting
  Arrow's decimal-to-string cast as canonical storage.
- [ADR 006](.agents/decisions/006-arrow-extension-type.md) — Arrow extension
  type over decimal storage, and the plain-field escape hatch.

`AGENTS.md` carries an older copy of these orientation notes for other
agents. This file supersedes it for Claude Code.

## Current state

Version 0.1.1 is on CRAN (published 2026-09-23); the default branch is
`0.1.1.9000`, verified 2026-11-11. 0.1.0 shipped the core: exact parsing,
character-backed `vctrs` vectors with one shared scale, contexts with traps
and sticky flags, vectorised arithmetic, comparison, ordering, Math and
Summary methods, and the decimal helpers (`quantize()`, `normalize()`,
`fma()`, `same_quantum()`, `adjusted()`, `number_class()`). 0.1.1 added
exact conversion to and from Arrow decimal arrays and an Arrow extension type
for `decimal` columns. The rest of the 0.2.0 toolbox (rich formatting,
remainder-near and friends, total comparisons) is not built yet; see the
[0.2.0 release plan](.agents/release-0.2.0-plan.md).

## Versions and dependents

The open version parent issue is #17 (`v0.1.1`), still open after 0.1.1
reached CRAN. Sibling packages that use this one: zuarrow (`Suggests`) and
zuspark (`Suggests`, with `Remotes: pedrobtz/decimal`). Issue #24 and pull
request #26 register decimal's Arrow types with zuarrow.

## Commands

Beyond the shared commands:

```sh
Rscript -e "devtools::test(filter = 'context')"            # one test group
Rscript -e "devtools::test_active_file('R/<module>.R')"    # file pair
gh workflow run native-checks.yaml --ref main              # native suite
```

`devtools::test_active_file()` works when production and test file names
align. The native suite (sanitizers, Valgrind, LTO, gctorture, rchk) is
required for every native change; see [Testing](.agents/testing.md).

## Architecture

The R layer owns vector semantics, scale, context state and conditions. The C
layer does exact parsing and vectorised numerical work through `mpdecimal`.
User-visible values never hold native pointers. The full flow and component
table are in [Architecture](.agents/architecture.md).

- `R/decimal.R` — values and methods (`decimal()`, `new_decimal()`,
  `vec_arith.decimal()`, `vec_math.decimal()`).
- `R/context.R` — context state and sticky flags.
- `R/arrow.R` — Arrow interoperability.
- `R/native-core.R` — the native adapter: `decimal_context_call()` and
  `decimal_native_result()`, which updates sticky flags, raises a classed
  error for the first trapped element and otherwise warns on unexpected
  signals.
- `src/core.c` — kernels (`decimal_c_*_strings()`) and parsing and result
  helpers; `src/init.c` — routine registration; `src/mpdecimal/` — the
  vendored engine.
- `R/zzz.R`, `R/mpdecimal-version.R` — `.onLoad()` runtime validation and
  `decimal_runtime_smoke_test()`.

Adding an operation follows the seven steps in
[Package design](.agents/package-design.md): R function, cast and recycle in
R, wrapper in `R/native-core.R`, kernel in `src/core.c`, registration in
`src/init.c`, tests, then roxygen, `_pkgdown.yml` and `NEWS.md`.

## Invariants that are easy to break

The full list is in [Package design](.agents/package-design.md); these are the
ones a change most often touches.

- **Comparison, hashing and ordering never pass through double.** Equality
  and ordering proxies use normalised native keys.
- **Scale is a vector property.** Combining or assigning decimals promotes to
  a common scale without consulting the context. Context affects operations
  and explicit scale reduction, not exact parsing or promotion.
- **Double conversion needs a scale**, explicit or from
  `options(decimal.default_scale = )`, then quantizes. Decimal and double or
  character vectors never mix implicitly; decimal and integer may.
- **R `NA` is distinct from qNaN and sNaN.** Signed zero, infinities, NaNs and
  trailing zeros stay representable.
- **Quiet `mpd_q*` calls only**, so R aggregates and reports signals. Native
  correct rounding is always on and not user-configurable.
- **Cast and recycle in R.** C kernels receive compatible, equal-length
  character vectors plus the active context.
- **Native cleanup across longjmp.** Helpers never raise; they return a status
  or `NULL`. A kernel allocates every `mpd_t` it needs up front and checks
  them together. No R allocation while native memory is live: free the
  handles once the formatted text exists, then pass the text to
  `decimal_mkchar_consume()`, which frees it under `R_UnwindProtect()`.
- **Registration.** Package C symbols are prefixed `decimal_` or
  `decimal_c_`. Every routine is registered in `src/init.c` with fixed arity,
  and `R_useDynamicSymbols(dll, FALSE)` stays.
- **Arrow storage.** Arrow's decimal-to-string cast is trusted as canonical
  storage once the exponent letter is folded to lowercase (ADR 005); a
  property test guards it.
- **Every new public documentation topic goes into `_pkgdown.yml`.**

## Testing

Layout, one file per concern, is listed in [Testing](.agents/testing.md).

- `tests/testthat/setup.R` disables routine flag reporting globally. A test of
  a warning must re-enable it locally.
- Context-sensitive tests restore state with `with_decimal_context()` or
  `local_decimal_context()`, and `withr` for options.
- `test-data-table.R` runs queries through `dt_query()`. The namespace does
  not import data.table, so a bare `dt[...]` silently gets data-frame
  semantics.
- `test-arrow.R` and `test-data-table.R` skip when the package is not
  installed.
- Cover zero length, recycling, names, `NA`, qNaN, sNaN, infinities, signed
  zero, scale changes, every applicable rounding mode, sticky flags and
  trapped signals, and both argument orders for type interactions. Snapshot
  complete user-facing warnings and errors.
- No coverage threshold. The aggregate report includes `src/mpdecimal/`;
  judge first-party coverage separately for `R/`, `src/core.c`,
  `src/decimal.c` and `src/init.c`.

## Continuous integration

- `R-CMD-check.yaml` — **deviation:** still a hand-rolled `r-lib/actions`
  matrix, not a call to r-actions' `r-cmd-check.yml`, so it does not yet count
  as the pre-submission check. #23 tracks the adoption; #29 tracks gating the
  jobs on documentation-only pull requests.
- `native-checks.yaml` — r-actions' sanitizers, Valgrind, LTO, gctorture and
  rchk. Runs on pull requests that touch `src/**` (about seventeen minutes,
  nearly all gctorture) and on dispatch. #27 tracks a Valgrind failure on
  possibly-lost thread blocks from arrow and data.table.
- `coverage.yml` — r-actions' coverage on push and pull request; the badge
  commit goes to `gh-pages`.
- `pkgdown.yaml` — builds the site and deletes `CLAUDE.md` and `AGENTS.md`
  from the throwaway checkout first, because pkgdown renders every top-level
  `.md` file as a page.

## Vendored native code

`src/mpdecimal/` is libmpdec 4.0.1 by Stefan Krah, BSD 2-Clause, from
<https://www.bytereef.org/mpdecimal/>. Its notice is kept verbatim in
`src/mpdecimal/COPYRIGHT.txt`, and `inst/COPYRIGHTS` declares it. Modify it
only when R safety or portability needs it, and record the patch in
`inst/COPYRIGHTS`. Current local patches, confined to `mpdecimal.h`,
`mpdecimal.c` and `io.c`:

- under `MPD_NO_FILE_IO`, fatal and warning error macros and defensive
  `abort()` calls route through R's error handler, and `mpd_fprint()` and
  `mpd_print()` are disabled, so nothing writes to stdout or stderr or ends
  the process;
- the `#pragma GCC diagnostic ignored` lines are removed from `io.c` and
  `mpdecimal.c`, because they trip CRAN's pragma check.

**Deviation:** there is no `src/vendor/PROVENANCE`, `tools/patches/` or
vendor-verify script yet; `inst/COPYRIGHTS` is the patch record.
Pull request #25 selects the mpdecimal ABI on WebAssembly.
