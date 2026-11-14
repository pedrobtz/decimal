# a pinned type narrower than the values errors instead of wrapping

    Code
      arrow::as_arrow_array(decimal(strrep("9", 39)), type = arrow_decimal_type(38, 0))
    Condition
      Error in `arrow::as_arrow_array()`:
      ! `x` needs 39 digits of precision at scale 0, more than the 38 of `decimal128(38, 0)`.

# arrow_decimal_type() rejects a scale above the precision

    Code
      arrow_decimal_type(1, 2)
    Condition
      Error in `arrow_decimal_type()`:
      ! `scale` (2) must not exceed `precision` (1); Parquet rejects such a type.

