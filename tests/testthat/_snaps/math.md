# pmax() and pmin() refuse a later argument with a finer scale

    Code
      pmax(x, y)
    Condition
      Error in `pmax()`:
      ! `pmax()` can't take a decimal with a finer scale than its first argument.
      i The first argument has scale 0; a later one has scale 1.
      i Give every argument the same scale, for example with `as_decimal(x, scale = )`, or pass the finest-scaled one first.

# a quantize trap on a special value does not blame the precision

    Code
      round(decimal("sNaN"))
    Condition
      Error in `decimal_native_result()`:
      ! Decimal trap during `quantize` at element 1: invalid_operation.
      i A signaling NaN raises `invalid_operation` when used.

---

    Code
      quantize(decimal("Infinity"), decimal("1"))
    Condition
      Error in `decimal_native_result()`:
      ! Decimal trap during `quantize` at element 1: invalid_operation.
      i Quantizing an infinity to a finite quantum, or a finite value to an infinite quantum, is an invalid operation.

