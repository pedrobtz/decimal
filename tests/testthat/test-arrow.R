arrow_decimal <- function(values, precision, scale) {
  arrow::Array$create(values)$cast(arrow::decimal128(precision, scale))
}

# arrow can be built without Parquet or datasets, as it may be on a check
# machine; installed is not enough.
skip_if_no_parquet <- function() {
  skip_if_not_installed("arrow")
  skip_if_not(arrow::arrow_with_parquet(), "arrow was built without Parquet")
}

skip_if_no_dataset <- function() {
  skip_if_no_parquet()
  skip_if_not(arrow::arrow_with_dataset(), "arrow was built without datasets")
}

# Arrow to decimal ----------------------------------------------------------

test_that("as_decimal() reads an Arrow decimal128 array exactly", {
  skip_if_not_installed("arrow")

  x <- arrow_decimal(c("100.05", "99999999999999999999.99", "0.01"), 25L, 2L)
  out <- as_decimal(x)

  expect_s3_class(out, "decimal")
  expect_identical(attr(out, "scale"), 2L)
  expect_identical(
    as.character(out),
    c("100.05", "99999999999999999999.99", "0.01")
  )
  # The point of the exact path: at this magnitude a double's neighbours are
  # thousands apart, so the cents cannot survive `as.vector()`. Which double
  # the conversion lands on varies by platform; that it cannot hold the cents
  # does not.
  lossy <- as.vector(x)[2L]
  expect_identical(lossy + 0.99, lossy)
})

test_that("as_decimal() reads an Arrow decimal256 array exactly", {
  skip_if_not_installed("arrow")

  values <- c("12345678901234567890.12345678", "0.10000000000000000001")
  x <- arrow::Array$create(values)$cast(arrow::decimal256(50, 20))
  out <- as_decimal(x)

  expect_identical(attr(out, "scale"), 20L)
  expect_identical(
    as.character(out),
    c(
      "12345678901234567890.12345678000000000000",
      "0.10000000000000000001"
    )
  )
})

test_that("as_decimal() reads the narrow decimal32 and decimal64 types", {
  skip_if_not_installed("arrow")

  d32 <- arrow::Array$create(c("1234.5", "-0.1"))$cast(arrow::decimal32(9, 2))
  d64 <- arrow::Array$create("1234567890123456.78")$cast(
    arrow::decimal64(18, 2)
  )

  expect_identical(as_decimal(d32), decimal(c("1234.50", "-0.10")))
  expect_identical(as_decimal(d64), decimal("1234567890123456.78"))
})

test_that("Arrow nulls become missing decimals", {
  skip_if_not_installed("arrow")

  out <- as_decimal(arrow_decimal(c("1.50", NA, "2.25"), 9L, 2L))

  expect_identical(is.na(out), c(FALSE, TRUE, FALSE))
  expect_identical(as.character(out), c("1.50", NA, "2.25"))
})

test_that("as_decimal() takes the scale from the Arrow type", {
  skip_if_not_installed("arrow")

  # Whole numbers only: the scale must come from the type, not from the text.
  x <- arrow_decimal(c("1", "2"), 9L, 3L)

  expect_identical(attr(as_decimal(x), "scale"), 3L)
  expect_identical(as.character(as_decimal(x)), c("1.000", "2.000"))
})

test_that("as_decimal() handles a negative Arrow scale", {
  skip_if_not_installed("arrow")

  out <- as_decimal(arrow_decimal(c("1200", "3400"), 10L, -2L))

  expect_identical(attr(out, "scale"), -2L)
  expect_identical(as.character(out), c("1.2e+3", "3.4e+3"))
})

test_that("as_decimal() folds Arrow's uppercase exponent letter", {
  skip_if_not_installed("arrow")

  out <- as_decimal(arrow_decimal(c("1E-10", "-2.5E+7"), 30L, 10L))

  expect_identical(vctrs::vec_data(out), c("1e-10", "-25000000.0000000000"))
  expect_identical(out, decimal(c("0.0000000001", "-25000000"), scale = 10L))
})

test_that("as_decimal()'s `scale` argument overrides the Arrow type", {
  skip_if_not_installed("arrow")

  x <- arrow_decimal(c("1.25", "2.50"), 9L, 2L)

  expect_identical(attr(as_decimal(x, scale = 4L), "scale"), 4L)
  expect_identical(
    as.character(as_decimal(x, scale = 4L)),
    c("1.2500", "2.5000")
  )
})

test_that("as_decimal() reads a chunked Arrow column", {
  skip_if_not_installed("arrow")

  x <- arrow::ChunkedArray$create(
    arrow_decimal(c("1.25", "2.50"), 9L, 2L),
    arrow_decimal("3.75", 9L, 2L)
  )
  out <- as_decimal(x)

  expect_identical(x$num_chunks, 2L)
  expect_identical(out, decimal(c("1.25", "2.50", "3.75")))
})

test_that("as_decimal() converts Arrow integer arrays exactly at every width", {
  skip_if_not_installed("arrow")

  expect_identical(
    as_decimal(arrow::Array$create(1:3)),
    decimal(c("1", "2", "3"))
  )

  # 2^53 + 1: a double cannot hold it, and as.vector() returns integer64.
  big <- arrow::Array$create(c("9007199254740993", NA))$cast(arrow::int64())
  expect_identical(as_decimal(big), decimal(c("9007199254740993", NA)))

  umax <- arrow::Array$create("18446744073709551615")$cast(arrow::uint64())
  expect_identical(as_decimal(umax), decimal("18446744073709551615"))

  cents <- arrow::Array$create(c(12345L, -5L))$cast(arrow::int64())
  expect_identical(
    as_decimal(cents, scale = 2L),
    decimal(c("12345.00", "-5.00"))
  )
})

test_that("as_decimal() falls back to the R conversion for other arrays", {
  skip_if_not_installed("arrow")

  expect_identical(
    as_decimal(arrow::Array$create(c("1.2", "3.45"))),
    decimal(c("1.2", "3.45"))
  )
  expect_error(
    as_decimal(arrow::Array$create(0.1)),
    "`scale` must be provided"
  )
  expect_identical(
    as_decimal(arrow::Array$create(0.5), scale = 1L),
    decimal("0.5")
  )
})

test_that("Arrow's decimal-to-string cast matches the canonical form", {
  skip_if_not_installed("arrow")

  # The trusted fast path assumes Arrow's cast writes exactly what
  # `mpd_to_sci()` writes, apart from the exponent letter. This property test
  # guards that invariant against drift in either library.
  withr::local_seed(20260922)

  # Build a decimal string with `scale` fractional digits from an unscaled
  # integer, so the cast into the Arrow type is exact for every scale.
  at_scale <- function(digits, scale) {
    if (scale <= 0L) {
      return(paste0(digits, strrep("0", -scale)))
    }
    if (nchar(digits) <= scale) {
      digits <- paste0(strrep("0", scale - nchar(digits) + 1L), digits)
    }
    paste0(
      substr(digits, 1L, nchar(digits) - scale),
      ".",
      substr(digits, nchar(digits) - scale + 1L, nchar(digits))
    )
  }

  widths <- list(
    list(type = arrow::decimal32, precision = 9L),
    list(type = arrow::decimal64, precision = 18L),
    list(type = arrow::decimal128, precision = 38L),
    list(type = arrow::decimal256, precision = 76L)
  )

  for (scale in c(-5L, 0L, 2L, 7L, 20L, 38L)) {
    for (width in widths) {
      precision <- width$precision
      if (scale > precision) {
        next
      }
      # Digits left for the coefficient once negative-scale zeros are added.
      max_digits <- min(precision - max(0L, -scale), 30L)
      counts <- sample(seq_len(max_digits), 40L, replace = TRUE)
      digits <- vapply(
        counts,
        function(n) paste(sample(0:9, n, replace = TRUE), collapse = ""),
        character(1)
      )
      signs <- sample(c("-", ""), length(digits), replace = TRUE)
      values <- c(
        paste0(signs, vapply(digits, at_scale, character(1), scale = scale)),
        at_scale("0", scale),
        paste0("-", at_scale("0", scale)),
        at_scale("1", scale),
        NA
      )

      x <- arrow::Array$create(values)$cast(width$type(precision, scale))
      trusted <- vctrs::vec_data(as_decimal(x))
      # `decimal()` re-parses and re-canonicalizes the same strings.
      validated <- vctrs::vec_data(
        decimal(as.vector(x$cast(arrow::string())), scale = scale)
      )

      expect_identical(trusted, validated)
    }
  }
})

# Decimal to Arrow ----------------------------------------------------------

test_that("infer_type() reports the extension type over a plain decimal", {
  skip_if_not_installed("arrow")

  type <- arrow::infer_type(decimal(c("1.25", "-12345.50")))

  expect_s3_class(type, "DecimalExtensionType")
  expect_identical(type$extension_name(), "r.decimal")
  expect_identical(type$storage_type()$ToString(), "decimal128(7, 2)")
  expect_identical(type$ToString(), "decimal<decimal128(7, 2)>")
})

test_that("infer_type() widens to decimal256 and errors past its limit", {
  skip_if_not_installed("arrow")

  wide <- decimal(paste0(strrep("9", 60), ".5"))
  expect_identical(
    arrow::infer_type(wide)$storage_type()$ToString(),
    "decimal256(61, 1)"
  )

  expect_error(
    arrow::infer_type(decimal(strrep("9", 90))),
    "76 digits"
  )
})

test_that("infer_type() falls back to a single digit for all-missing vectors", {
  skip_if_not_installed("arrow")

  expect_identical(
    arrow::infer_type(decimal(NA_character_))$storage_type()$ToString(),
    "decimal128(1, 0)"
  )
  expect_identical(
    arrow::infer_type(decimal(character()))$storage_type()$ToString(),
    "decimal128(1, 0)"
  )
})

test_that("the decimal.arrow_extension option switches to plain fields", {
  skip_if_not_installed("arrow")
  withr::local_options(decimal.arrow_extension = FALSE)

  x <- decimal(c("1.25", "2.50"))
  expect_identical(arrow::infer_type(x)$ToString(), "decimal128(3, 2)")

  tab <- arrow::arrow_table(amount = x)
  expect_identical(
    tab$schema$GetFieldByName("amount")$type$ToString(),
    "decimal128(3, 2)"
  )
  expect_identical(as_decimal(tab$amount), x)
})

test_that("Arrow conversion rejects infinities and NaNs for any decimal target", {
  skip_if_not_installed("arrow")

  expect_error(
    arrow::as_arrow_array(decimal(c("1.50", "NaN"))),
    "cannot represent infinities or NaNs"
  )
  expect_error(
    arrow::as_arrow_array(decimal(c("1.50", "Infinity"))),
    "element 2"
  )
  expect_error(
    arrow::as_arrow_array(
      decimal(c("1.50", "NaN")),
      type = arrow::decimal128(10, 1)
    ),
    "cannot represent infinities or NaNs"
  )
  # A string target can hold them.
  expect_identical(
    as.vector(arrow::as_arrow_array(
      decimal(c("1.50", "NaN")),
      type = arrow::string()
    )),
    c("1.50", "NaN")
  )
})

test_that("as_arrow_array() wraps a real decimal, and a pinned type is honoured", {
  skip_if_not_installed("arrow")

  x <- decimal(c("1.25", NA, "-12345.50"))
  out <- arrow::as_arrow_array(x)

  expect_s3_class(out, "ExtensionArray")
  expect_identical(out$type$ToString(), "decimal<decimal128(7, 2)>")
  expect_identical(out$storage()$type$ToString(), "decimal128(7, 2)")
  expect_identical(as_decimal(out), x)
  expect_identical(as.vector(out), x)

  plain <- arrow::as_arrow_array(x, type = arrow::decimal128(20, 2))
  expect_identical(plain$type$ToString(), "decimal128(20, 2)")
  expect_identical(as_decimal(plain), x)

  wide <- arrow::as_arrow_array(x, type = arrow_decimal_type(20, 2))
  expect_identical(wide$type$ToString(), "decimal<decimal128(20, 2)>")
  expect_identical(as.vector(wide), x)
})

test_that("arrow_decimal_type() builds the extension type at either width", {
  skip_if_not_installed("arrow")

  expect_identical(
    arrow_decimal_type(20, 2)$storage_type()$ToString(),
    "decimal128(20, 2)"
  )
  expect_identical(
    arrow_decimal_type(50, 10)$storage_type()$ToString(),
    "decimal256(50, 10)"
  )
})

test_that("a decimal column round-trips through tables, Parquet, and datasets", {
  skip_if_no_parquet()

  x <- decimal(c("100.05", "99999999999999999999.99", NA))
  df <- data.frame(id = 1:3)
  df$amount <- x

  tab <- arrow::arrow_table(df)
  expect_identical(
    tab$schema$GetFieldByName("amount")$type$ToString(),
    "decimal<decimal128(22, 2)>"
  )
  # arrow's own conversion, the path every reader takes by default.
  expect_identical(as.data.frame(tab)$amount, x)

  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(tab, path)
  expect_identical(arrow::read_parquet(path)$amount, x)

  back <- arrow::read_parquet(path, as_data_frame = FALSE)
  expect_identical(
    back$schema$GetFieldByName("amount")$type$storage_type()$ToString(),
    "decimal128(22, 2)"
  )
  expect_identical(as_decimal(back$amount), x)
})

test_that("a decimal column round-trips through a dataset", {
  skip_if_no_dataset()
  # arrow::write_dataset() builds its plan with dplyr.
  skip_if_not_installed("dplyr")

  x <- decimal(c("100.05", "99999999999999999999.99", NA))
  df <- data.frame(id = 1:3)
  df$amount <- x

  dir <- withr::local_tempdir()
  arrow::write_dataset(df, dir)
  scanned <- arrow::Scanner$create(arrow::open_dataset(dir))$ToTable()
  expect_identical(as.data.frame(scanned)$amount, x)
})

test_that("a reader without the extension registered sees the plain decimal", {
  skip_if_no_parquet()

  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(arrow::arrow_table(amount = decimal("100.05")), path)

  arrow::unregister_extension_type("r.decimal")
  withr::defer(decimal:::decimal_register_arrow_extension())

  back <- arrow::read_parquet(path, as_data_frame = FALSE)
  expect_identical(
    back$schema$GetFieldByName("amount")$type$ToString(),
    "decimal128(5, 2)"
  )
  expect_type(arrow::read_parquet(path)$amount, "double")
})

# Tables --------------------------------------------------------------------

test_that("arrow_as_data_frame() reads plain fields exactly, the rest via arrow", {
  skip_if_not_installed("arrow")

  tab <- arrow::arrow_table(
    id = 1:2,
    label = factor(c("a", "b")),
    when = as.POSIXct(
      c("2020-01-01 12:00:00", "2020-06-01 12:00:00"),
      tz = "America/New_York"
    ),
    amount = arrow_decimal(c("100.05", "0.01"), 25L, 2L)
  )
  out <- arrow_as_data_frame(tab)

  expect_s3_class(out, "data.frame")
  expect_identical(names(out), c("id", "label", "when", "amount"))
  expect_identical(out$id, 1:2)
  expect_identical(out$label, factor(c("a", "b")))
  expect_identical(attr(out$when, "tzone"), "America/New_York")
  expect_identical(out$amount, decimal(c("100.05", "0.01")))
  # What arrow's own conversion does with the same column.
  expect_type(as.data.frame(tab)$amount, "double")
  expect_equal(as.data.frame(tab)$amount, c(100.05, 0.01))
})

test_that("arrow_as_data_frame() passes extension columns through and rebuilds plain ones", {
  skip_if_not_installed("arrow")

  x <- decimal(c("100.05", "0.01"))
  expect_identical(
    arrow_as_data_frame(arrow::arrow_table(amount = x))$amount,
    x
  )

  withr::local_options(decimal.arrow_extension = FALSE)
  plain <- arrow::arrow_table(amount = x)
  expect_identical(
    plain$schema$GetFieldByName("amount")$type$ToString(),
    "decimal128(5, 2)"
  )
  expect_identical(arrow_as_data_frame(plain)$amount, x)

  # arrow reapplies the column's recorded attributes to the double it made.
  broken <- as.data.frame(plain)$amount
  expect_type(broken, "double")
  expect_error(format(broken), "holds doubles")
})

test_that("arrow_as_data_frame() works on a RecordBatch and rejects other input", {
  skip_if_not_installed("arrow")

  batch <- arrow::record_batch(amount = decimal(c("1.25", "2.50")))
  expect_identical(
    arrow_as_data_frame(batch)$amount,
    decimal(c("1.25", "2.50"))
  )

  expect_error(
    arrow_as_data_frame(arrow::Array$create(1:2)),
    "must be an Arrow `Table` or `RecordBatch`"
  )
})
