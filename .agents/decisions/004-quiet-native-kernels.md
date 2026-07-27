# ADR 004: Quiet, Vectorized Native Kernels

- **Status:** Accepted and implemented in 0.1.0
- **Scope:** R-to-C safety boundary

## Context

libmpdec offers signaling operations that may invoke its trap handler
immediately. That behavior conflicts with R's condition system and makes it
difficult to clean native allocations, aggregate vector statuses, or identify
the first failing element safely.

## Decision

Use quiet `mpd_q*` functions inside package-owned vector kernels.

- R casts and recycles operands before calling C, so native kernels receive
  compatible, equal-length vectors.
- C parses exact strings, allocates temporary `mpd_t` values, and processes
  each vector element.
- Kernels aggregate status bits and record the first trapped element rather
  than invoking a libmpdec trap handler.
- Results return as a list containing values, flags, trap signal, and trap
  index. `decimal_native_result()` translates that metadata into R state and
  classed conditions after native cleanup.
- Kernels propagate `NA`, use `R_xlen_t`, check interrupts periodically, and
  register fixed-arity `.Call` routines with dynamic symbols disabled.

## Consequences

R retains control of warnings and errors, vector operations report useful
element indexes, and native resources can be released before unwinding. The
cost is more package-owned kernel and dispatch code, plus explicit auditing of
allocation, protection, and cleanup paths for every new operation.

## Code References

- `R/native-core.R`: `decimal_context_call()` and `decimal_native_result()`.
- `src/core.c`: parsing helpers, result helpers, and `decimal_c_*` kernels.
- `src/init.c`: `CallEntries` and `R_init_decimal()`.
- `.github/workflows/native-checks.yaml`: native robustness checks.
