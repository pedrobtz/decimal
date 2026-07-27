# Conventions

## R Code

- Use two spaces, spaces instead of tabs, UTF-8, Unix line endings, and a final
  newline.
- Use `snake_case` for functions and variables and base `|>` for pipelines.
- Use `\() ...` for a single-line anonymous function; use
  `function(...) { ... }` for multi-line functions.
- Prefer explicit early `return()` calls. Keep validation near public
  boundaries and use backticks around argument names in messages.
- Run `air format .` after changing R code.

Public functions require roxygen2 documentation and an `@export` tag. Wrap
roxygen comments at 80 columns. Internal helpers normally remain
undocumented. Run `devtools::document()` after roxygen changes.

## C Code

Follow the surrounding two-space style and keep package-owned symbols prefixed
with `decimal_` or `decimal_c_`. Register every exported routine in
`src/init.c` with fixed arity. Keep `R_useDynamicSymbols(dll, FALSE)`.

Use quiet, thread-safe `mpd_q*` calls. Check allocation status, release every
`mpd_t` and mpdecimal string on all paths, balance `PROTECT`/`UNPROTECT`, use
`R_xlen_t` for vector lengths, propagate `NA`, and call
`R_CheckUserInterrupt()` periodically in long loops. Cast and recycle in R so
C kernels receive compatible, equal-length vectors.

## Generated and Vendored Files

- Edit `README.Rmd`, then regenerate `README.md`.
- Edit roxygen in `R/`, then regenerate `man/` and `NAMESPACE`.
- Treat `src/mpdecimal/` as vendored upstream code. Modify it only when
  required for R safety or portability, document the patch in
  `inst/COPYRIGHTS`, and preserve all notices.
- Do not commit object files, shared libraries, check directories, or pkgdown
  output.

## Tests and Documentation

Production changes require corresponding tests. Keep tests self-contained,
restore context and option state, and prefer precise expectations over broad
boolean assertions. Add each new public documentation topic to `_pkgdown.yml`.
Document user-visible changes in `NEWS.md`; small internal refactors do not
need entries.

## Git and Review

Use short, imperative commit subjects, matching repository history (for
example, `fix protected bugs`). Keep commits and pull requests focused. PR
descriptions should state what changed, why, compatibility or storage impact,
linked issues, and commands run. Include screenshots only when rendered
documentation changes materially.
