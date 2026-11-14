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

