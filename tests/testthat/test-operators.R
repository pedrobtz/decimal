test_that("decimal arithmetic is vectorized and type stable", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  set_decimal_context(decimal_context(traps = character()))

  expect_identical(decimal("1.20") + decimal("2.3"), decimal("3.50"))
  expect_identical(decimal("5.0") - 2L, decimal("3.0"))
  expect_identical(2L * decimal("1.50"), decimal("3.00"))
  # "/" has no exact terminating scale, so the vector scale reflects what
  # mpdecimal actually computed (here, minimal/exact), not the dividend's own
  # scale (which would otherwise round 7/2 to "4").
  expect_identical(decimal("7") / decimal("2"), decimal("3.5"))
  expect_identical(decimal("2")^decimal("3"), decimal("8"))
  expect_identical(decimal("-7") %% decimal("4"), decimal("-3"))
  expect_identical(decimal("-7") %/% decimal("4"), decimal("-1"))
  expect_identical(
    +decimal(c("1.20", NA_character_)),
    decimal(c("1.20", NA_character_))
  )
  expect_identical(-decimal(c("1.20", "-0")), decimal(c("-1.20", "0")))

  expect_identical(decimal(c("1", "2")) + 1L, decimal(c("2", "3")))
  expect_error(decimal("1") + 0.5, class = "vctrs_error_incompatible_op")
  expect_error(0.5 + decimal("1"), class = "vctrs_error_incompatible_op")
})

test_that("elementwise arithmetic and comparisons preserve base-style names", {
  x <- setNames(decimal(c("1", "2")), c("a", "b"))
  y <- setNames(decimal(c("3", "4")), c("c", "d"))

  expect_identical(names(x + decimal("1")), names(x))
  expect_identical(names(decimal("1") + x), names(x))
  expect_identical(names(x + y), names(x))
  expect_identical(names(x < decimal("3")), names(x))
  expect_null(names(unname(x) + y))
})

test_that("decimal arithmetic respects context flags and traps", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)

  set_decimal_context(decimal_context(precision = 2L, traps = character()))
  clear_decimal_flags()
  expect_identical(decimal("1.25") + decimal("0"), decimal("1.2"))
  expect_identical(decimal_flags(), c("inexact", "rounded"))

  set_decimal_context(decimal_context(traps = "division_by_zero"))
  clear_decimal_flags()
  expect_error(decimal("1") / decimal("0"), class = "decimal_division_by_zero")
})

test_that("comparison operators avoid double conversion and handle special values", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)

  set_decimal_context(decimal_context(traps = character()))
  clear_decimal_flags()

  expect_identical(decimal("1.0") == decimal("1"), TRUE)
  expect_identical(decimal("1.0") != decimal("2"), TRUE)
  expect_identical(decimal("-2") < decimal("1"), TRUE)
  expect_identical(decimal("-2") <= decimal("-2.0"), TRUE)
  expect_identical(decimal("3") > 2L, TRUE)
  expect_identical(2L >= decimal("2.0"), TRUE)
  expect_identical(
    decimal(c("1", NA_character_)) < decimal(c("2", "3")),
    c(TRUE, NA)
  )

  expect_identical(decimal("NaN") == decimal("1"), NA)
  expect_identical(decimal("NaN") != decimal("1"), NA)
  expect_identical(decimal("NaN") < decimal("1"), NA)
  expect_identical(decimal_flags(), character())

  expect_identical(decimal("sNaN") == decimal("1"), NA)
  expect_true("invalid_operation" %in% decimal_flags())

  set_decimal_context(decimal_context(traps = "invalid_operation"))
  clear_decimal_flags()
  expect_error(
    decimal("sNaN") < decimal("1"),
    class = "decimal_invalid_operation"
  )
})

test_that("equality and ordering are scale-invariant: 1.0 and 1 are the same value", {
  x <- decimal(c("1.0", "1", "-0", "0", "NaN", "NaN", NA_character_, "2", "-2"))

  expect_identical(
    vctrs::vec_equal(decimal("1.0"), decimal("1"), na_equal = TRUE),
    TRUE
  )
  expect_identical(
    vctrs::vec_equal(decimal("-0"), decimal("0"), na_equal = TRUE),
    TRUE
  )
  expect_identical(
    vctrs::vec_equal(decimal("NaN"), decimal("NaN"), na_equal = TRUE),
    TRUE
  )

  # A single decimal() call infers one shared scale, so "1.0" and "1" among
  # these inputs are stored identically once constructed together.
  expect_identical(
    unique(x),
    decimal(c("1.0", "-0", "NaN", NA_character_, "2", "-2"))
  )
  expect_identical(
    vctrs::vec_match(decimal(c("1", "-0", "NaN", NA_character_)), x),
    c(1L, 3L, 5L, 7L)
  )

  expect_identical(
    sort(decimal(c(
      "2",
      "-2",
      "0",
      "-0",
      "1.0",
      "1",
      "Infinity",
      "-Infinity",
      "NaN"
    ))),
    decimal(c("-Infinity", "-2", "0", "-0", "1.0", "1", "2", "Infinity", "NaN"))
  )
})

# Sets the collation for the calling test, or skips the test when the
# platform lacks that locale.
local_collation <- function(locale, env = parent.frame()) {
  if (!identical(locale, "C")) {
    old <- Sys.getlocale("LC_COLLATE")
    set <- suppressWarnings(Sys.setlocale("LC_COLLATE", locale))
    Sys.setlocale("LC_COLLATE", old)
    if (identical(set, "")) {
      skip(paste0("Locale ", locale, " is not available."))
    }
  }
  withr::local_collate(locale, .local_envir = env)
}

order_sample <- function() {
  withr::local_seed(46)
  finite <- sprintf(
    "%s%d.%03d",
    sample(c("-", ""), 60, replace = TRUE),
    sample(0:120, 60, replace = TRUE),
    sample(0:999, 60, replace = TRUE)
  )
  special <- c(
    "-1.25",
    "-1.2",
    "-1.205",
    "-12",
    "-120",
    "-0.012",
    "-1",
    "1",
    "1.2",
    "1.25",
    "12",
    "0",
    "-0",
    "0.000",
    "Infinity",
    "-Infinity",
    "NaN",
    NA_character_
  )
  decimal(sample(c(finite, special)))
}

test_that("vctrs orders negative decimals by value in any collation (#46)", {
  for (locale in c("C", "en_US.UTF-8", "de_DE.UTF-8", "sv_SE.UTF-8")) {
    local({
      local_collation(locale)
      x <- order_sample()

      expect_identical(
        vctrs::vec_sort(decimal(c("-1.25", "-1.2"))),
        decimal(c("-1.25", "-1.20")),
        info = locale
      )
      expect_identical(vctrs::vec_order(x), order(x), info = locale)
      expect_identical(vctrs::vec_sort(x), x[order(x)], info = locale)
      expect_identical(
        vctrs::vec_sort(x, direction = "desc"),
        x[order(x, decreasing = TRUE, na.last = FALSE)],
        info = locale
      )
      expect_identical(
        vctrs::vec_rank(x, ties = "min", incomplete = "na"),
        as.integer(rank(xtfrm(x), ties.method = "min", na.last = "keep")),
        info = locale
      )
    })
  }
})

test_that("dplyr and tidyr order decimals by value under ICU collation (#46)", {
  skip_if_not_installed("dplyr")
  skip_if_not_installed("stringi")
  local_collation("en_US.UTF-8")
  x <- order_sample()
  df <- data.frame(x = x)

  expect_identical(dplyr::arrange(df, x, .locale = "en")$x, x[order(x)])
  expect_identical(dplyr::arrange(df, x)$x, x[order(x)])
  expect_identical(
    dplyr::arrange(df, dplyr::desc(x), .locale = "en")$x,
    x[order(x, decreasing = TRUE, na.last = TRUE)]
  )

  # An inequality join orders both sides together.
  left <- data.frame(a = decimal(c("-1.25", "-1.2", "0.5")))
  right <- data.frame(b = decimal(c("-1.21", "0")))
  joined <- dplyr::inner_join(left, right, by = dplyr::join_by(a > b))
  expect_identical(joined$a, decimal(c("-1.20", "0.50", "0.50")))
  expect_identical(joined$b, decimal(c("-1.21", "-1.21", "0.00")))

  skip_if_not_installed("tidyr")
  expect_identical(tidyr::expand(df, x)$x, unique(x[order(x)]))
})

test_that("vctrs comparisons agree with the comparison operators (#46)", {
  local_collation("en_US.UTF-8")
  x <- order_sample()
  y <- rev(x)
  known <- !is.na(x) & !is.na(y) & !is.nan(x) & !is.nan(y)

  expected <- ifelse(x < y, -1L, ifelse(x > y, 1L, 0L))
  expect_identical(vctrs::vec_compare(x, y)[known], expected[known])
})
