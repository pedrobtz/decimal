test_that("decimal constructors infer a shared vector scale", {
  expect_s3_class(decimal(), "decimal")
  expect_identical(length(decimal()), 0L)
  expect_true(is_decimal(decimal("1.2300")))

  expect_identical(as.character(decimal("1.2300")), "1.2300")
  expect_identical(
    as.character(decimal(c("1.2", "756.56"))),
    c("1.20", "756.56")
  )
  expect_identical(
    as.character(decimal(c(1L, NA_integer_, -2L))),
    c("1", NA_character_, "-2")
  )
  expect_identical(NA_decimal_, decimal(NA_character_))
})

test_that("scale is a shared vector property, not a per-element one", {
  x <- decimal(c("1.2300", "-0", "NaN", NA_character_))

  expect_identical(attr(x, "scale"), 4L)
  expect_identical(
    as.character(x),
    c("1.2300", "-0.0000", "NaN", NA_character_)
  )
  expect_true(decimal("1.2") == decimal("1.20"))
  expect_identical(decimal(c("1.2", "1.20")), decimal(c("1.20", "1.20")))
})

test_that("scale can be set explicitly and rescaled after construction", {
  expect_identical(as.character(decimal("1.2", scale = 4L)), "1.2000")
  expect_identical(attr(decimal("1.2", scale = 4L), "scale"), 4L)
  expect_identical(
    as.character(as_decimal(decimal("1.2"), scale = 4L)),
    "1.2000"
  )

  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))
  expect_identical(as.character(decimal("1.256", scale = 2L)), "1.26")
})

test_that("promotion to a finer shared scale is exact and context-free", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(precision = 1L))
  clear_decimal_flags()

  expect_identical(
    decimal(c("1.2", "1.23")),
    decimal(c("1.20", "1.23"), scale = 2L)
  )
  expect_identical(
    vctrs::vec_c(decimal("1.2"), decimal("1.23")),
    decimal(c("1.20", "1.23"), scale = 2L)
  )

  x <- decimal(c("1.2", "3.4"))
  x[2] <- decimal("1.23")
  expect_identical(x, decimal(c("1.20", "1.23"), scale = 2L))
  expect_identical(decimal_flags(), character())
})

test_that("double conversion requires an explicit scale", {
  withr::local_options(decimal.default_scale = NULL)

  expect_error(
    decimal_from_double(0.1),
    "`scale` must be provided for double conversion"
  )
  expect_error(
    as_decimal(0.1),
    "`scale` must be provided for double conversion"
  )

  expect_identical(
    as.character(decimal_from_double(
      c(0.5, -0, Inf, -Inf, NaN, NA_real_),
      scale = 2L
    )),
    c("0.50", "-0.00", "Infinity", "-Infinity", "NaN", NA_character_)
  )
  expect_identical(attr(decimal_from_double(0.5, scale = 2L), "scale"), 2L)
})

test_that("decimal.default_scale supplies an opt-in conversion scale", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))
  withr::local_options(decimal.default_scale = 7L)

  expect_identical(as_decimal(0.002), decimal("0.0020000", scale = 7L))
  expect_identical(decimal_from_double(0.002), decimal("0.0020000", scale = 7L))
  expect_identical(as_decimal("1.2"), decimal("1.2000000", scale = 7L))
  expect_identical(as_decimal(1L), decimal("1.0000000", scale = 7L))
  expect_identical(
    as_decimal(decimal("1.2", scale = 1L)),
    decimal("1.2000000", scale = 7L)
  )
  expect_identical(
    as_decimal(0.002, scale = 3L),
    decimal("0.002", scale = 3L)
  )
})

test_that("decimal.default_scale must be an integer scalar", {
  condition <- local({
    withr::local_options(decimal.default_scale = "7")
    rlang::catch_cnd(as_decimal("1"))
  })

  expect_s3_class(condition, "rlang_error")
  expect_match(conditionMessage(condition), "`decimal.default_scale` must be")
})

test_that("unsupported construction paths fail cleanly", {
  expect_error(
    as_decimal(TRUE),
    "`x` must be a decimal, character, integer, or double vector"
  )
  expect_error(
    decimal_from_double(1L, scale = 2L),
    "`x` must be a double vector"
  )
  expect_error(decimal("not-a-decimal"), "Invalid decimal string at element 1")
})

test_that("decimal formatting and reverse coercions behave as specified", {
  x <- decimal(c("1.2300", "-0", "NaN", NA_character_))

  expect_identical(format(x), c("1.2300", "-0.0000", "NaN", NA_character_))
  expect_error(format(x, scientific = TRUE), "Can't apply `scientific`")
  # `format.data.frame()` injects these into `...` for every column; they are
  # tolerated so a decimal column can be printed, but never honored.
  expect_identical(format(x, digits = 2), format(x))
  expect_identical(format(x, na.encode = FALSE), format(x))
  expect_identical(format(x, justify = "left"), format(x))
  expect_error(format(x, engineering = 1), "`engineering` must be")
  expect_identical(
    format(decimal_from_double(0.000000123, scale = 20), engineering = TRUE),
    "123.00000000000e-9"
  )
  # "-0" is padded to "-0.0" by the shared vector scale (inferred from
  # "1.5"); that trailing zero is declared significance a double can't hold,
  # so the cast is lossy even though the numeric value round-trips exactly.
  expect_warning(
    expect_identical(
      as.double(decimal(c("1.5", "-0", "NaN", NA_character_))),
      c(1.5, -0, NaN, NA_real_)
    ),
    "Lossy conversion from `decimal` to `double`"
  )

  expect_warning(
    expect_identical(as.double(decimal("0.1")), 0.1),
    "Lossy conversion from `decimal` to `double`"
  )
  expect_warning(
    expect_identical(
      as.integer(decimal(c("1.9", "-0", NA_character_))),
      c(1L, 0L, NA_integer_)
    ),
    "Lossy conversion from `decimal` to `integer`"
  )
})

test_that("constructors, formatting, and coercions preserve names", {
  input <- c(a = "1.20", b = "2.00")
  x <- decimal(input)

  expect_identical(names(x), names(input))
  expect_identical(names(format(x)), names(input))
  expect_identical(names(as.character(x)), names(input))
  expect_identical(names(suppressWarnings(as.double(x))), names(input))
  expect_identical(names(suppressWarnings(as.integer(x))), names(input))
})

test_that("vec_ptype labels and casts are defined", {
  x <- decimal("1.0")

  expect_identical(vctrs::vec_ptype_abbr(x), "dec")
  expect_identical(vctrs::vec_ptype_full(x), "decimal")
  expect_s3_class(vctrs::vec_ptype2(decimal(), decimal()), "decimal")
  expect_s3_class(vctrs::vec_ptype2(decimal(), integer()), "decimal")
  expect_s3_class(vctrs::vec_ptype2(integer(), decimal()), "decimal")
  expect_s3_class(vctrs::vec_ptype2(NA, decimal()), "decimal")

  expect_error(
    vctrs::vec_ptype2(decimal(), double()),
    class = "vctrs_error_incompatible_type"
  )
  expect_error(
    vctrs::vec_ptype2(decimal(), character()),
    class = "vctrs_error_incompatible_type"
  )
  expect_error(
    vctrs::vec_ptype2(decimal(), logical()),
    class = "vctrs_error_incompatible_type"
  )

  expect_identical(
    vctrs::vec_cast(c("1.2300", NA_character_), decimal()),
    decimal(c("1.2300", NA_character_))
  )
  expect_identical(
    vctrs::vec_cast(c(1L, NA_integer_), decimal()),
    decimal(c("1", NA_character_))
  )
  expect_error(
    vctrs::vec_cast(c(0.5, NA_real_), decimal()),
    "requires an explicit scale"
  )
  expect_identical(vctrs::vec_cast(x, character()), "1.0")

  expect_error(vctrs::vec_cast(x, double()), class = "vctrs_error_cast_lossy")
  expect_error(vctrs::vec_cast(x, integer()), class = "vctrs_error_cast_lossy")
  expect_identical(vctrs::allow_lossy_cast(vctrs::vec_cast(x, double())), 1)
  expect_identical(
    vctrs::allow_lossy_cast(vctrs::vec_cast(decimal("1"), integer())),
    1L
  )
})

test_that("combining decimal vectors promotes to the common (max) scale", {
  expect_identical(
    vctrs::vec_c(decimal("1.2"), decimal("2.345")),
    decimal(c("1.200", "2.345"))
  )
  expect_identical(
    vctrs::vec_c(decimal("1.20"), 2L, NA),
    decimal(c("1.20", "2.00", NA_character_))
  )
})

test_that("decimal vectors behave like stable columns", {
  x <- decimal(c("1.2300", NA_character_))
  names(x) <- c("a", "b")

  expect_identical(names(x), c("a", "b"))
  expect_identical(unname(x[1]), decimal("1.2300"))
  expect_identical(
    vctrs::vec_c(decimal("1.2300"), 2L, NA),
    decimal(c("1.2300", "2.0000", NA_character_))
  )

  x[2] <- 3L
  expect_identical(
    x,
    structure(decimal(c("1.2300", "3.0000")), names = c("a", "b"))
  )

  df <- data.frame(x = decimal(c("1", "2")))
  expect_s3_class(df$x, "decimal")

  path <- tempfile(fileext = ".rds")
  saveRDS(decimal(c("1.2300", "-0", NA_character_)), path)
  expect_identical(readRDS(path), decimal(c("1.2300", "-0", NA_character_)))
})

test_that("tibble display uses decimal type labels", {
  testthat::skip_if_not_installed("tibble")

  out <- utils::capture.output(print(tibble::tibble(
    x = decimal(c("1.2300", "-0"))
  )))
  expect_true(any(grepl("<dec>", out, fixed = TRUE)))
  expect_true(any(grepl("1.2300", out, fixed = TRUE)))
})

test_that("decimal columns print inside a base data frame", {
  df <- data.frame(id = 1:3)
  df$amount <- decimal(c("1.25", "2.50", NA))

  # `print.data.frame()` reaches `format.decimal()` through
  # `format.data.frame()`, which passes `digits`, `na.encode` and `justify`.
  expect_no_error(capture.output(print(df)))
  # `format.data.frame()` wraps each formatted column in `AsIs`.
  expect_identical(as.character(format(df)$amount), c("1.25", "2.50", NA))
})

test_that("format() ignores the arguments other table printers pass", {
  x <- decimal(c("1.25", NA))

  # data.table passes `timezone`; knitr::kable() passes `trim`.
  expect_identical(
    format(x, na.encode = FALSE, timezone = FALSE, justify = "none"),
    format(x)
  )
  expect_identical(format(x, trim = TRUE), format(x))
  expect_identical(format(x, width = 12), format(x))
})

test_that("format() refuses arguments that would change the digits shown", {
  x <- decimal("1234.5")

  expect_error(format(x, nsmall = 2), "Can't apply `nsmall`")
  expect_error(format(x, big.mark = ","), "Can't apply `big.mark`")
  expect_error(format(x, drop0trailing = TRUE), "Can't apply `drop0trailing`")
})

test_that("base rbind() binds data frames with decimal columns", {
  a <- data.frame(id = 1L, amount = decimal("1.5"))
  b <- data.frame(id = 2:3, amount = decimal(c("2.25", NA)))

  # `rbind.data.frame()` grows each column by assigning past its end.
  out <- rbind(a, b)
  expect_identical(out$amount, decimal(c("1.50", "2.25", NA)))
  expect_identical(rbind(b, a)$amount, decimal(c("2.25", NA, "1.50")))
})

test_that("assigning past the end grows a decimal vector with missing values", {
  x <- decimal(c("1.5", "2.5"))
  x[4] <- decimal("3.25")

  expect_identical(x, decimal(c("1.50", "2.50", NA, "3.25")))
})

test_that("match() and %in% compare values, not their scales", {
  x <- decimal(c("2.5", "20", "0", NA))
  table <- decimal(c("20.00", "2.50", "-0.00", NA))

  expect_identical(match(x, table), c(2L, 1L, 3L, 4L))
  expect_identical(decimal("2.5") %in% decimal("1.25"), FALSE)

  # Whole numbers still match integers and plain strings.
  expect_identical(
    decimal(c("20", "20.00", "7")) %in% c(10L, 20L),
    c(TRUE, TRUE, FALSE)
  )
  expect_identical(
    decimal(c("2.50", "300")) %in% c("2.5", "300"),
    c(TRUE, TRUE)
  )

  # A merge on a decimal key matches across scales.
  left <- data.frame(amount = decimal("2.5"), v = 1L)
  right <- data.frame(amount = decimal(c("1.25", "2.50")), w = 1:2)
  expect_identical(merge(left, right)$w, 2L)
})

test_that("decimal columns print in a knitr table", {
  skip_if_not_installed("knitr")

  df <- data.frame(amount = decimal(c("1.25", "10.50")))
  out <- as.character(knitr::kable(df))

  expect_true(any(grepl("10.50", out, fixed = TRUE)))
})

test_that("a decimal object that holds doubles is refused rather than printed", {
  bad <- structure(c(1, 2), class = c("decimal", "vctrs_vctr"), scale = 2L)

  expect_error(format(bad), "holds doubles")
  expect_error(as.character(bad), "holds doubles")
})
