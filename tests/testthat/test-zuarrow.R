arrow_type_of <- function(array) {
  format(zuarrow::arrow_schema(array))
}

# A zuarrow array of the Arrow decimal type `type` from exact text.
zuarrow_decimal <- function(values, type) {
  zuarrow::arrow_array(structure(values, arrow_type = type))
}

test_that("decimal registers with zuarrow for every decimal type", {
  skip_if_not_installed("zuarrow")

  registry <- zuarrow::arrow_registry()
  ours <- registry[registry$package %in% "decimal", ]

  expect_setequal(ours$key, c("d:*", "r.decimal"))
  expect_true(all(ours$exact))
  expect_identical(ours$class[ours$key == "d:*"], "decimal")
})

test_that("registering again replaces the registration quietly", {
  skip_if_not_installed("zuarrow")
  loadNamespace("zuarrow")

  expect_no_message(decimal_register_zuarrow())
  hooks <- getHook(packageEvent("zuarrow", "onLoad"))
  expect_length(Filter(\(f) isTRUE(attr(f, "decimal")), hooks), 1L)
  expect_setequal(
    zuarrow::arrow_registry()$key[
      zuarrow::arrow_registry()$package %in%
        "decimal"
    ],
    c("d:*", "r.decimal")
  )
})

test_that("decimal128 vectors round-trip through zuarrow exactly", {
  skip_if_not_installed("zuarrow")

  max38 <- strrep("9", 38)
  cases <- list(
    decimal(c("1.25", "-3.50", NA, "0.00", "-0.01")),
    decimal(c(max38, paste0("-", max38), NA, "0", "-1")),
    decimal(c("12300", "-500", NA, "0"), scale = -2L),
    decimal(c("0.0000001", "-0.0000123", NA), scale = 7L),
    decimal(character(), scale = 3L),
    decimal(c(NA_character_, NA_character_), scale = 4L)
  )
  for (x in cases) {
    array <- zuarrow::arrow_array(x)
    expect_identical(
      arrow_type_of(array),
      sprintf("decimal128(38, %d)", attr(x, "scale"))
    )
    expect_identical(zuarrow::arrow_to_r(array), x)
  }
})

test_that("decimal256 vectors round-trip through zuarrow exactly", {
  skip_if_not_installed("zuarrow")

  max76 <- strrep("9", 76)
  wide <- decimal(c(max76, paste0("-", max76), NA, "1", "0"))
  array <- zuarrow::arrow_array(wide)
  expect_identical(arrow_type_of(array), "decimal256(76, 0)")
  expect_identical(zuarrow::arrow_to_r(array), wide)

  # A scale past 38 needs the wide type even for small values.
  fine <- decimal(c("1", "-2.5", NA), scale = 40L)
  array <- zuarrow::arrow_array(fine)
  expect_identical(arrow_type_of(array), "decimal256(76, 40)")
  expect_identical(zuarrow::arrow_to_r(array), fine)
})

test_that("a negative zero becomes zero", {
  skip_if_not_installed("zuarrow")

  out <- zuarrow::arrow_to_r(zuarrow::arrow_array(decimal("-0.00")))
  expect_identical(out, decimal("0.00"))
})

test_that("every Arrow decimal width reads with its scale", {
  skip_if_not_installed("zuarrow")

  values <- c("1.20", "-7.00", NA, "0.05")
  for (type in c("d:9,2,32", "d:18,2,64", "d:10,2", "d:50,2,256")) {
    out <- zuarrow::arrow_to_r(zuarrow_decimal(values, type))
    expect_identical(out, decimal(values, scale = 2L))
  }
})

test_that("the extremes of every Arrow decimal width read exactly", {
  skip_if_not_installed("zuarrow")

  for (bits in c(32L, 64L, 128L, 256L)) {
    precision <- c(`32` = 9L, `64` = 18L, `128` = 38L, `256` = 76L)[[
      as.character(bits)
    ]]
    nines <- strrep("9", precision)
    values <- c(nines, paste0("-", nines), "1", "-1", "0")
    type <- sprintf("d:%d,0,%d", precision, bits)
    out <- zuarrow::arrow_to_r(zuarrow_decimal(values, type))
    expect_identical(out, decimal(values))
  }
})

test_that("the codec agrees with zuarrow's own decimal text", {
  skip_if_not_installed("zuarrow")
  withr::local_seed(20261104)
  # `decimal()` rescales under the context precision, and these values are
  # wider than the default.
  local_decimal_context(decimal_context(precision = 100L))

  # Plain text with `scale` fractional digits, the form zuarrow reads.
  random_text <- function(n, precision, scale) {
    digits <- vapply(
      sample(precision, n, replace = TRUE),
      \(k) paste(sample(0:9, k, replace = TRUE), collapse = ""),
      ""
    )
    if (scale > 0L) {
      digits <- vapply(
        digits,
        \(d) {
          d <- paste0(strrep("0", max(scale + 1L - nchar(d), 0L)), d)
          cut <- nchar(d) - scale
          paste0(substr(d, 1L, cut), ".", substring(d, cut + 1L))
        },
        "",
        USE.NAMES = FALSE
      )
    } else {
      digits <- paste0(digits, strrep("0", -scale))
    }
    out <- paste0(sample(c("", "-"), n, replace = TRUE), digits)
    out[sample(n, 2L)] <- NA
    out
  }

  types <- list(
    c(9L, 3L, 32L),
    c(18L, 0L, 64L),
    c(38L, 10L, 128L),
    c(38L, -3L, 128L),
    c(76L, 30L, 256L)
  )
  for (type in types) {
    format <- sprintf("d:%d,%d,%d", type[[1L]], type[[2L]], type[[3L]])
    text <- random_text(100L, type[[1L]], type[[2L]])
    expected <- decimal(text, scale = type[[2L]])

    # Decoding: zuarrow writes the buffers from text, decimal reads them.
    array <- zuarrow_decimal(text, format)
    expect_identical(decimal_arrow_decode(array), expected)

    # Encoding: decimal writes the buffers, zuarrow reads them as text.
    back <- zuarrow::arrow_to_r(
      decimal_arrow_encode(expected),
      to = character()
    )
    expect_identical(decimal(as.vector(back), scale = type[[2L]]), expected)
  }
})

test_that("a data frame round-trips through zuarrow IPC exactly", {
  skip_if_not_installed("zuarrow")

  df <- data.frame(id = 1:5)
  df$amount <- decimal(c("1.25", "-3.50", "12345.67", NA, "0.00"))
  df$big <- decimal(c(strrep("9", 38), "1", NA, "-2", "3"))
  df$coarse <- decimal(c("100", NA, "-2500", "0", "700"), scale = -2L)

  for (format in c("file", "stream")) {
    path <- withr::local_tempfile()
    # Two rows per batch, so the column is combined from three pieces.
    zuarrow::arrow_write(df, path, format = format, batch = 2L)
    expect_identical(zuarrow::arrow_read(path), df)
  }
})

test_that("an r.decimal extension column reads as a decimal vector", {
  skip_if_not_installed("zuarrow")

  array <- zuarrow::arrow_array(structure(
    c("1.20", NA, "-0.05"),
    arrow_type = "d:10,2",
    arrow_extension = "r.decimal"
  ))
  expect_identical(
    zuarrow::arrow_to_r(array),
    decimal(c("1.20", NA, "-0.05"))
  )
})

test_that("values without an Arrow decimal form raise an error", {
  skip_if_not_installed("zuarrow")

  expect_error(
    zuarrow::arrow_array(decimal(strrep("9", 77))),
    class = "decimal_arrow_error"
  )
  expect_error(
    zuarrow::arrow_array(decimal("1", scale = 77L)),
    class = "decimal_arrow_error"
  )
  expect_error(
    zuarrow::arrow_array(decimal(c("1", "Inf"))),
    class = "decimal_arrow_error"
  )
  expect_error(
    zuarrow::arrow_array(decimal(c("1", "NaN"))),
    class = "decimal_arrow_error"
  )
})

test_that("the decoder rejects an array that is not a decimal", {
  skip_if_not_installed("zuarrow")

  expect_error(decimal_arrow_decode(zuarrow::arrow_array(1:3)))
  expect_error(decimal_arrow_decode("not a handle"))
})

test_that("the decoder reads an array at an offset", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("nanoarrow")

  values <- c("1.25", NA, "-3.50", "99999999999999999999.99", "0.01")
  array <- arrow::Array$create(values)$cast(arrow::decimal128(25L, 2L))
  sliced <- nanoarrow::as_nanoarrow_array(array$Slice(1L, 3L))

  expect_identical(decimal_arrow_decode(sliced), decimal(values[2:4]))
})

test_that("the encoder's arrays read back exactly through arrow", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("nanoarrow")

  x <- decimal(c("1.25", NA, "-3.50", "99999999999999999999.99"))
  handle <- decimal_arrow_encode(x)
  expect_s3_class(handle, "nanoarrow_array")

  array <- arrow::as_arrow_array(nanoarrow::as_nanoarrow_array(handle))
  expect_identical(array$type$ToString(), "decimal128(38, 2)")
  expect_identical(as_decimal(array), x)
})
