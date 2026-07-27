# Testing

## Test Layout

The package uses testthat edition 3. Tests live in `tests/testthat/` and mirror
the production concern:

- `test-decimal.R` — construction, scale, conversion, vctrs, serialization.
- `test-context.R` — context lifecycle, flags, warnings, and traps.
- `test-operators.R` — arithmetic, comparison, equality, and ordering.
- `test-math.R` — Math/Summary methods and decimal-specific helpers.
- `test-native-core.R` — exact native conversion and kernel behavior.
- `test-mpdecimal-version.R` — startup and vendored-version checks.

Name new files `test-<module>.R` and use focused
`test_that("<observable behavior>", ...)` blocks. Put regressions beside the
closest existing behavior.

## Commands

```sh
# Run one test file or group while iterating
Rscript -e "devtools::test(filter = 'context')"

# Run the complete unit suite
Rscript -e "devtools::test()"

# Run the release-level package check
Rscript -e "devtools::check()"
```

Use `devtools::test_active_file("R/<module>.R")` when production and test file
names align.

## Expectations

Cover zero-length and recycled vectors, names, `NA`, qNaN, sNaN, infinities,
signed zero, scale changes, all applicable rounding modes, sticky flags, and
trapped signals. Test both argument orders for type interactions. Verify
results with specific expectations such as `expect_identical()`. Snapshot
complete user-facing warnings and errors with `expect_snapshot()` or
`expect_snapshot(error = TRUE)`.

Context-sensitive tests must restore global state. Prefer
`with_decimal_context()` or `local_decimal_context()` and use `withr` for
options. `tests/testthat/setup.R` disables routine flag reporting globally;
warning tests must re-enable it locally.

## Native Validation

Every `.Call` entry must be registered, use fixed arity, and keep dynamic
symbols disabled. Native loops must exercise missing values, special values,
allocation/error cleanup, and interrupt checks. For native changes, manually
dispatch `.github/workflows/native-checks.yaml`, which runs sanitizers,
Valgrind, LTO, gctorture, and rchk.

## Coverage Policy

No numeric threshold is configured. The aggregate report includes vendored
`src/mpdecimal/`, whose internal algorithms depend on operand size and should
not be targeted with artificial tests. Judge first-party coverage separately
for `R/`, `src/core.c`, `src/decimal.c`, and `src/init.c`; prioritize meaningful
behavior and failure paths.
