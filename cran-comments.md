## Submission

This is a new submission.

`decimal` provides arbitrary-precision decimal vectors for R, backed by the
vendored `mpdecimal` C library (the same library used by Python's `decimal`
module). Values use an exact, serializable decimal representation, arithmetic
is governed by an explicit decimal context, and vectors integrate with
`vctrs`.

## Test environments

- local macOS, R 4.5.2

Win-builder and cross-platform CI results will be added after those preflight
checks have run and before submission.

## R CMD check results

Local check: 0 errors | 0 warnings | 2 notes

Both notes are artifacts of the local sandboxed macOS toolchain:

```
* checking for future file timestamps ... NOTE
unable to verify current time

* checking for detritus in the temp directory ... NOTE
Found the following files/directories:
  'xcrun_db'
```

`urlchecker::url_check()` reports that all package URLs are correct.

## Notes on the vendored 'mpdecimal' library

- The package vendors `mpdecimal` 4.0.1 under `src/mpdecimal`. Its upstream
  copyright and BSD-2-Clause license are recorded in `inst/COPYRIGHTS` and
  `src/mpdecimal/COPYRIGHT.txt`, and Stefan Krah is credited as contributor and
  copyright holder in `Authors@R`.

- The vendored sources are minimally patched (guarded by the `MPD_NO_FILE_IO`
  build macro) so that no compiled code writes to stdout/stderr or terminates
  the R process: `mpdecimal`'s fatal/warning macros and its defensive,
  unreachable `abort()` calls are routed through R's error handler, and the
  unused debugging helpers `mpd_print()`/`mpd_fprint()` are compiled out. These
  changes are confined to `src/mpdecimal/mpdecimal.h` and `src/mpdecimal/io.c`
  and are documented in `inst/COPYRIGHTS`.

- If the `checking pragmas` step reports `#pragma` directives in
  `src/mpdecimal/mpdecimal.c` and `src/mpdecimal/io.c`. These are part of the
  unmodified upstream library: the `STDC FENV_ACCESS` / `float_control`
  pragmas in `mpdecimal.c` are required for correctly-rounded floating-point
  behaviour, and the remaining diagnostic pragmas are upstream's own. We have
  deliberately left the upstream numeric code unchanged here.

## Method references

There are no published references describing the methods in this package; it
wraps the well-established `mpdecimal` implementation of the General Decimal
Arithmetic Specification.
