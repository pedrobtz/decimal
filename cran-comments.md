## Submission

This is an update from 0.1.0 to 0.1.1. It adds exact conversion to and from
Arrow decimal arrays (with 'arrow' in Suggests) and a `summary()` method, speeds
up construction from character, and fixes memory leaks on the error paths of the
compiled code and malformed logical vectors returned by several predicates.
`DESCRIPTION` now declares `URL` and `BugReports`.

## Test environments

- local macOS Tahoe 26.6.2 (aarch64), R 4.6.1
- GitHub Actions: macOS (R release); Windows (R devel and release); Ubuntu
  (R devel, release and oldrel-1)
- GitHub Actions, for the compiled code: ASan/UBSan, Valgrind, LTO, gctorture
  and rchk

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
Any `#pragma` directives reported in `src/mpdecimal` are upstream's own and are
required for correctly-rounded floating-point behaviour.
