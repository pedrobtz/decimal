test_that("runtime version matches the vendored mpdecimal release", {
  expect_identical(mpdecimal_version(), "4.0.1")
})

test_that("package startup caches the loaded mpdecimal version", {
  expect_identical(decimal::mpdecimal_version(), "4.0.1")
  expect_identical(decimal:::.decimal_state$mpdecimal_version, "4.0.1")
})
