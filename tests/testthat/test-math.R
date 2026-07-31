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

  # exp/log/log10 have no exact terminating scale: mpdecimal computes to the
  # active context's precision, and that computed precision becomes the
  # result's scale (rather than collapsing to the input's, often coarser,
  # scale).
  expect_identical(exp(decimal("1")), decimal("2.718281828"))
  expect_identical(log(decimal("100"), base = 10L), decimal("2"))
  expect_identical(log10(decimal("1000")), decimal("3"))
})

test_that("round() supports rounding into the integer part with a negative scale", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))

  x <- round(decimal("7692.98"), digits = -3)
  expect_identical(x, decimal("8E+3"))
  expect_identical(attr(x, "scale"), -3L)
})

test_that("signif() rescales the whole vector to the finest precision needed", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))

  # 1234.5 -> 3 sig figs needs no decimal places (1.23E+3); 0.012345 -> 3 sig
  # figs needs 4 decimal places (0.0123). The vector scale must cover both.
  x <- signif(decimal(c("1234.5", "0.012345")), digits = 3)
  expect_identical(as.character(x), c("1230.0000", "0.0123"))
  expect_identical(attr(x, "scale"), 4L)
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
  expect_identical(
    as.character(x),
    c("1.2300", "0.0010", "-0.0000", "Infinity", "NaN", NA_character_)
  )

  expect_identical(
    number_class(x),
    c("+Normal", "+Subnormal", "-Zero", "+Infinity", "NaN", NA_character_)
  )
  # Padding a zero out to more decimal places changes its exponent (GDA
  # zero quanta are distinct representations of the same value), so
  # adjusted() for the padded "-0.0000" differs from the unpadded "-0".
  expect_identical(
    adjusted(x),
    c(0L, -3L, -4L, NA_integer_, NA_integer_, NA_integer_)
  )
  expect_identical(is_normal(x), c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(is_subnormal(x), c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE))
})

test_that("elementwise math and decimal helpers preserve names", {
  x <- setNames(decimal(c("1.20", "2.30")), c("a", "b"))

  expect_identical(names(abs(x)), names(x))
  expect_identical(names(round(x, 1)), names(x))
  expect_identical(names(quantize(x, decimal("0.1"))), names(x))
  expect_identical(names(normalize(x)), names(x))
  expect_identical(names(number_class(x)), names(x))
  expect_identical(names(adjusted(x)), names(x))
  expect_identical(names(is_zero(x)), names(x))
  expect_identical(names(is.finite(x)), names(x))
  expect_identical(names(same_quantum(x, decimal("1.00"))), names(x))
  expect_identical(names(fma(x, decimal("2"), decimal("1"))), names(x))
})

test_that("same_quantum compares the vectors' shared scales", {
  # Under fixed-scale storage, quantum is a per-vector property: comparing
  # two vectors' quanta means comparing their declared scales, recycled like
  # any other vectorized predicate.
  expect_identical(
    same_quantum(
      decimal(c("1.20", "1.2", NA_character_)),
      decimal(c("2.30", "2.30", "1"))
    ),
    c(TRUE, TRUE, TRUE)
  )
  expect_identical(same_quantum(decimal("1.00"), decimal("2.0")), FALSE)
  expect_identical(same_quantum(decimal("1.00"), decimal("2.00")), TRUE)
})

test_that("decimal-specific operations use context-aware kernels", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(precision = 10L, traps = character()))

  expect_identical(
    quantize(decimal("1.2345"), decimal("0.01")),
    decimal("1.23")
  )
  expect_identical(
    normalize(decimal(c("1.2300", "1.2"))),
    decimal(c("1.23", "1.20"))
  )
  expect_identical(fma(decimal("2"), decimal("3"), decimal("4")), decimal("10"))
})

test_that("normalize() strips shared trailing zeros without discarding significance", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))

  # "-0.00" alone would reduce to "-0"; sharing a vector with "1.2300" forces
  # the coarser element to keep the finer scale that "1.2300" still needs
  # after its own reduction (2 fractional digits).
  x <- normalize(decimal(c("1.2300", "-0.00")))
  expect_identical(as.character(x), c("1.23", "-0.00"))
  expect_identical(attr(x, "scale"), 2L)
})

test_that("summaries handle empty inputs, na.rm, and NaN propagation", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))

  x <- decimal(c("1.20", "2.30", NA_character_, "NaN"))

  expect_identical(sum(decimal(c("1.20", "2.30"))), decimal("3.50"))
  expect_identical(prod(decimal(c("1.20", "2"))), decimal("2.4000"))
  expect_identical(sum(x, na.rm = TRUE), decimal("3.50"))
  expect_identical(prod(x, na.rm = TRUE), decimal("2.7600"))
  expect_identical(mean(decimal(c("1", "2", "3"))), decimal("2"))
  expect_identical(mean(x, na.rm = TRUE), decimal("1.75"))

  expect_identical(sum(decimal(c(NA_character_, "1"))), NA_decimal_)
  expect_identical(sum(decimal(c("NaN", "1"))), decimal("NaN"))
  expect_true(
    "invalid_operation" %in%
      {
        clear_decimal_flags()
        sum(decimal(c("sNaN", "1")))
        decimal_flags()
      }
  )

  expect_identical(sum(decimal(), na.rm = TRUE), decimal("0"))
  expect_identical(prod(decimal(), na.rm = TRUE), decimal("1"))
  expect_identical(mean(decimal(), na.rm = TRUE), decimal("NaN"))
})

test_that("ordering summaries return decimal infinities on empty input", {
  expect_warning(
    expect_identical(min(decimal(), na.rm = TRUE), decimal("Infinity")),
    "no non-missing arguments to min"
  )
  expect_warning(
    expect_identical(max(decimal(), na.rm = TRUE), decimal("-Infinity")),
    "no non-missing arguments to max"
  )
  expect_warning(
    expect_identical(
      range(decimal(), na.rm = TRUE),
      decimal(c("Infinity", "-Infinity"))
    ),
    "no non-missing arguments to min"
  )

  x <- decimal(c("2", "-1", "NaN", NA_character_))
  expect_identical(min(x, na.rm = TRUE), decimal("-1"))
  expect_identical(max(x, na.rm = TRUE), decimal("2"))
  expect_identical(range(x, na.rm = TRUE), decimal(c("-1", "2")))
  expect_identical(min(decimal(c("NaN", "1"))), decimal("NaN"))
  expect_identical(
    range(decimal(c(NA_character_, "1"))),
    c(NA_decimal_, NA_decimal_)
  )
})
