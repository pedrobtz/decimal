# Package index

## Decimal values

- [`decimal()`](https://pedrobtz.github.io/decimal/dev/reference/decimal.md)
  : Construct decimal vectors
- [`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
  : Convert a vector to decimal
- [`decimal_from_double()`](https://pedrobtz.github.io/decimal/dev/reference/decimal_from_double.md)
  : Controlled conversion from double
- [`is_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/is_decimal.md)
  : Test whether an object is a decimal vector
- [`NA_decimal_`](https://pedrobtz.github.io/decimal/dev/reference/NA_decimal_.md)
  : Missing decimal scalar

## Decimal operations

- [`quantize()`](https://pedrobtz.github.io/decimal/dev/reference/quantize.md)
  : Quantize decimal values to a scale
- [`normalize()`](https://pedrobtz.github.io/decimal/dev/reference/normalize.md)
  : Remove unnecessary trailing zeros
- [`fma()`](https://pedrobtz.github.io/decimal/dev/reference/fma.md) :
  Fused multiply-add
- [`same_quantum()`](https://pedrobtz.github.io/decimal/dev/reference/same_quantum.md)
  : Compare decimal vector scales
- [`summary(`*`<decimal>`*`)`](https://pedrobtz.github.io/decimal/dev/reference/summary.decimal.md)
  : Summarise a decimal vector
- [`adjusted()`](https://pedrobtz.github.io/decimal/dev/reference/adjusted.md)
  : Compute the adjusted exponent
- [`number_class()`](https://pedrobtz.github.io/decimal/dev/reference/number_class.md)
  : Classify decimal values

## Decimal predicates

- [`is_qnan()`](https://pedrobtz.github.io/decimal/dev/reference/is_qnan.md)
  : Identify quiet NaN values
- [`is_snan()`](https://pedrobtz.github.io/decimal/dev/reference/is_snan.md)
  : Identify signaling NaN values
- [`is_normal()`](https://pedrobtz.github.io/decimal/dev/reference/is_normal.md)
  : Identify normal decimal values
- [`is_subnormal()`](https://pedrobtz.github.io/decimal/dev/reference/is_subnormal.md)
  : Identify subnormal decimal values
- [`is_signed()`](https://pedrobtz.github.io/decimal/dev/reference/is_signed.md)
  : Identify values with a negative sign
- [`is_zero()`](https://pedrobtz.github.io/decimal/dev/reference/is_zero.md)
  : Identify decimal zeros

## Arrow interoperability

- [`decimal_arrow`](https://pedrobtz.github.io/decimal/dev/reference/decimal_arrow.md)
  : Arrow interoperability
- [`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md)
  : Convert an Arrow table to a data frame, keeping decimal columns
  exact
- [`arrow_decimal_type()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_decimal_type.md)
  : Arrow type for a decimal column

## Contexts and signals

- [`decimal_context()`](https://pedrobtz.github.io/decimal/dev/reference/decimal_context.md)
  : Create a decimal arithmetic context
- [`get_decimal_context()`](https://pedrobtz.github.io/decimal/dev/reference/get_decimal_context.md)
  : Get the active decimal arithmetic context
- [`set_decimal_context()`](https://pedrobtz.github.io/decimal/dev/reference/set_decimal_context.md)
  : Set the active decimal arithmetic context
- [`local_decimal_context()`](https://pedrobtz.github.io/decimal/dev/reference/local_decimal_context.md)
  : Install a decimal context for the current scope
- [`with_decimal_context()`](https://pedrobtz.github.io/decimal/dev/reference/with_decimal_context.md)
  : Use a decimal context within a block
- [`decimal_flags()`](https://pedrobtz.github.io/decimal/dev/reference/decimal_flags.md)
  : Read sticky decimal flags
- [`clear_decimal_flags()`](https://pedrobtz.github.io/decimal/dev/reference/clear_decimal_flags.md)
  : Clear sticky decimal flags

## Package information

- [`mpdecimal_version()`](https://pedrobtz.github.io/decimal/dev/reference/mpdecimal_version.md)
  : Report the bundled mpdecimal runtime version
- [`decimal-package`](https://pedrobtz.github.io/decimal/dev/reference/decimal-package.md)
  : decimal: Arbitrary-Precision Decimal Vectors for R
