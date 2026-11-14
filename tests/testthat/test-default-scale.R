# `decimal.default_scale` is the scale `decimal()` and `as_decimal()` use when
# the caller gives none. It must not reach the conversions the package makes
# for itself: integer operands, quantums, counts and constants.

# Every input carries an explicit scale, so only the package's own conversions
# can see the option.
default_scale_operations <- function() {
  x <- decimal(c("1.23456", "2.5", "7.125", "10"), scale = 5L)
  empty <- decimal(character(), scale = 0L)
  list(
    round = \() round(x, 3),
    quantize = \() quantize(x, "0.001"),
    summary = \() summary(x),
    summary_na = \() summary(c(x, NA_decimal_)),
    add_integer = \() x + 150L,
    multiply_integer = \() x * 3L,
    integer_minus = \() 150L - x,
    max_integer = \() max(x, 12345L),
    min_integer = \() min(x, -12345L),
    compare_integer = \() x < 5L,
    mean = \() mean(x),
    sum = \() sum(x),
    sum_empty = \() sum(empty),
    prod_empty = \() prod(empty),
    mean_empty = \() mean(empty),
    max_nan = \() max(decimal(c("NaN", "1"), scale = 0L)),
    range_empty = \() suppressWarnings(range(empty)),
    match_integer = \() match(decimal("150", scale = 0L), 150L),
    sqrt_integer = \() sqrt(decimal("4", scale = 0L)) + 0L,
    fma_character = \() fma("1.5", 2L, "0.25"),
    as_decimal_decimal = \() as_decimal(x)
  )
}

run_default_scale_operations <- function() {
  lapply(default_scale_operations(), \(f) {
    tryCatch(f(), error = \(e) structure(conditionMessage(e), class = "error"))
  })
}

is_error_message <- function(x) {
  inherits(x, "error")
}

test_that("internal conversions ignore decimal.default_scale", {
  reference <- local({
    withr::local_options(decimal.default_scale = NULL)
    run_default_scale_operations()
  })

  # The reference itself is right: no operation errors.
  expect_false(any(vapply(reference, is_error_message, logical(1))))
  expect_identical(
    reference$round,
    decimal(c("1.235", "2.500", "7.125", "10.000"))
  )
  expect_identical(reference$quantize, reference$round)
  expect_identical(
    unname(as.character(reference$summary[c(2L, 3L, 5L)])),
    c("2.1836400", "4.8125000", "7.8437500")
  )
  expect_identical(as.character(reference$add_integer[1L]), "151.23456")
  expect_identical(as.character(reference$multiply_integer[1L]), "3.70368")
  expect_identical(as.character(reference$max_integer), "12345.00000")
  expect_identical(reference$match_integer, 1L)
  expect_identical(
    unname(as.character(reference$summary_na[["NA's"]])),
    "1.0000000"
  )

  for (default in list(2L, 0L, -2L)) {
    withr::local_options(decimal.default_scale = default)
    out <- run_default_scale_operations()
    for (name in names(reference)) {
      expect_identical(
        out[[name]],
        reference[[name]],
        label = paste0(name, " under default_scale = ", default)
      )
    }
  }
})

test_that("as_decimal() returns a decimal vector unchanged without a scale", {
  x <- decimal("1.2", scale = 1L)
  withr::local_options(decimal.default_scale = 7L)

  expect_identical(as_decimal(x), x)
  expect_identical(decimal(x), x)
  expect_identical(
    as_decimal(x, scale = 3L),
    decimal("1.200", scale = 3L)
  )
})

test_that("decimal.default_scale still applies to user conversions", {
  withr::local_options(decimal.default_scale = 2L)

  expect_identical(decimal("1.2"), decimal("1.20", scale = 2L))
  expect_identical(as_decimal(3L), decimal("3.00", scale = 2L))
  expect_identical(as_decimal(0.5), decimal("0.50", scale = 2L))
})

test_that("Arrow reads keep the Arrow scale under decimal.default_scale", {
  skip_if_not_installed("arrow")

  values <- arrow::Array$create(c("1.25", "2.75"))$cast(
    arrow::decimal128(10, 2)
  )
  expected <- decimal(c("1.25", "2.75"), scale = 2L)
  withr::local_options(decimal.default_scale = 1L)

  expect_identical(as_decimal(values), expected)
  expect_identical(
    as_decimal(values, scale = 1L),
    decimal(c("1.2", "2.8"), scale = 1L)
  )

  table <- arrow::arrow_table(amount = values)
  expect_identical(arrow_as_data_frame(table)$amount, expected)

  extension <- arrow::arrow_table(data.frame(amount = expected))
  expect_identical(as.data.frame(extension)$amount, expected)

  skip_if_not(arrow::arrow_with_parquet(), "arrow was built without Parquet")
  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(amount = expected), path)
  expect_identical(arrow::read_parquet(path)$amount, expected)
})
