# casting to a coarser decimal is a lossy cast (#50)

    Code
      vctrs::vec_cast(decimal("1.55"), to)
    Condition
      Error:
      ! Can't convert from `decimal("1.55")` <decimal> to <decimal> due to loss of precision.
      * Locations: 1

# casting text to a decimal type uses that type's scale (#51)

    Code
      vctrs::vec_cast(c("1.5", "1.123"), to)
    Condition
      Error:
      ! Can't convert from `c("1.5", "1.123")` <character> to <decimal> due to loss of precision.
      * Locations: 2

