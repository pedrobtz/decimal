test_that("validation and canonicalization handle exact decimal strings", {
  x <- c("1.2300", "-0", "Infinity", "-Infinity", "NaN", "sNaN", NA_character_)

  expect_identical(
    decimal:::.decimal_validate_strings(x),
    c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, NA)
  )
  expect_identical(
    decimal:::.decimal_canonicalize_strings(x),
    x
  )
  expect_false(decimal:::.decimal_validate_strings("not-a-decimal"))
})

test_that("classification is context aware for zero, normal, and subnormal", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)

  set_decimal_context(decimal_context(precision = 3L, emin = -2L))
  expect_identical(
    decimal:::.decimal_classify_strings(c("0", "-0", "1E-2", "1E-3", "Infinity", "sNaN")),
    c("+Zero", "-Zero", "+Normal", "+Subnormal", "+Infinity", "sNaN")
  )
})

test_that("scientific and engineering formatting are available", {
  expect_identical(
    decimal:::.decimal_format_strings(c("12345", "0.00123"), style = "sci"),
    c("12345", "0.00123")
  )
  expect_identical(
    decimal:::.decimal_format_strings(c("12345", "0.000000123"), style = "eng"),
    c("12345", "123e-9")
  )
})

test_that("exact double conversion preserves IEEE 754 values", {
  expect_identical(
    decimal:::.decimal_from_double_strings(c(0.5, -0, Inf, -Inf, NaN, NA_real_)),
    c("0.5", "-0", "Infinity", "-Infinity", "NaN", NA_character_)
  )
  expect_identical(
    decimal:::.decimal_from_double_strings(0.1),
    "0.1000000000000000055511151231257827021181583404541015625"
  )
})

test_that("rounding modes apply through native context operations", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)

  set_decimal_context(decimal_context(precision = 2L, rounding = "half_even", traps = character()))
  expect_identical(decimal:::.decimal_apply_context("1.25"), "1.2")

  set_decimal_context(decimal_context(precision = 2L, rounding = "half_up", traps = character()))
  expect_identical(decimal:::.decimal_apply_context("1.25"), "1.3")

  set_decimal_context(decimal_context(precision = 2L, rounding = "half_down", traps = character()))
  expect_identical(decimal:::.decimal_apply_context("1.25"), "1.2")

  set_decimal_context(decimal_context(precision = 2L, rounding = "up", traps = character()))
  expect_identical(decimal:::.decimal_apply_context("1.21"), "1.3")

  set_decimal_context(decimal_context(precision = 2L, rounding = "down", traps = character()))
  expect_identical(decimal:::.decimal_apply_context("1.29"), "1.2")

  set_decimal_context(decimal_context(precision = 2L, rounding = "ceiling", traps = character()))
  expect_identical(decimal:::.decimal_apply_context("-1.29"), "-1.2")

  set_decimal_context(decimal_context(precision = 2L, rounding = "floor", traps = character()))
  expect_identical(decimal:::.decimal_apply_context("-1.21"), "-1.3")

  set_decimal_context(decimal_context(precision = 2L, rounding = "05up", traps = character()))
  expect_identical(decimal:::.decimal_apply_context("1.51"), "1.6")
})

test_that("signals become sticky flags and traps raise classed conditions", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)

  set_decimal_context(decimal_context(precision = 2L, traps = character()))
  clear_decimal_flags()
  expect_identical(decimal:::.decimal_apply_context("1.25"), "1.2")
  expect_identical(decimal_flags(), c("inexact", "rounded"))

  clear_decimal_flags()
  expect_identical(decimal:::.decimal_divide_strings("1", "0"), "Infinity")
  expect_true("division_by_zero" %in% decimal_flags())

  set_decimal_context(decimal_context(traps = "division_by_zero"))
  clear_decimal_flags()
  expect_error(
    decimal:::.decimal_divide_strings("1", "0"),
    class = "decimal_division_by_zero"
  )
})

test_that("string scale counts fractional digits net of the exponent", {
  expect_identical(
    decimal:::.decimal_string_scale(
      c("0", "123", "-123", "0.1", "1.23", "0.00", "1.500")
    ),
    c(0L, 0L, 0L, 1L, 2L, 2L, 3L)
  )

  # An exponent shifts the point, so the scale moves with it and may go negative
  expect_identical(
    decimal:::.decimal_string_scale(
      c("1E+2", "1e+2", "1.23E+5", "1.23e-5", "0E+10", "1E+000")
    ),
    c(-2L, -2L, -3L, 7L, -10L, 0L)
  )
})

test_that("string scale is NA where no fractional-digit count exists", {
  # NA, infinities and NaNs carry no scale
  expect_identical(
    decimal:::.decimal_string_scale(
      c(NA_character_, "Infinity", "-Infinity", "NaN", "-NaN", "sNaN")
    ),
    rep(NA_integer_, 6L)
  )

  # Forms that are not canonical decimal strings, including ones mpdecimal
  # itself would accept, such as a leading "+", a bare ".5" or a trailing "1."
  expect_identical(
    decimal:::.decimal_string_scale(
      c("", "abc", "1.2.3", "1,5", " 1.0", "1.0 ", "+1.0", "1.", ".5", "-.5",
        "1e", "1e+")
    ),
    rep(NA_integer_, 12L)
  )
})

test_that("string scale is NA when the exponent leaves integer range", {
  expect_identical(
    decimal:::.decimal_string_scale(
      c("1E+2147483647", "1E-2147483647", "1E+2147483648", "1E-2147483648",
        "1E+99999999999")
    ),
    c(-2147483647L, 2147483647L, NA_integer_, NA_integer_, NA_integer_)
  )
})

test_that("string scale rejects a non-character input", {
  expect_error(decimal:::.decimal_string_scale(1:3), "must be a character vector")
})
