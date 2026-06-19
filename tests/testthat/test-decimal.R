test_that("decimal constructors build exact vectors", {
  expect_s3_class(decimal(), "decimal")
  expect_identical(length(decimal()), 0L)
  expect_true(is_decimal(decimal("1.2300")))
  expect_identical(as.character(decimal(c("1.2300", "-0", "NaN", NA_character_))),
                   c("1.2300", "-0", "NaN", NA_character_))
  expect_identical(as.character(decimal(c(1L, NA_integer_, -2L))), c("1", NA_character_, "-2"))
  expect_identical(
    as.character(decimal_from_double(c(0.1, -0, Inf, -Inf, NaN, NA_real_))),
    c(
      "0.1000000000000000055511151231257827021181583404541015625",
      "-0",
      "Infinity",
      "-Infinity",
      "NaN",
      NA_character_
    )
  )
  expect_identical(NA_decimal_, decimal(NA_character_))
})

test_that("unsupported construction paths fail cleanly", {
  expect_error(as_decimal(TRUE), "`x` must be a decimal, character, integer, or double vector")
  expect_error(decimal_from_double(1L), "`x` must be a double vector")
  expect_error(decimal("not-a-decimal"), "Invalid decimal string at element 1")
})

test_that("decimal formatting and reverse coercions behave as specified", {
  x <- decimal(c("1.2300", "-0", "NaN", NA_character_))

  expect_identical(format(x), c("1.2300", "-0", "NaN", NA_character_))
  expect_identical(format(decimal("0.000000123"), engineering = TRUE), "123e-9")
  expect_identical(as.double(decimal(c("1.5", "-0", "NaN", NA_character_))),
                   c(1.5, -0, NaN, NA_real_))

  expect_warning(
    expect_identical(as.double(decimal("0.1")), 0.1),
    "Lossy conversion from `decimal` to `double`"
  )
  expect_warning(
    expect_identical(as.integer(decimal(c("1.9", "-0", NA_character_))), c(1L, 0L, NA_integer_)),
    "Lossy conversion from `decimal` to `integer`"
  )
})

test_that("vec_ptype labels and casts are defined", {
  x <- decimal("1.0")

  expect_identical(vctrs::vec_ptype_abbr(x), "dec")
  expect_identical(vctrs::vec_ptype_full(x), "decimal")
  expect_s3_class(vctrs::vec_ptype2(decimal(), decimal()), "decimal")
  expect_s3_class(vctrs::vec_ptype2(decimal(), integer()), "decimal")
  expect_s3_class(vctrs::vec_ptype2(integer(), decimal()), "decimal")
  expect_s3_class(vctrs::vec_ptype2(NA, decimal()), "decimal")

  expect_error(vctrs::vec_ptype2(decimal(), double()), class = "vctrs_error_incompatible_type")
  expect_error(vctrs::vec_ptype2(decimal(), character()), class = "vctrs_error_incompatible_type")
  expect_error(vctrs::vec_ptype2(decimal(), logical()), class = "vctrs_error_incompatible_type")

  expect_identical(vctrs::vec_cast(c("1.2300", NA_character_), decimal()),
                   decimal(c("1.2300", NA_character_)))
  expect_identical(vctrs::vec_cast(c(1L, NA_integer_), decimal()),
                   decimal(c("1", NA_character_)))
  expect_identical(
    vctrs::vec_cast(c(0.5, NA_real_), decimal()),
    decimal(c("0.5", NA_character_))
  )
  expect_identical(vctrs::vec_cast(x, character()), "1.0")

  expect_error(vctrs::vec_cast(x, double()), class = "vctrs_error_cast_lossy")
  expect_error(vctrs::vec_cast(x, integer()), class = "vctrs_error_cast_lossy")
  expect_identical(vctrs::allow_lossy_cast(vctrs::vec_cast(x, double())), 1)
  expect_identical(vctrs::allow_lossy_cast(vctrs::vec_cast(decimal("1"), integer())), 1L)
})

test_that("decimal vectors behave like stable columns", {
  x <- decimal(c("1.2300", NA_character_))
  names(x) <- c("a", "b")

  expect_identical(names(x), c("a", "b"))
  expect_identical(unname(x[1]), decimal("1.2300"))
  expect_identical(vctrs::vec_c(decimal("1.2300"), 2L, NA), decimal(c("1.2300", "2", NA_character_)))

  x[2] <- 3L
  expect_identical(x, structure(decimal(c("1.2300", "3")), names = c("a", "b")))

  df <- data.frame(x = decimal(c("1", "2")))
  expect_s3_class(df$x, "decimal")

  path <- tempfile(fileext = ".rds")
  saveRDS(decimal(c("1.2300", "-0", NA_character_)), path)
  expect_identical(readRDS(path), decimal(c("1.2300", "-0", NA_character_)))
})

test_that("tibble display uses decimal type labels", {
  testthat::skip_if_not_installed("tibble")

  out <- utils::capture.output(print(tibble::tibble(x = decimal(c("1.2300", "-0")))))
  expect_true(any(grepl("<dec>", out, fixed = TRUE)))
  expect_true(any(grepl("1.2300", out, fixed = TRUE)))
})
