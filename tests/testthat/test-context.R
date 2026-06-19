test_that("default context matches roadmap defaults", {
  ctx <- get_decimal_context()

  expect_s3_class(ctx, "decimal_context")
  expect_identical(ctx$precision, 28L)
  expect_identical(ctx$rounding, "half_even")
  expect_identical(ctx$emax, 999999L)
  expect_identical(ctx$emin, -999999L)
  expect_identical(
    ctx$traps,
    c("division_by_zero", "invalid_operation", "overflow")
  )
  expect_identical(ctx$flags, character())
  expect_identical(ctx$clamp, FALSE)
  expect_identical(ctx$allcr, TRUE)
})

test_that("decimal_context validates scalar fields and signal names", {
  expect_error(decimal_context(precision = 0L), "precision")
  expect_error(decimal_context(emax = -1L), "emax")
  expect_error(decimal_context(emin = 1L), "emin")
  expect_error(decimal_context(rounding = "bogus"), "must be one of")
  expect_error(decimal_context(traps = "bogus"), "unsupported signals")
  expect_error(decimal_context(flags = c("rounded", NA_character_)), "without missing")
})

test_that("set, with, and local context restore previous state", {
  old <- get_decimal_context()
  new <- decimal_context(precision = 9L, traps = character(), flags = "rounded")

  expect_identical(set_decimal_context(new), old)
  expect_identical(get_decimal_context()$precision, 9L)
  expect_identical(get_decimal_context()$flags, "rounded")

  expect_identical(
    with_decimal_context(decimal_context(precision = 4L), get_decimal_context()$precision),
    4L
  )
  expect_identical(get_decimal_context()$precision, 9L)

  local_result <- local({
    local_decimal_context(decimal_context(precision = 5L))
    get_decimal_context()$precision
  })
  expect_identical(local_result, 5L)
  expect_identical(get_decimal_context()$precision, 9L)

  set_decimal_context(old)
})

test_that("sticky flag helpers expose and clear active flags", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)

  set_decimal_context(decimal_context(flags = c("rounded", "inexact")))
  expect_identical(decimal_flags(), c("inexact", "rounded"))
  expect_identical(clear_decimal_flags(), c("inexact", "rounded"))
  expect_identical(decimal_flags(), character())
})
