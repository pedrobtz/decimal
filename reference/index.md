# Package index

## Decimal values

- [`decimal()`](https://pedrobtz.github.io/decimal/reference/decimal.md)
  : Construct decimal vectors
- [`as_decimal()`](https://pedrobtz.github.io/decimal/reference/as_decimal.md)
  : Convert a vector to decimal
- [`decimal_from_double()`](https://pedrobtz.github.io/decimal/reference/decimal_from_double.md)
  : Controlled conversion from double
- [`is_decimal()`](https://pedrobtz.github.io/decimal/reference/is_decimal.md)
  : Test whether an object is a decimal vector
- [`NA_decimal_`](https://pedrobtz.github.io/decimal/reference/NA_decimal_.md)
  : Missing decimal scalar

## Decimal operations

- [`quantize()`](https://pedrobtz.github.io/decimal/reference/quantize.md)
  : Quantize decimal values to a scale
- [`normalize()`](https://pedrobtz.github.io/decimal/reference/normalize.md)
  : Remove unnecessary trailing zeros
- [`fma()`](https://pedrobtz.github.io/decimal/reference/fma.md) : Fused
  multiply-add
- [`same_quantum()`](https://pedrobtz.github.io/decimal/reference/same_quantum.md)
  : Compare decimal vector scales
- [`adjusted()`](https://pedrobtz.github.io/decimal/reference/adjusted.md)
  : Compute the adjusted exponent
- [`number_class()`](https://pedrobtz.github.io/decimal/reference/number_class.md)
  : Classify decimal values

## Decimal predicates

- [`is_qnan()`](https://pedrobtz.github.io/decimal/reference/is_qnan.md)
  : Identify quiet NaN values
- [`is_snan()`](https://pedrobtz.github.io/decimal/reference/is_snan.md)
  : Identify signaling NaN values
- [`is_normal()`](https://pedrobtz.github.io/decimal/reference/is_normal.md)
  : Identify normal decimal values
- [`is_subnormal()`](https://pedrobtz.github.io/decimal/reference/is_subnormal.md)
  : Identify subnormal decimal values
- [`is_signed()`](https://pedrobtz.github.io/decimal/reference/is_signed.md)
  : Identify values with a negative sign
- [`is_zero()`](https://pedrobtz.github.io/decimal/reference/is_zero.md)
  : Identify decimal zeros

## Contexts and signals

- [`decimal_context()`](https://pedrobtz.github.io/decimal/reference/decimal_context.md)
  : Create a decimal arithmetic context
- [`get_decimal_context()`](https://pedrobtz.github.io/decimal/reference/get_decimal_context.md)
  : Get the active decimal arithmetic context
- [`set_decimal_context()`](https://pedrobtz.github.io/decimal/reference/set_decimal_context.md)
  : Set the active decimal arithmetic context
- [`local_decimal_context()`](https://pedrobtz.github.io/decimal/reference/local_decimal_context.md)
  : Install a decimal context for the current scope
- [`with_decimal_context()`](https://pedrobtz.github.io/decimal/reference/with_decimal_context.md)
  : Use a decimal context within a block
- [`decimal_flags()`](https://pedrobtz.github.io/decimal/reference/decimal_flags.md)
  : Read sticky decimal flags
- [`clear_decimal_flags()`](https://pedrobtz.github.io/decimal/reference/clear_decimal_flags.md)
  : Clear sticky decimal flags

## Package information

- [`mpdecimal_version()`](https://pedrobtz.github.io/decimal/reference/mpdecimal_version.md)
  : Report the bundled mpdecimal runtime version
- [`decimal-package`](https://pedrobtz.github.io/decimal/reference/decimal-package.md)
  : decimal: Arbitrary-Precision Decimal Vectors for R
