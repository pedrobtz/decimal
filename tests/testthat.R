# testthat is a suggested package: CRAN's NOSUGGESTS check runs the tests
# without it, and an unguarded library(testthat) would fail there.
if (requireNamespace("testthat", quietly = TRUE)) {
  library(testthat)
  library(decimal)

  test_check("decimal")
}
