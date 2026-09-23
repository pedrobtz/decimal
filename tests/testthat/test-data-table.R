# data.table treats `dt[...]` as its own query syntax only when the calling
# code is data.table-aware. The package namespace these tests run in does not
# import data.table, so `dt[x > 1]` would silently behave like a data frame.
# Run queries from an environment whose top level is the global one, with the
# test's variables in scope.
dt_query <- function(expr) {
  env <- list2env(as.list(parent.frame()), parent = globalenv())
  eval(substitute(expr), env)
}

test_that("a data.table with a decimal column prints", {
  skip_if_not_installed("data.table")

  dt <- data.table::data.table(
    amount = decimal(c("1.25", "10.50", NA)),
    id = 1:3
  )
  out <- capture.output(print(dt))

  expect_true(any(grepl("<decimal>", out, fixed = TRUE)))
  expect_true(any(grepl("10.50", out, fixed = TRUE)))
  # A list column formats each element through `format()` too.
  lst <- data.table::data.table(value = list(decimal("1.5"), 1L))
  expect_no_error(capture.output(print(lst)))
})

test_that("decimal columns keep their class through data.table construction", {
  skip_if_not_installed("data.table")

  x <- decimal(c("10.00", "9.50", NA))
  expect_identical(data.table::data.table(amount = x)$amount, x)
  expect_identical(data.table::as.data.table(data.frame(amount = x))$amount, x)

  df <- data.frame(amount = x)
  data.table::setDT(df)
  expect_identical(df$amount, x)

  # rbindlist() is exact when the columns already share a scale.
  a <- data.table::data.table(amount = decimal("1.50"))
  b <- data.table::data.table(amount = decimal("2.25"))
  expect_identical(
    data.table::rbindlist(list(a, b))$amount,
    decimal(c("1.50", "2.25"))
  )
})

test_that("data.table queries filter and compute with decimal arithmetic", {
  skip_if_not_installed("data.table")

  dt <- data.table::data.table(amount = decimal(c("10.00", "9.50", "-3.00")))

  expect_identical(
    dt_query(dt[amount > decimal("5")])$amount,
    decimal(c("10.00", "9.50"))
  )
  # Without `by`, `sum()` dispatches to the decimal method.
  expect_identical(dt_query(dt[, sum(amount)]), decimal("16.50"))

  doubled <- dt_query(dt[, twice := amount * 2L])
  expect_identical(doubled$twice, decimal(c("20.00", "19.00", "-6.00")))
})

test_that("data.table joins and groups on a decimal key at a shared scale", {
  skip_if_not_installed("data.table")

  prices <- data.table::data.table(amount = decimal(c("1.50", "2.50")), v = 1:2)
  lookup <- data.table::data.table(amount = decimal("2.50"), w = 9L)

  expect_identical(dt_query(lookup[prices, on = "amount"])$w, c(NA, 9L))
  expect_identical(
    dt_query(prices[, .N, by = amount])$amount,
    prices$amount
  )
})

test_that("fwrite() writes the exact decimal strings", {
  skip_if_not_installed("data.table")

  dt <- data.table::data.table(
    amount = decimal(c("99999999999999999999.99", "0.10"))
  )
  path <- withr::local_tempfile(fileext = ".csv")
  data.table::fwrite(dt, path)

  expect_identical(
    readLines(path),
    c("amount", "99999999999999999999.99", "0.10")
  )
})

test_that("the documented data.table workarounds sort and summarize by value", {
  skip_if_not_installed("data.table")

  dt <- data.table::data.table(
    amount = decimal(c("10.00", "9.50", "-3.00", "-20.00")),
    group = c("a", "a", "b", "b")
  )

  # data.table's own sort compares the stored strings; `xtfrm()` ranks values.
  expect_identical(
    dt_query(dt[order(xtfrm(amount))])$amount,
    decimal(c("-20.00", "-3.00", "9.50", "10.00"))
  )

  # Grouped `max()` and `sum()` skip data.table's string-based fast path when
  # called through `base::`.
  by_group <- dt_query(
    dt[, .(top = base::max(amount), total = base::sum(amount)), by = group]
  )
  expect_identical(by_group$top, decimal(c("10.00", "-3.00")))
  expect_identical(by_group$total, decimal(c("19.50", "-23.00")))
})
