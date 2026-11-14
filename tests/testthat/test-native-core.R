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

test_that("string scale combines fractional digits before the range check", {
  # Scale is fractional digits minus exponent: a fractional digit brings an
  # exponent just past integer range back inside it.
  expect_identical(
    decimal:::.decimal_string_scale(
      c(
        "1.5E+2147483648",
        "1.5E+2147483649",
        "1.5E-2147483646",
        "1.5E-2147483647",
        "12.34E+2147483649",
        "12.34E+2147483650",
        "1E+99999999999999999999999999",
        "1.5E-99999999999999999999999999"
      )
    ),
    c(
      -2147483647L,
      NA_integer_,
      2147483647L,
      NA_integer_,
      -2147483647L,
      NA_integer_,
      NA_integer_,
      NA_integer_
    )
  )
})

test_that("adjusted exponents at the integer limits are exact or an error", {
  adjusted_strings <- decimal:::.decimal_adjusted_strings
  msg <- "Adjusted exponent out of integer range at element 1"

  expect_identical(adjusted_strings("5E-2147483647"), -2147483647L)
  expect_identical(adjusted_strings("5E+2147483647"), 2147483647L)
  expect_identical(adjusted_strings("15E+2147483646"), 2147483647L)
  # -2147483648 is NA_integer_ in R, so it is out of range too.
  expect_error(adjusted_strings("5E-2147483648"), msg)
  expect_error(adjusted_strings("5E-2147483649"), msg)
  expect_error(adjusted_strings("15E+2147483647"), msg)
  expect_identical(adjusted(decimal("1.5E+2147483647")), 2147483647L)
  expect_error(adjusted(decimal("1.5E+2147483648")), msg)
})

test_that("string scale rejects a non-character input", {
  expect_error(decimal:::.decimal_string_scale(1:3), "must be a character vector")
})

test_that("every kernel rejects an invalid decimal string and reports its index", {
  # The public API canonicalizes before any other kernel sees a string, so these
  # parse-failure paths are only reachable through the internal wrappers. Each
  # frees the handles it holds before raising; driving every operand position
  # here is what lets the valgrind job check that.
  bad <- c("1", "not-a-decimal")
  ok <- c("1", "2")
  msg <- "Invalid decimal string at element 2"

  expect_error(decimal:::.decimal_canonicalize_strings(bad), msg)
  expect_error(decimal:::.decimal_classify_strings(bad), msg)
  expect_error(decimal:::.decimal_format_strings(bad), msg)
  expect_error(decimal:::.decimal_to_double_strings(bad), msg)
  expect_error(decimal:::.decimal_to_integer_strings(bad), msg)
  expect_error(decimal:::.decimal_equal_proxy_strings(bad), msg)
  expect_error(decimal:::.decimal_order_proxy_strings(bad), msg)
  expect_error(decimal:::.decimal_unary_op_strings(bad, "-"), msg)
  expect_error(decimal:::.decimal_math_op_strings(bad, "abs"), msg)
  expect_error(decimal:::.decimal_rescale_exact_strings(bad, 0L), msg)
  expect_error(decimal:::.decimal_adjusted_strings(bad), msg)
  expect_error(decimal:::.decimal_predicate_strings(bad, "nan"), msg)
  expect_error(decimal:::.decimal_apply_context(bad), msg)

  expect_error(decimal:::.decimal_binary_op_strings(bad, ok, "+"), msg)
  expect_error(decimal:::.decimal_binary_op_strings(ok, bad, "+"), msg)
  expect_error(decimal:::.decimal_compare_strings(bad, ok, "=="), msg)
  expect_error(decimal:::.decimal_compare_strings(ok, bad, "=="), msg)
  expect_error(decimal:::.decimal_quantize_strings(bad, ok), msg)
  expect_error(decimal:::.decimal_quantize_strings(ok, bad), msg)
  expect_error(decimal:::.decimal_same_quantum_strings(bad, ok), msg)
  expect_error(decimal:::.decimal_same_quantum_strings(ok, bad), msg)
  expect_error(decimal:::.decimal_divide_strings(bad, ok), msg)
  expect_error(decimal:::.decimal_divide_strings(ok, bad), msg)

  expect_error(decimal:::.decimal_fma_strings(bad, ok, ok), msg)
  expect_error(decimal:::.decimal_fma_strings(ok, bad, ok), msg)
  expect_error(decimal:::.decimal_fma_strings(ok, ok, bad), msg)
})

test_that("equality proxy keys reduce equal values to one key", {
  expect_identical(
    decimal:::.decimal_equal_proxy_strings(c(
      "1.20",
      "1.2",
      "12E-1",
      "0",
      "-0",
      "0.0E5",
      "-1.500",
      "NaN",
      "sNaN",
      "Infinity",
      "-Infinity",
      NA_character_
    )),
    c(
      "1.2",
      "1.2",
      "1.2",
      "0",
      "0",
      "0",
      "-1.5",
      "NaN",
      "NaN",
      "Infinity",
      "-Infinity",
      NA_character_
    )
  )
})

test_that("ordering proxy keys sort in numeric order under byte comparison", {
  ascending <- c(
    "-Infinity",
    "-12345",
    "-1E3",
    "-999",
    "-1.5",
    "-1.05",
    "-1",
    "-0.001",
    "-1E-10",
    "0",
    "1E-10",
    "0.001",
    "1",
    "1.05",
    "1.5",
    "999",
    "1E3",
    "12345",
    "Infinity",
    "NaN"
  )
  shuffled <- rev(ascending)
  keys <- decimal:::.decimal_order_proxy_strings(shuffled)

  expect_identical(shuffled[order(keys, method = "radix")], ascending)
  expect_identical(
    decimal:::.decimal_order_proxy_strings(c("-0", "0.000", NA_character_)),
    c("3/0", "3/0", NA_character_)
  )
})

test_that("malformed context arguments raise an error instead of crashing", {
  # The R wrappers always pass well-formed context fields, so these shapes are
  # only reachable through .Call; each used to read past a zero-length vector.
  ctx <- list(
    precision = 28L,
    rounding = "half_even",
    emax = 999999L,
    emin = -999999L,
    traps = character(),
    flags = character(),
    clamp = FALSE,
    allcr = TRUE
  )
  scalar_bad <- list(
    precision = list(integer(), c(28L, 28L), 28, "28", NA_integer_),
    rounding = list(character(), c("half_even", "half_up"), 1L, NA_character_),
    emax = list(integer(), c(1L, 1L), 999999, NA_integer_),
    emin = list(integer(), c(-1L, -1L), -999999, NA_integer_),
    clamp = list(logical(), c(FALSE, FALSE), 0L, NA),
    allcr = list(logical(), c(TRUE, TRUE), 1L, NA)
  )
  vector_bad <- list(
    traps = list(1L, NA_character_, list("division_by_zero")),
    flags = list(1L, NA_character_, list("inexact"))
  )

  call_with <- function(name, value) {
    args <- ctx
    args[name] <- list(value)
    list(
      function() {
        do.call(.Call, c(list(decimal:::decimal_c_apply_context, "1.5"), args))
      },
      function() {
        do.call(
          .Call,
          c(list(decimal:::decimal_c_binary_op_strings, "1", "2", "+"), args)
        )
      }
    )
  }

  for (name in names(scalar_bad)) {
    for (value in scalar_bad[[name]]) {
      for (f in call_with(name, value)) {
        expect_error(f(), paste0("`", name, "` must be"), fixed = TRUE)
      }
    }
  }
  for (name in names(vector_bad)) {
    for (value in vector_bad[[name]]) {
      for (f in call_with(name, value)) {
        expect_error(f(), paste0("`", name, "` must be"), fixed = TRUE)
      }
    }
  }

  # The well-formed context still works through both kernels.
  ok <- do.call(.Call, c(list(decimal:::decimal_c_apply_context, "1.5"), ctx))
  expect_identical(ok[[1]], "1.5")
})

test_that("conversion to double is correctly rounded", {
  # Oracle values from Python's float(), generated by fixtures/make-to-double.py.
  cases <- utils::read.csv(
    test_path("fixtures", "to-double.csv"),
    colClasses = "character",
    na.strings = character()
  )
  expected <- as.numeric(cases$hex)
  expect_false(anyNA(expected))

  plain <- cases$scale == "NA"
  expect_identical(
    decimal:::.decimal_to_double_strings(cases$input[plain]),
    expected[plain]
  )
  # Signed zeros: identical() treats 0 and -0 as equal.
  expect_identical(
    1 / decimal:::.decimal_to_double_strings(cases$input[plain]) < 0,
    1 / expected[plain] < 0
  )

  for (i in which(!plain)) {
    x <- decimal(cases$input[[i]], scale = as.integer(cases$scale[[i]]))
    out <- suppressWarnings(as.double(x))
    expect_identical(out, expected[[i]], label = cases$input[[i]])
    expect_identical(1 / out < 0, 1 / expected[[i]] < 0)
  }
})

test_that("as.double() handles the reported misrounded values", {
  to_double <- decimal:::.decimal_to_double_strings
  expect_identical(to_double("83E25"), as.numeric("0x1.5747ab143e353p+89"))
  # Expected values as hex floats: R's own parser for decimal literals has the
  # same rounding error the conversion used to have.
  expect_identical(
    to_double("19745E303"),
    as.numeric("0x1.c1e2903c5a5aap+1020")
  )
  expect_identical(
    to_double("44658E-118"),
    as.numeric("0x1.5fec4702d8d3fp-377")
  )
  expect_identical(
    to_double("237281754796605.859375"),
    as.numeric("0x1.af9ced69a47bcp+47")
  )
  expect_identical(
    to_double("1.7976931348623158E+308"),
    .Machine$double.xmax
  )
  expect_identical(
    suppressWarnings(as.double(decimal(c("1", "2.5", "0"), scale = 5000L))),
    c(1, 2.5, 0)
  )
  expect_identical(
    suppressWarnings(as.double(decimal(c("1", "-2.5"), scale = 4932L))),
    c(1, -2.5)
  )
  expect_identical(
    suppressWarnings(as.double(decimal("1e23", scale = 15))),
    as.numeric("0x1.52d02c7e14af6p+76")
  )
})

test_that("conversion to double does not depend on LC_NUMERIC", {
  # strtod() reads the locale's decimal point; the text it is given has none.
  old <- Sys.getlocale("LC_NUMERIC")
  set <- suppressWarnings(Sys.setlocale("LC_NUMERIC", "de_DE.UTF-8"))
  on.exit(suppressWarnings(Sys.setlocale("LC_NUMERIC", old)), add = TRUE)
  skip_if(identical(set, ""), "de_DE.UTF-8 locale is not available")

  expect_identical(
    decimal:::.decimal_to_double_strings(c("1.5", "-0.25", "1.5E+3")),
    c(1.5, -0.25, 1500)
  )
})
