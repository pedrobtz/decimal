test_that("Math and Math2 methods operate on decimal vectors", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(precision = 10L, traps = character()))

  expect_identical(abs(decimal("-1.2300")), decimal("1.2300"))
  expect_identical(sign(decimal(c("-2", "0", "3"))), decimal(c("-1", "0", "1")))
  expect_identical(sqrt(decimal("4")), decimal("2"))
  expect_identical(floor(decimal("-1.2")), decimal("-2"))
  expect_identical(ceiling(decimal("-1.2")), decimal("-1"))
  expect_identical(trunc(decimal("-1.2")), decimal("-1"))
  expect_identical(round(decimal("1.25"), digits = 1), decimal("1.2"))
  expect_identical(signif(decimal("1234.5"), digits = 3), decimal("1.23E+3"))
  expect_identical(exp(decimal("1")), decimal("2.718281828"))
  expect_identical(log(decimal("100"), base = 10L), decimal("2"))
  expect_identical(log10(decimal("1000")), decimal("3"))
})

test_that("missingness and finiteness predicates follow decimal semantics", {
  x <- decimal(c("1", "NaN", "sNaN", "Infinity", "-0", NA_character_))

  expect_identical(is.na(x), c(FALSE, TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(is.nan(x), c(FALSE, TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(is.finite(x), c(TRUE, FALSE, FALSE, FALSE, TRUE, FALSE))
  expect_identical(is.infinite(x), c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE))

  expect_identical(is_qnan(x), c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(is_snan(x), c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(is_zero(x), c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE))
  expect_identical(is_signed(x), c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE))
})

test_that("classification helpers expose decimal-specific state", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(precision = 3L, emin = -2L))

  x <- decimal(c("1.2300", "1E-3", "-0", "Infinity", "NaN", NA_character_))

  expect_identical(number_class(x), c("+Normal", "+Subnormal", "-Zero", "+Infinity", "NaN", NA_character_))
  expect_identical(adjusted(x), c(0L, -3L, 0L, NA_integer_, NA_integer_, NA_integer_))
  expect_identical(is_normal(x), c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(is_subnormal(x), c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(same_quantum(decimal(c("1.20", "1.2", NA_character_)),
                                decimal(c("2.30", "2.30", "1"))),
                   c(TRUE, FALSE, NA))
})

test_that("decimal-specific operations use context-aware kernels", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(precision = 3L, traps = character()))

  expect_identical(quantize(decimal("1.2345"), decimal("0.01")), decimal("1.23"))
  expect_identical(normalize(decimal(c("1.2300", "-0.00"))), decimal(c("1.23", "-0")))
  expect_identical(fma(decimal("2"), decimal("3"), decimal("4")), decimal("10"))
})

test_that("summaries handle empty inputs, na.rm, and NaN propagation", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))

  x <- decimal(c("1.20", "2.30", NA_character_, "NaN"))

  expect_identical(sum(decimal(c("1.20", "2.30"))), decimal("3.50"))
  expect_identical(prod(decimal(c("1.20", "2"))), decimal("2.40"))
  expect_identical(sum(x, na.rm = TRUE), decimal("3.50"))
  expect_identical(prod(x, na.rm = TRUE), decimal("2.7600"))
  expect_identical(mean(decimal(c("1", "2", "3"))), decimal("2"))
  expect_identical(mean(x, na.rm = TRUE), decimal("1.75"))

  expect_identical(sum(decimal(c(NA_character_, "1"))), NA_decimal_)
  expect_identical(sum(decimal(c("NaN", "1"))), decimal("NaN"))
  expect_true("invalid_operation" %in% {
    clear_decimal_flags()
    sum(decimal(c("sNaN", "1")))
    decimal_flags()
  })

  expect_identical(sum(decimal(), na.rm = TRUE), decimal("0"))
  expect_identical(prod(decimal(), na.rm = TRUE), decimal("1"))
  expect_identical(mean(decimal(), na.rm = TRUE), decimal("NaN"))
})

test_that("ordering summaries return decimal infinities on empty input", {
  expect_warning(expect_identical(min(decimal(), na.rm = TRUE), decimal("Infinity")),
                 "no non-missing arguments to min")
  expect_warning(expect_identical(max(decimal(), na.rm = TRUE), decimal("-Infinity")),
                 "no non-missing arguments to max")
  expect_warning(expect_identical(range(decimal(), na.rm = TRUE), decimal(c("Infinity", "-Infinity"))),
                 "no non-missing arguments to min")

  x <- decimal(c("2", "-1", "NaN", NA_character_))
  expect_identical(min(x, na.rm = TRUE), decimal("-1"))
  expect_identical(max(x, na.rm = TRUE), decimal("2"))
  expect_identical(range(x, na.rm = TRUE), decimal(c("-1", "2")))
  expect_identical(min(decimal(c("NaN", "1"))), decimal("NaN"))
  expect_identical(range(decimal(c(NA_character_, "1"))), c(NA_decimal_, NA_decimal_))
})
