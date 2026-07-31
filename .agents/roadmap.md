# Product Roadmap

## Purpose

This document records product direction and release-level outcomes. The
committed next-release scope lives in the
[0.2.0 Release Plan](release-0.2.0-plan.md), while the broader numerical
backlog lives in [Feature Expansion Plan](feature-expansion-plan.md). Durable
design choices live in [decisions/](decisions/).

## Current Baseline: 0.1.0

The first functional release is implemented. It provides:

- exact character and integer parsing, context-free shared-scale promotion,
  and explicit double decoding followed by quantization;
- character-backed `vctrs` vectors with one shared scale;
- active contexts with rounding, exponent limits, traps, and sticky flags;
- vectorized arithmetic, comparison, ordering, Math, and Summary methods;
- `NA`, infinities, qNaN, sNaN, and signed-zero behavior;
- decimal helpers including `quantize()`, `normalize()`, `fma()`,
  `same_quantum()`, `adjusted()`, and `number_class()`;
- cross-platform R CMD check, coverage, and manually dispatched native checks.

The lifecycle remains early: correctness and a coherent R API take priority
over feature parity with Python's `decimal` module.

## Next: 0.2.0 Decimal Toolbox

Prioritize Python-inspired operations with clear R-vector use cases:

1. Rich formatting and adjacent representable values.
2. Remainder-near, sign copying, magnitude extrema, exponent shifting, and a
   combined quotient/remainder operation.
3. Total comparisons with an R-appropriate return contract.

The release scope, exclusions, sequence, and gates are maintained in the
[0.2.0 Release Plan](release-0.2.0-plan.md). The broader executable backlog
remains in [Feature Expansion Plan](feature-expansion-plan.md).

## Later Themes

### Integrations

Explore fixed-scale or money subclasses, database and Arrow/DBI conversion,
and a stable downstream C API only after concrete use cases define the
contracts.

### Performance

Profile realistic workloads before changing representation. Cached native
values, ALTREP, or compact binary storage are options only if they preserve
exact round trips, special values, serialization, and the public scale
contract.

### Deferred Features

Digit-logical operations, rotate/shift, base limb import/export, and
multithreaded kernels remain demand-driven. Do not expose libmpdec functions
solely to increase API or coverage counts.

## Compatibility Snapshot

| Capability | Status | Notes |
| --- | --- | --- |
| Exact parsing and lossless default formatting | Implemented | Finer-scale promotion is exact; double conversion quantizes explicitly |
| Contexts, traps, and sticky flags | Implemented | Session-scoped, with local helpers |
| Arithmetic and comparison | Implemented | Vectorized; no implicit decimal/double mixing |
| Math and summaries | Implemented | Core Math/Summary methods |
| Special values | Implemented | R `NA`, infinities, NaNs, signed zero |
| Total-order public API | Planned | Internal ordering already supports vctrs |
| Advanced libmpdec operations | Planned selectively | See the feature expansion plan |
| Fixed-scale subclasses and integrations | Deferred | Requires separate design decisions |
| Alternative storage or ALTREP | Deferred | Requires profiling and migration design |

## Release Gates

Each roadmap slice must preserve the accepted ADRs, include behavior and native
tests, document every public API, pass cross-platform R CMD check, and complete
relevant native robustness workflows. See [Testing](testing.md) and
[Release Process](release-process.md).
