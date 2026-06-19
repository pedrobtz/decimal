test_that("decimal arithmetic is vectorized and type stable", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))

  expect_identical(decimal("1.20") + decimal("2.3"), decimal("3.50"))
  expect_identical(decimal("5.0") - 2L, decimal("3.0"))
  expect_identical(2L * decimal("1.50"), decimal("3.00"))
  expect_identical(decimal("7") / decimal("2"), decimal("3.5"))
  expect_identical(decimal("2") ^ decimal("3"), decimal("8"))
  expect_identical(decimal("-7") %% decimal("4"), decimal("-3"))
  expect_identical(decimal("-7") %/% decimal("4"), decimal("-1"))
  expect_identical(+decimal(c("1.20", NA_character_)), decimal(c("1.20", NA_character_)))
  expect_identical(-decimal(c("1.20", "-0")), decimal(c("-1.20", "0")))

  expect_identical(decimal(c("1", "2")) + 1L, decimal(c("2", "3")))
  expect_error(decimal("1") + 0.5, class = "vctrs_error_incompatible_op")
  expect_error(0.5 + decimal("1"), class = "vctrs_error_incompatible_op")
})

test_that("decimal arithmetic respects context flags and traps", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)

  set_decimal_context(decimal_context(precision = 2L, traps = character()))
  clear_decimal_flags()
  expect_identical(decimal("1.25") + decimal("0"), decimal("1.2"))
  expect_identical(decimal_flags(), c("inexact", "rounded"))

  set_decimal_context(decimal_context(traps = "division_by_zero"))
  clear_decimal_flags()
  expect_error(decimal("1") / decimal("0"), class = "decimal_division_by_zero")
})

test_that("comparison operators avoid double conversion and handle special values", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)

  set_decimal_context(decimal_context(traps = character()))
  clear_decimal_flags()

  expect_identical(decimal("1.0") == decimal("1"), TRUE)
  expect_identical(decimal("1.0") != decimal("2"), TRUE)
  expect_identical(decimal("-2") < decimal("1"), TRUE)
  expect_identical(decimal("-2") <= decimal("-2.0"), TRUE)
  expect_identical(decimal("3") > 2L, TRUE)
  expect_identical(2L >= decimal("2.0"), TRUE)
  expect_identical(decimal(c("1", NA_character_)) < decimal(c("2", "3")), c(TRUE, NA))

  expect_identical(decimal("NaN") == decimal("1"), NA)
  expect_identical(decimal("NaN") != decimal("1"), NA)
  expect_identical(decimal("NaN") < decimal("1"), NA)
  expect_identical(decimal_flags(), character())

  expect_identical(decimal("sNaN") == decimal("1"), NA)
  expect_true("invalid_operation" %in% decimal_flags())

  set_decimal_context(decimal_context(traps = "invalid_operation"))
  clear_decimal_flags()
  expect_error(decimal("sNaN") < decimal("1"), class = "decimal_invalid_operation")
})

test_that("equality and ordering proxies support matching and sorting", {
  x <- decimal(c("1.0", "1", "-0", "0", "NaN", "NaN", NA_character_, "2", "-2"))

  expect_identical(vctrs::vec_equal(decimal("1.0"), decimal("1"), na_equal = TRUE), TRUE)
  expect_identical(vctrs::vec_equal(decimal("-0"), decimal("0"), na_equal = TRUE), TRUE)
  expect_identical(vctrs::vec_equal(decimal("NaN"), decimal("NaN"), na_equal = TRUE), TRUE)

  expect_identical(unique(x), decimal(c("1.0", "-0", "NaN", NA_character_, "2", "-2")))
  expect_identical(vctrs::vec_match(decimal(c("1", "-0", "NaN", NA_character_)), x), c(1L, 3L, 5L, 7L))

  expect_identical(
    sort(decimal(c("2", "-2", "0", "-0", "1.0", "1", "Infinity", "-Infinity", "NaN"))),
    decimal(c("-Infinity", "-2", "0", "-0", "1.0", "1", "2", "Infinity", "NaN"))
  )
})
