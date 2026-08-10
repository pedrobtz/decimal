## Resubmission

This is a resubmission. In this version I have:

- added return-value documentation for `NA_decimal_`;
- added a reference for the General Decimal Arithmetic model; and
- reworded terms flagged by the incoming spell check.

## Test environments

- local macOS Tahoe 26.5.2, R 4.6.1

## R CMD check results

0 errors | 0 warnings | 0 notes

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
