# ADR 006: Arrow Extension Type over Decimal Storage

- **Status:** Accepted and implemented in 0.2.0
- **Scope:** Arrow interoperability boundary, decimal to Arrow direction

## Context

A `decimal` column can enter Arrow in three ways, and each loses something.

Before 0.2.0 arrow applied its generic `vctrs_extension_type`: storage was
`utf8` and the R round trip was exact, but every other reader saw a string
column.

Writing a plain `decimal128()` or `decimal256()` field gives other readers a
decimal and lets Arrow's compute engine filter and aggregate the column, but
arrow records an R column's attributes in the schema and reapplies them
blindly on read (`arrow:::apply_arrow_r_metadata()`, with a hard-coded
exemption list and no hook). A table this package wrote therefore came back
from `as.data.frame()`, `read_parquet()` and `collect()` as a double wearing
the `decimal` class. `format()` and `print()` showed rounded doubles with no
error, on the package's most common path.

An Arrow extension type whose storage is the real decimal keeps the storage
for other readers and gives this package the conversion back. Measured on
arrow 24: `read_parquet()` and `collect()` return the exact `decimal` vector;
DuckDB reads the same file as `DECIMAL(22,2)`; an arrow session without the
type registered gets the plain storage as a double. What it costs is
arrow-side compute on the column: `filter(amount > 50)`, `sum(amount)` and
`mutate(amount * 2)` evaluated inside arrow fail with "no kernel matching
input types", while selecting, collecting and filtering on other columns work.
A `cast()` inside the expression does not restore it.

## Decision

Write `decimal` vectors as an extension type named `r.decimal` whose storage
is `decimal128()` up to 38 digits of precision and `decimal256()` up to 76.

- `arrow::infer_type()` returns the extension type; `arrow::as_arrow_array()`
  wraps the cast storage in it.
- Passing a plain Arrow decimal type as `type` yields exactly that type, a
  plain field. `options(decimal.arrow_extension = FALSE)` does the same for
  every conversion. Both exist for workloads that need arrow-side compute.
- `arrow_decimal_type()` builds the extension type with a pinned precision
  and scale for columns that will be appended to.
- `format()` and `as.character()` refuse a `decimal` object whose data is not
  character, so a plain field read back through arrow's own conversion errors
  rather than printing rounded values. `arrow_as_data_frame()` reads such
  tables exactly.
- The type is registered from `.onLoad()`, or when arrow loads later.

## Consequences

The base case, write from R and read in R, is exact on every path and
improves on 0.1.0 without regressing it. Other systems see a decimal column.
Users who need Arrow compute on the column opt into plain fields and read
them with `arrow_as_data_frame()`.

The trade-off is inherent to arrow's R conversion model: a native type cannot
carry a third-party class back without arrow knowing the class, and an
extension type cannot enter Arrow compute. Should arrow add either a hook for
attribute reapplication or extension-aware compute, this decision should be
revisited.

## Code References

- `R/arrow.R`: `decimal_arrow_extension_class()`, `infer_type.decimal()`,
  `as_arrow_array.decimal()`, `arrow_decimal_type()`.
- `R/decimal.R`: `decimal_check_storage()`.
- `tests/testthat/test-arrow.R`: round-trip, plain-field and option tests.
- ADR 005 for the Arrow-to-decimal direction.
