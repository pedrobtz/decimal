# Assurance

How this package meets `.claude/shared/assurance.md`. CI checks this
file (r-actions `assurance.yml`), so keep the headings and table
columns as they are.

- **Statuses:** a cell is a fact, `gap #<issue>` or `n/a: <reason>`.

## Kinds

`compiled` `untrusted-input` `spec` `emits`

Evidence: compiled, src/core.c plus vendored mpdecimal 4.0.1.
Untrusted input, decimal text from users, files, databases and Arrow's
string cast, parsed by mpdecimal and by the package's own fractional-digit
scanner in C. Spec, IBM General Decimal Arithmetic through mpdecimal, and
IEEE 754 binary64 for double conversion. Emits, Arrow arrays and Parquet
files read by other systems. No object outlives its call (no external
pointers, ALTREP or handles; the context is an R list), so the package has
no Objects table.

## Required checks

| Check         | Status | Where              |
| ------------- | ------ | ------------------ |
| sanitizers    | done   | native-checks.yaml |
| valgrind      | done   | native-checks.yaml |
| rchk          | done   | native-checks.yaml |
| gctorture     | done   | native-checks.yaml |
| analyzers     | gap #0 |                    |
| alloc-failure | gap #0 |                    |
| mutation      | gap #0 |                    |
| fuzz          | gap #0 |                    |
| fuzz-reach    | gap #0 |                    |

## Boundaries

<!-- markdownlint-disable MD013 -->
| Boundary                                    | Oracle                                                                                    | Carried by                                  |
| ------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------- |
| decimal text parse and canonical form       | hand-written expected strings only                                                        | gap #0                                      |
| fractional-digit scan of text (own C)       | hand-written cases, INT range straddled; no differential against the parsed exponent      | gap #0                                      |
| double to decimal (exact)                   | hand-written IEEE cases (`0.1`, `-0`, specials)                                           | gap #0                                      |
| decimal to double                           | hand-written cases only; no round trip over random doubles                                | gap #0                                      |
| arithmetic, Math, quantize, fma vs the spec | hand-written expected values; mpdecimal's decTest vectors are not run                     | gap #0                                      |
| order and equality proxy keys               | 20-value hand-sorted list and equal-key list; no property test against `mpd_cmp()`        | gap #0                                      |
| Arrow decimal to `decimal`                  | property test: Arrow's string cast against `decimal()` re-parse, all four widths          | tests/testthat/test-arrow.R                 |
| `decimal` to Arrow / Parquet                | round trip through arrow, and a reader without the extension type; no independent reader  | gap #0                                      |
<!-- markdownlint-enable MD013 -->

## Limits

| Limit                                | Unit                 | Straddled by                     |
| ------------------------------------ | -------------------- | -------------------------------- |
| scale within `INT_MAX`               | fractional digits    | tests/testthat/test-native-core.R |
| context `precision` 1..MPD_MAX_PREC  | digits               | gap #0                           |
| context `emax` / `emin`              | exponent             | gap #0                           |
| decimal128 / decimal256 at 38 / 76   | digits of precision  | gap #0                           |
