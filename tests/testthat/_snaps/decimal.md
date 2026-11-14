# casting to a coarser decimal is a lossy cast (#50)

    Code
      vctrs::vec_cast(decimal("1.55"), to)
    Condition
      Error:
      ! Can't convert from `decimal("1.55")` <decimal> to <decimal> due to loss of precision.
      * Locations: 1

