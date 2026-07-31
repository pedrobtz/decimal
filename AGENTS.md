# Repository Guidelines

This repository contains `decimal`, an R package for exact,
arbitrary-precision decimal vectors. It combines an R and `vctrs`
interface with registered C kernels backed by the vendored `mpdecimal`
4.0.1 library.

## Documentation Map

Read the documents relevant to a change before editing:

- [Architecture](https://pedrobtz.github.io/decimal/.agents/architecture.md)
  — runtime layers, native boundary, and data flow.
- [Package
  design](https://pedrobtz.github.io/decimal/.agents/package-design.md)
  — public API, invariants, and extension points.
- [Product
  roadmap](https://pedrobtz.github.io/decimal/.agents/roadmap.md) —
  current baseline, next releases, and deferred themes.
- [0.2.0 release
  plan](https://pedrobtz.github.io/decimal/.agents/release-0.2.0-plan.md)
  — committed scope, exclusions, sequencing, and release gates for the
  next release.
- [Feature expansion
  plan](https://pedrobtz.github.io/decimal/.agents/feature-expansion-plan.md)
  — detailed, task-by-task work for advanced libmpdec operations.
- [Testing](https://pedrobtz.github.io/decimal/.agents/testing.md) —
  test layout, commands, and coverage policy.
- [Release
  process](https://pedrobtz.github.io/decimal/.agents/release-process.md)
  — documentation, CI, and CRAN release gates.
- [Conventions](https://pedrobtz.github.io/decimal/.agents/conventions.md)
  — R, C, documentation, Git, and vendored-code rules.
- [ADR
  001](https://pedrobtz.github.io/decimal/.agents/decisions/001-r-native-vector-api.md)
  — R-native vector interface and type compatibility.
- [ADR
  002](https://pedrobtz.github.io/decimal/.agents/decisions/002-character-backed-shared-scale.md)
  — character-backed storage and shared scale.
- [ADR
  003](https://pedrobtz.github.io/decimal/.agents/decisions/003-session-scoped-arithmetic-context.md)
  — session context, traps, and sticky flags.
- [ADR
  004](https://pedrobtz.github.io/decimal/.agents/decisions/004-quiet-native-kernels.md)
  — native safety and signal aggregation.

## Working Agreement

Keep changes focused and preserve the package invariants described
above. User-facing behavior requires a test and, when applicable,
roxygen documentation, `_pkgdown.yml`, and a `NEWS.md` entry. Edit
`README.Rmd`, not generated `README.md`; edit roxygen source, not
generated `man/` files or `NAMESPACE`.

For routine development, run:

``` sh
Rscript -e "devtools::load_all()"
Rscript -e "devtools::test()"
Rscript -e "devtools::document()"
Rscript -e "devtools::check()"
```

Run focused tests while iterating, then the complete suite and package
check. Native changes also require the manual sanitizer, Valgrind, LTO,
gctorture, and rchk workflows described in
[Testing](https://pedrobtz.github.io/decimal/.agents/testing.md).

## Pull Requests

Use short, imperative commit subjects. Pull requests should explain the
user-visible behavior and design impact, link related issues, list
validation commands, and include all generated documentation changes. Do
not mix unrelated cleanup with a functional change.
