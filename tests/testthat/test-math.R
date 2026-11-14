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

test_that("predicates return real logicals, not mpdecimal flag bits", {
  # Several mpd_is*() predicates return masked flags -- MPD_NAN is 4, MPD_SNAN
  # is 8, MPD_INF is 2 -- so a predicate that forwards the return value builds
  # an LGLSXP holding values R never produces. Such a vector still prints as
  # TRUE and still compares equal under `==` (4 == TRUE is TRUE), which is why
  # `expect_identical()` above cannot see the difference. Check the underlying
  # integers, and the base functions that a malformed logical actually breaks.
  x <- decimal(c("1", "NaN", "sNaN", "Infinity", "-0", NA_character_))

  expect_identical(as.integer(is.na(x)), c(0L, 1L, 1L, 0L, 0L, 1L))
  expect_identical(as.integer(is.nan(x)), c(0L, 1L, 1L, 0L, 0L, 0L))
  expect_identical(as.integer(is.infinite(x)), c(0L, 0L, 0L, 1L, 0L, 0L))
  expect_identical(as.integer(is_qnan(x)), c(0L, 1L, 0L, 0L, 0L, 0L))
  expect_identical(as.integer(is_snan(x)), c(0L, 0L, 1L, 0L, 0L, 0L))

  expect_identical(which(is.na(x)), c(2L, 3L, 6L))
  expect_identical(sum(is.na(x)), 3L)
  expect_true(identical(is.nan(x), c(FALSE, TRUE, TRUE, FALSE, FALSE, FALSE)))
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

test_that("summary() reports the same statistics as base R", {
  expect_identical(
    unname(as.character(summary(decimal(c("1", "2", "3", "4"))))),
    c("1.00", "1.75", "2.50", "2.50", "3.25", "4.00")
  )
  expect_identical(
    names(summary(decimal(c("1", "2", "3", "4")))),
    c("Min.", "1st Qu.", "Median", "Mean", "3rd Qu.", "Max.")
  )

  # A median that lands on an element is exact, not interpolated.
  expect_identical(
    as.character(summary(decimal(c("1", "2", "3")))[["Median"]]),
    "2.0"
  )
})

test_that("summary() counts missing values instead of propagating them", {
  out <- summary(decimal(c("1.5", NA, "2.5")))

  expect_identical(names(out)[7], "NA's")
  expect_identical(as.character(out[["NA's"]]), "1.000")
  expect_identical(as.character(out[["Min."]]), "1.500")

  # NaN is missing here for the same reason it is in base R: is.na() is true.
  expect_identical(
    as.character(summary(decimal(c("1", "NaN", "3")))[["NA's"]]),
    "1.00"
  )
})

test_that("summary() handles empty and all-missing input", {
  empty <- summary(decimal(character(0)))
  expect_identical(as.character(empty[["Min."]]), NA_character_)
  expect_identical(as.character(empty[["Mean"]]), "NaN")

  all_na <- summary(decimal(c(NA_character_, NA_character_)))
  expect_identical(as.character(all_na[["NA's"]]), "2")
})

test_that("summary() keeps precision a double would lose", {
  x <- decimal(c("0.10000000000000000001", "0.10000000000000000003"))
  out <- summary(x)

  # Interpolating the quartiles needs two more digits than the input carries,
  # and the shared scale widens every entry to match, so compare values rather
  # than their padded text.
  expect_true(out[["Median"]] == decimal("0.10000000000000000002"))
  expect_true(out[["1st Qu."]] == decimal("0.100000000000000000015"))
  expect_identical(attr(out, "scale"), 22L)

  # The same figures through double would collapse to a single value, which is
  # the loss this package warns about.
  expect_warning(doubles <- as.double(x), "Lossy conversion")
  expect_identical(length(unique(doubles)), 1L)
})

test_that("summary() tolerates the arguments summary.data.frame passes", {
  x <- decimal(c("1", "2", "3", "4"))

  expect_identical(summary(x, digits = 2), summary(x))
  expect_identical(summary(x, maxsum = 7L), summary(x))
  expect_error(summary(x, bogus = TRUE), "`...` must be empty")
})

test_that("min(), max() and range() compare values when a decimal comes first", {
  expect_identical(min(decimal("9"), 10L), decimal("9"))
  expect_identical(max(decimal("10"), 2L), decimal("10"))
  expect_identical(max(decimal(c("10", "100")), 9L), decimal("100"))
  expect_identical(range(decimal("10"), 2L), decimal(c("2", "10")))
  expect_identical(
    max(decimal("9.5"), decimal(c("10", "100"))),
    decimal("100.0")
  )
})

test_that("is.unsorted() orders decimal values, not their text", {
  expect_false(is.unsorted(decimal(c("9", "10"))))
  expect_true(is.unsorted(decimal(c("10", "9"))))
  expect_false(is.unsorted(decimal(c("-Infinity", "-2.5", "0", "Infinity"))))
  expect_false(is.unsorted(decimal("1")))
  expect_false(is.unsorted(decimal()))

  ties <- decimal(c("1", "1.0", "2"))
  expect_false(is.unsorted(ties))
  expect_true(is.unsorted(ties, strictly = TRUE))
  expect_false(is.unsorted(decimal(c("9", "10")), strictly = TRUE))

  expect_identical(is.unsorted(decimal(c("9", NA, "10"))), NA)
  expect_identical(is.unsorted(decimal(c("9", "NaN", "10"))), NA)
  expect_false(is.unsorted(decimal(c("9", NA, "10")), na.rm = TRUE))
  expect_true(is.unsorted(decimal(c("10", "NaN", "9")), na.rm = TRUE))
})

test_that("pmax() and pmin() return consistent decimals", {
  x <- decimal(c("10.0", "9.0", NA))
  y <- decimal(c("9.5", "9.5", "9.5"))

  expect_identical(pmax(x, y), decimal(c("10.0", "9.5", NA)))
  expect_identical(pmin(x, y), decimal(c("9.5", "9.0", NA)))
  expect_identical(pmax(x, y, na.rm = TRUE), decimal(c("10.0", "9.5", "9.5")))
  expect_identical(pmin(x, y, na.rm = TRUE), decimal(c("9.5", "9.0", "9.5")))
  expect_identical(
    pmax(decimal(c("1.0", "5.0", "3.0")), decimal("2.0")),
    decimal(c("2.0", "5.0", "3.0"))
  )

  # A coarser later argument widens to the first argument's scale.
  expect_identical(
    pmax(decimal(c("9.5", "1.25")), decimal(c("10", "1"))),
    decimal(c("10.00", "1.25"))
  )
  expect_identical(
    pmin(decimal(c("9.5", NA)), decimal(c(NA, "10")), na.rm = TRUE),
    decimal(c("9.5", "10.0"))
  )
})

test_that("pmax() and pmin() refuse a later argument with a finer scale", {
  x <- decimal(c("10", "9"))
  y <- decimal(c("9.5", "9.5"))

  # Base pmax() resets the result's attributes to the first argument's, which
  # would label values held at scale 1 as scale 0.
  expect_snapshot(error = TRUE, pmax(x, y))
  expect_error(pmin(x, y), class = "decimal_parallel_extrema_scale")
  expect_error(
    pmax(x, decimal("1.5"), 2L),
    class = "decimal_parallel_extrema_scale"
  )
  expect_identical(pmax(y, x), decimal(c("10.0", "9.5")))
})

test_that("rounding functions pass infinities and quiet NaNs through", {
  x <- decimal(c("1.5", "Infinity", "-Infinity", "NaN", "NaN123", NA))
  specials <- c("Infinity", "-Infinity", "NaN", "NaN123", NA)

  expect_identical(floor(x), decimal(c("1", specials)))
  expect_identical(ceiling(x), decimal(c("2", specials)))
  expect_identical(trunc(x), decimal(c("1", specials)))
  expect_identical(round(x), decimal(c("2", specials)))
  expect_identical(round(x, digits = 1), decimal(c("1.5", specials)))
  expect_identical(signif(x, digits = 1), decimal(c("2", specials)))

  # Passing a special through raises no signal.
  clear_decimal_flags()
  only <- decimal(specials)
  for (f in list(floor, ceiling, trunc, round, signif)) {
    expect_identical(f(only), only)
  }
  expect_identical(decimal_flags(), character())

  # Specials do not change the scale signif() chooses.
  expect_identical(
    signif(decimal(c("Infinity", "0.012345")), digits = 2),
    decimal(c("Infinity", "0.012"))
  )
  expect_identical(signif(decimal("NaN")), decimal("NaN"))
})

test_that("rounding functions signal invalid_operation for a signaling NaN", {
  x <- decimal(c("1.5", "sNaN"))

  for (f in list(floor, ceiling, trunc, round, signif)) {
    expect_error(f(x), class = "decimal_invalid_operation")
  }

  with_decimal_context(decimal_context(traps = character()), {
    clear_decimal_flags()
    out <- floor(x)
    expect_true("invalid_operation" %in% decimal_flags())
    expect_identical(is_qnan(out), c(FALSE, TRUE))

    clear_decimal_flags()
    out <- round(x)
    expect_true("invalid_operation" %in% decimal_flags())
    expect_identical(is_qnan(out), c(FALSE, TRUE))

    clear_decimal_flags()
    out <- signif(x, digits = 1)
    expect_true("invalid_operation" %in% decimal_flags())
    expect_identical(is_qnan(out), c(FALSE, TRUE))
  })
})

test_that("a quantize trap on a special value does not blame the precision", {
  expect_snapshot(error = TRUE, round(decimal("sNaN")))
  expect_snapshot(error = TRUE, quantize(decimal("Infinity"), decimal("1")))
})

test_that("mean() trims like base R", {
  values <- c("-5", "1", "2", "3", "4", "7", "8.5", "100")
  x <- decimal(values)
  for (trim in c(0, 0.1, 0.125, 0.2, 0.25, 0.375, 0.49, 0.5, 0.7, -1)) {
    # Every expected mean here is exact in binary, so it converts losslessly.
    expected <- decimal(as.character(mean(as.double(values), trim = trim)))
    expect_true(mean(x, trim = trim) == expected)
  }

  four <- decimal(c("1", "2", "3", "100"))
  expect_identical(mean(four, trim = 0.25), decimal("2.5"))
  # A trim of 0.5 or more gives the median.
  expect_identical(mean(four, trim = 0.5), decimal("2.5"))
  expect_identical(mean(decimal(c("1", "2", "100")), trim = 0.5), decimal("2"))
  # Exact where a double is not.
  expect_identical(
    mean(decimal(c("0.1", "0.2", "0.3", "1E+20")), trim = 0.25),
    decimal("0.25")
  )

  y <- decimal(c("1", NA, "2", "3", "100"))
  expect_identical(mean(y, trim = 0.25), NA_decimal_)
  expect_identical(mean(y, trim = 0.25, na.rm = TRUE), decimal("2.5"))
  expect_identical(mean(decimal(), trim = 0.25), decimal("NaN"))

  expect_error(mean(x, trim = c(0.1, 0.2)), "`trim` must be a number")
  expect_error(mean(x, trim = "a"), "`trim` must be a number")
})
