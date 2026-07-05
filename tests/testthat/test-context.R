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

test_that("non-trapped signals are reported as warnings by default", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  withr::local_options(decimal.report_flags = TRUE)

  set_decimal_context(decimal_context(precision = 2L, traps = character()))
  clear_decimal_flags()

  # 1.25 rounds to 1.2 at precision 2: inexact + rounded, neither trapped.
  expect_warning(
    result <- decimal("1.25") + decimal("0"),
    class = "decimal_flags_warning"
  )
  expect_identical(result, decimal("1.2"))
  # The warning does not stop flags from accumulating.
  expect_true(all(c("inexact", "rounded") %in% decimal_flags()))

  # The condition carries the raised signals and the operation.
  cnd <- rlang::catch_cnd(decimal("1.25") + decimal("0"), classes = "decimal_flags_warning")
  expect_true(all(c("inexact", "rounded") %in% cnd$signals))
  expect_identical(cnd$operation, "+")
})

test_that("decimal.report_flags = FALSE silences flag warnings but keeps flags", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  withr::local_options(decimal.report_flags = FALSE)

  set_decimal_context(decimal_context(precision = 2L, traps = character()))
  clear_decimal_flags()

  expect_no_warning(result <- decimal("1.25") + decimal("0"))
  expect_identical(result, decimal("1.2"))
  expect_true(all(c("inexact", "rounded") %in% decimal_flags()))
})

test_that("trapped signals still error rather than warn", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  withr::local_options(decimal.report_flags = TRUE)

  # division_by_zero is trapped by default: an error, never a warning.
  expect_error(
    decimal("1") / decimal("0"),
    class = "decimal_division_by_zero"
  )
})

test_that("exact operations raise no flag warning", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  withr::local_options(decimal.report_flags = TRUE)

  set_decimal_context(decimal_context(traps = character()))
  expect_no_warning(decimal("1.20") + decimal("2.30"))
})

test_that("quantize()/round()/signif() don't warn for their own inexact/rounded signals", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  withr::local_options(decimal.report_flags = TRUE)

  set_decimal_context(decimal_context(traps = character()))
  clear_decimal_flags()

  expect_no_warning(result <- quantize(decimal("1.23456"), decimal("0.01")))
  expect_identical(result, decimal("1.23"))
  expect_no_warning(round(decimal("1.25"), digits = 1))
  expect_no_warning(signif(decimal("1234.5"), digits = 3))
  expect_true(all(c("inexact", "rounded") %in% decimal_flags()))

  # An ordinary arithmetic op still warns for the same signals.
  set_decimal_context(decimal_context(precision = 2L, traps = character()))
  expect_warning(
    decimal("1.25") + decimal("0"),
    class = "decimal_flags_warning"
  )
})

test_that("sqrt()/exp()/log()/log10() don't warn for their near-universal inexactness", {
  old <- get_decimal_context()
  on.exit(set_decimal_context(old), add = TRUE)
  withr::local_options(decimal.report_flags = TRUE)

  set_decimal_context(decimal_context(precision = 10L, traps = character()))
  clear_decimal_flags()

  expect_no_warning(sqrt(decimal("2")))
  expect_no_warning(exp(decimal("1")))
  expect_no_warning(log(decimal("2")))
  expect_no_warning(log10(decimal("3")))
  expect_true(all(c("inexact", "rounded") %in% decimal_flags()))

  # Exact cases raise no signal at all, so nothing to warn about either way.
  clear_decimal_flags()
  expect_no_warning(expect_identical(sqrt(decimal("4")), decimal("2")))
  expect_identical(decimal_flags(), character())

  # Division is only *sometimes* inexact, so it is not exempt: it still warns.
  expect_no_warning(decimal("7") / decimal("2"))
  expect_warning(
    decimal("1") / decimal("3"),
    class = "decimal_flags_warning"
  )
})
