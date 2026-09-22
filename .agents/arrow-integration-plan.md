# Arrow Integration Plan

**Status:** Items 1 to 3 implemented in `R/arrow.R` (2026-09-22); item 4
remains deferred. Arrow integration is in the committed 0.2.0 scope in
[release-0.2.0-plan.md](release-0.2.0-plan.md), and [roadmap.md](roadmap.md)
lists it under 0.2.0 rather than later themes. The trust decision is recorded
in [ADR 005](decisions/005-arrow-string-cast-canonical.md) and the choice of
an extension type over decimal storage, made after review, in
[ADR 006](decisions/006-arrow-extension-type.md).

## Objective

Give first-class, exact conversion between `decimal` vectors and Arrow
`decimal128` / `decimal256` arrays in both directions, in R code only, without
touching the native kernels.

## Current state before this work

- `vignettes/arrow-decimal-types.Rmd` documents the lossless path: cast the
  Arrow array to `arrow::string()`, pull the character vector, build with
  `decimal()`. Nothing is exported; the vignette's `from_arrow_decimal()` and
  `to_arrow_decimal()` helpers are code users must copy.
- `arrow` is in `Suggests`. `nanoarrow` is not a dependency.
- Arrow to decimal is correct but slow. For 1e6 `decimal128(20, 2)` values,
  Arrow's cast and pull take 0.06s and our `decimal()` constructor takes
  1.05s, almost all of it in `decimal_c_canonicalize_strings()` re-parsing
  strings that are already canonical. The lossy `as.vector()` to double takes
  0.11s, so exact conversion is ten times slower than the lossy default.
- Decimal to Arrow has a real gap. `arrow::infer_type()` on a `decimal`
  vector returns arrow's generic `vctrs_extension_type` over `utf8` storage
  (it prints as `<decimal[0]>`). `arrow_table()`, `write_parquet()` and
  `write_dataset()` therefore emit a string column with vctrs metadata. It
  round-trips inside R but Spark, DuckDB, pandas and every other reader see
  text, not a decimal.

## Key finding: Arrow's string cast is our canonical form

Arrow's decimal-to-string cast and `mpd_to_sci()` both implement the General
Decimal Arithmetic "to-scientific-string" rule: plain notation when
`scale >= 0` and the adjusted exponent is at least -6, otherwise scientific.

A property check over about 5,200 random values, eleven scales from -5 to 70,
both `decimal128` and `decimal256`, negatives, zeros and trailing zeros found
exactly one difference: Arrow writes the exponent letter as `E`, we write `e`
(the package calls `mpd_to_sci(dec, 0)`, which selects lowercase). After
folding `E` to `e` there were zero mismatches.

Arrow's `utf8_lower` compute kernel performs that fold in C++ (0.04s per
1e6). The result can go straight into `new_decimal(x, scale, validate =
FALSE)`, the package's own trusted internal constructor.

Measured, 1e6 `decimal128(20, 2)` values, median of three:

| Path | Time |
| --- | --- |
| Documented path (cast, pull, `decimal()`) | 1.11s |
| Cast, `utf8_lower`, pull, `new_decimal()` untrusted off | 0.10s |
| Same on a two-chunk `ChunkedArray` | 0.10s |
| Runtime verification pass in C, if wanted | about +0.3s |

Results are `identical()` to the documented path, including exponent-bearing
values such as `1E-10` and `-2.5E+7`.

Decision taken: trust Arrow's formatting. The property test lives in
`tests/testthat/test-arrow.R` and the invariant in ADR 005. The cast is deterministic C++ following a published spec, the
property test guards against drift, and verification would turn an
eleven-fold gain into a three-fold one.

## Work items, in order of value

### 1. `as_decimal()` methods for `Array` and `ChunkedArray` — done

- The generic is this package's, so `S3method(as_decimal, Array)` and
  `S3method(as_decimal, ChunkedArray)` register in NAMESPACE with no arrow
  dependency at load time; they dispatch only when an arrow object arrives.
- Inside: `rlang::check_installed("arrow")`, then
  `x$cast(arrow::string())`, `arrow::call_function("utf8_lower", ...)`,
  `as.vector()`, `new_decimal(chr, scale = x$type$scale())`.
- Scale from the type. The existing `scale` argument overrides through
  `decimal_set_scale()`.
- `decimal256` needs nothing extra; the cast path is identical.
- Names: none (Arrow arrays carry none).
- As built, a non-decimal Arrow array is not an error: it converts to R with
  `as.vector()` and then follows the ordinary `as_decimal()` rules for that R
  type, so string and integer arrays work without a special case.
- Tests (skipped without arrow): nulls, both widths, negative scale, chunked
  input, the `1E-10` fold, and the property test above at a modest size.

### 2. `infer_type.decimal()` and `as_arrow_array.decimal()` — done

- Register with `vctrs::s3_register("arrow::infer_type", "decimal")` and
  `vctrs::s3_register("arrow::as_arrow_array", "decimal")` in `.onLoad()`.
- Type: `decimal128(p, s)` when `p <= 38`, `decimal256(p, s)` when
  `p <= 76`, error above. `s` is the vector's scale.
- Precision inference: `max(adjusted(x), na.rm = TRUE) + 1L + scale`,
  floored at 1. The `adjusted()` kernel already exists in C (0.32s per 1e6).
  The generic's `type` argument lets the caller pin a wider type, which is
  the right choice for a column that will be appended to.
- Conversion: `arrow::Array$create(vctrs::vec_data(x))$cast(type)`.
  Measured 0.21s to create the string array plus 0.04s to cast, per 1e6.
- Infinity and NaN have no Arrow decimal; error with a clear message.
  Today they round-trip through the extension type, so this is a behaviour
  change that needs a NEWS entry.
- Tests: `arrow_table()` on a data frame with a decimal column yields a
  decimal field; `write_parquet()` then `read_parquet(as_data_frame = FALSE)`
  returns the same type; item 1 reads it back `identical()`.

### 3. Table-level helper — done, as `arrow_as_data_frame()`

`as.data.frame()` on an arrow `Table` silently turns decimal columns into
doubles. `arrow_as_data_frame()` takes a `Table` or `RecordBatch`, converts
each decimal field through item 1, leaves every other column to arrow's own
`as.vector()`, and returns a data frame. Per-column casts were kept instead of
one schema cast: the total work is the same, and reusing the exported
`as_decimal()` path keeps one implementation of the canonical-form assumption.

Review found that a plain decimal field regresses the base case: arrow
records an R column's attributes in the schema's R metadata and reapplies them
blindly on the way back (`arrow:::apply_arrow_r_metadata()`, whose exemption
list is hard-coded with no hook), so a table written from a `decimal` column
came back from `as.data.frame()`, `read_parquet()` and `collect()` as a double
wearing the `decimal` class, printing rounded values with no error. The
resolution, an extension type whose storage is the real decimal, is
[ADR 006](decisions/006-arrow-extension-type.md). Plain fields remain
available through `type` and `options(decimal.arrow_extension = FALSE)` for
arrow-side compute, `arrow_as_data_frame()` reads them exactly, and
`format()` now refuses a double-backed decimal object.

### 4. Deferred: native import through nanoarrow

Feasible: `nanoarrow` ships `include/nanoarrow/r.h` with the Arrow C Data
Interface structs and external-pointer accessors, decimal buffers are 16 or
32 byte little-endian two's-complement integers, and mpdecimal offers
`mpd_qimport_u32()` for base 2^32 limbs. Not needed for speed: Arrow's own
cast beats any per-element import we would write. Its only real use is input
that arrives as a nanoarrow array without the arrow package, for example
ADBC results. Leave deferred until that use case appears, per the roadmap.

## Not in scope

- Anything native. Items 1 to 3 are R only, so the native check gates do not
  apply.
- The `decimal()` name collision with `arrow::decimal()`; the vignette already
  documents qualifying calls.

## Documentation and gates

- Roxygen for every new export, `_pkgdown.yml` entries, NEWS.
- Rewrite `vignettes/arrow-decimal-types.Rmd` around the exported API.
- Record the "Arrow string cast equals canonical form" invariant and the
  trust decision as an ADR.
- Move Arrow integration from exclusions to scope in
  `release-0.2.0-plan.md` and update `roadmap.md`.
- All arrow-dependent tests use `skip_if_not_installed("arrow")`.
