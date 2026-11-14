## Submission

This is an update from 0.1.1 to 0.1.2, a correctness release. An internal
review found results that 0.1.1 returned wrongly without any error or
warning, and this release fixes them:

- `as.double()` is now correctly rounded on every platform. Previously some
  values were off by one unit in the last place, and values of more than
  about 4,900 digits became `NaN` or `Inf`.
- `options(decimal.default_scale)` no longer changes the results of
  rounding, `summary()`, integer arithmetic or Arrow reads.
- `summary()` quartiles no longer depend on `options(digits)` or `OutDec`.
- vctrs ordering of negative values no longer depends on the collation
  locale.
- Arrow writes no longer wrap values that are wider than a pinned type, and a
  failed Parquet write no longer truncates an existing file.
- The compiled code now validates the context arguments it receives.
- Special values now pass through `floor()`, `round()` and `signif()`.
- `pmax()`, `[[<-` and `vctrs::vec_cast()` keep the shared-scale invariant.

Three behaviour changes are listed in NEWS.md:

- `as_decimal()` on a decimal without `scale` is now the identity.
- A cast to a coarser decimal is now a vctrs lossy-cast error.
- A character-to-decimal cast now uses the target scale.

Two known issues are documented in NEWS.md, each with a workaround: combining
Arrow columns of different decimal types, and `merge()` ordering its result by
a decimal key's text.

The bundled 'mpdecimal' now selects its 32- or 64-bit configuration on
WebAssembly as well.

'tidyr' and 'stringi' are new in Suggests, for tests only; every use is
guarded.

## Test environments

- local macOS 15 (x86_64), R 4.6.2
- GitHub Actions runners: macOS (R release); Windows (R release and R devel);
  Ubuntu (R release and oldrel-1)
- GitHub Actions, CRAN-like R-devel containers: clang 23 (C as `-std=gnu23`,
  CRAN's C flags), Ubuntu clang and Ubuntu GCC 16; R-hub `nosuggests`
- GitHub Actions, for the compiled code: AddressSanitizer (R-hub `clang-asan`
  and `gcc-asan`), UBSan (gcc and clang), Valgrind memcheck, LTO, gctorture,
  rchk, gcc `-fanalyzer`, and CRAN's rcnst, rlibro and vnu checks

## R CMD check results

0 errors | 0 warnings | 0 notes

## Reverse dependencies

There are no reverse dependencies.

## Notes on the vendored 'mpdecimal' library

The package vendors `mpdecimal` 4.0.1 under `src/mpdecimal`. Its BSD-2-Clause
license is recorded in `inst/COPYRIGHTS`, and Stefan Krah is credited in
`Authors@R`.

The vendored sources are minimally patched (guarded by `MPD_NO_FILE_IO`) so
that no compiled code writes to stdout/stderr or terminates the R process:
fatal/warning macros and defensive `abort()` calls are routed through R's error
handler, and the unused `mpd_print()`/`mpd_fprint()` helpers are compiled out.
The header also selects its 32- or 64-bit configuration from compiler macros,
WebAssembly included. Any `#pragma` directives reported in `src/mpdecimal` are
upstream's own and are required for correctly-rounded floating-point behaviour.
