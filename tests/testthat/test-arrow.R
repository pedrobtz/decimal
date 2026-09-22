arrow_decimal <- function(values, precision, scale) {
  arrow::Array$create(values)$cast(arrow::decimal128(precision, scale))
}

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
  # The point of the exact path: a double loses the twenty-second digit.
  expect_false(identical(as.vector(x)[2L], 99999999999999999999.99))
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

test_that("as_decimal() falls back to the R conversion for non-decimal arrays", {
  skip_if_not_installed("arrow")

  expect_identical(
    as_decimal(arrow::Array$create(c("1.2", "3.45"))),
    decimal(c("1.2", "3.45"))
  )
  expect_identical(
    as_decimal(arrow::Array$create(1:3)),
    decimal(c("1", "2", "3"))
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

  for (scale in c(-5L, 0L, 2L, 7L, 20L, 38L)) {
    for (width in c(38L, 76L)) {
      type <- if (width == 38L) arrow::decimal128 else arrow::decimal256
      counts <- sample(seq_len(min(width, 30L)), 40L, replace = TRUE)
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

      x <- arrow::Array$create(values)$cast(type(width, scale))
      trusted <- vctrs::vec_data(as_decimal(x))
      # `decimal()` re-parses and re-canonicalizes the same strings.
      validated <- vctrs::vec_data(
        decimal(as.vector(x$cast(arrow::string())), scale = scale)
      )

      expect_identical(trusted, validated)
    }
  }
})

test_that("infer_type() reports an Arrow decimal type for decimal vectors", {
  skip_if_not_installed("arrow")

  type <- arrow::infer_type(decimal(c("1.25", "-12345.50")))

  expect_s3_class(type, "Decimal128Type")
  expect_identical(type$ToString(), "decimal128(7, 2)")
})

test_that("infer_type() widens to decimal256 and errors past its limit", {
  skip_if_not_installed("arrow")

  wide <- decimal(paste0(strrep("9", 60), ".5"))
  expect_s3_class(arrow::infer_type(wide), "Decimal256Type")
  expect_identical(arrow::infer_type(wide)$ToString(), "decimal256(61, 1)")

  expect_error(
    arrow::infer_type(decimal(strrep("9", 90))),
    "76 digits"
  )
})

test_that("infer_type() falls back to a single digit for all-missing vectors", {
  skip_if_not_installed("arrow")

  expect_identical(
    arrow::infer_type(decimal(NA_character_))$ToString(),
    "decimal128(1, 0)"
  )
  expect_identical(
    arrow::infer_type(decimal(character()))$ToString(),
    "decimal128(1, 0)"
  )
})

test_that("Arrow conversion rejects infinities and NaNs", {
  skip_if_not_installed("arrow")

  expect_error(
    arrow::as_arrow_array(decimal(c("1.50", "NaN"))),
    "cannot represent infinities or NaNs"
  )
  expect_error(
    arrow::as_arrow_array(decimal(c("1.50", "Infinity"))),
    "element 2"
  )
})

test_that("as_arrow_array() converts exactly and honours a pinned type", {
  skip_if_not_installed("arrow")

  x <- decimal(c("1.25", NA, "-12345.50"))
  out <- arrow::as_arrow_array(x)

  expect_identical(out$type$ToString(), "decimal128(7, 2)")
  expect_identical(as_decimal(out), x)

  pinned <- arrow::as_arrow_array(x, type = arrow::decimal128(20, 2))
  expect_identical(pinned$type$ToString(), "decimal128(20, 2)")
  expect_identical(as_decimal(pinned), x)
})

test_that("a decimal column survives arrow_table() and Parquet", {
  skip_if_not_installed("arrow")

  x <- decimal(c("100.05", "99999999999999999999.99"))
  tab <- arrow::arrow_table(id = 1:2, amount = x)

  expect_identical(
    tab$schema$GetFieldByName("amount")$type$ToString(),
    "decimal128(22, 2)"
  )

  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(tab, path)
  back <- arrow::read_parquet(path, as_data_frame = FALSE)

  expect_identical(
    back$schema$GetFieldByName("amount")$type$ToString(),
    "decimal128(22, 2)"
  )
  expect_identical(as_decimal(back$amount), x)
})

test_that("arrow_as_data_frame() keeps decimal columns exact", {
  skip_if_not_installed("arrow")

  tab <- arrow::arrow_table(
    id = 1:2,
    label = c("a", "b"),
    amount = arrow_decimal(c("100.05", "0.01"), 25L, 2L)
  )
  out <- arrow_as_data_frame(tab)

  expect_s3_class(out, "data.frame")
  expect_identical(names(out), c("id", "label", "amount"))
  expect_identical(out$id, 1:2)
  expect_identical(out$label, c("a", "b"))
  expect_identical(out$amount, decimal(c("100.05", "0.01")))
  # What arrow's own conversion does with the same column.
  expect_identical(as.data.frame(tab)$amount, c(100.05, 0.01))
})

test_that("arrow_as_data_frame() ignores arrow's restored R attributes", {
  skip_if_not_installed("arrow")

  # A table built from an R decimal column carries that column's `scale` and
  # `class` attributes in the schema's R metadata. Arrow reapplies them to the
  # double it produces, so `as.data.frame()` returns a double wearing the
  # decimal class. `arrow_as_data_frame()` rebuilds the column from the Arrow
  # data instead and is unaffected.
  tab <- arrow::arrow_table(amount = decimal(c("100.05", "0.01")))

  restored <- as.data.frame(tab)$amount
  expect_type(restored, "double")

  out <- arrow_as_data_frame(tab)$amount
  expect_type(vctrs::vec_data(out), "character")
  expect_identical(out, decimal(c("100.05", "0.01")))
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
