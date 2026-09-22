# Arrow interoperability.
#
# Arrow's decimal-to-string cast and mpdecimal's `mpd_to_sci()` implement the
# same General Decimal Arithmetic rule, so Arrow's own C++ cast produces this
# package's canonical storage form directly -- apart from the exponent letter,
# which Arrow writes as `E` and mpdecimal as `e`. Folding that letter makes the
# result trusted input for `new_decimal()`, which is both exact and an order of
# magnitude faster than re-parsing the strings. See
# `.agents/decisions/005-arrow-string-cast-canonical.md`.
#
# Nothing here is loaded unless an Arrow object arrives: the `as_decimal()`
# methods belong to this package's own generic, and the methods on arrow's
# generics register from `.onLoad()` only when arrow is present.

decimal_check_arrow <- function() {
  rlang::check_installed("arrow", reason = "to convert Arrow decimal values.")
}

decimal_is_arrow_decimal <- function(type) {
  inherits(type, c("Decimal32Type", "Decimal64Type")) ||
    inherits(type, c("Decimal128Type", "Decimal256Type"))
}

# Arrow writes the exponent letter as `E`; the canonical form uses `e`. Arrow
# decimals cannot hold infinities or NaNs, so `E` is the only letter that can
# appear and a fixed substitution is exact.
decimal_from_arrow_decimal <- function(x, scale) {
  values <- as.vector(arrow::call_function(
    "utf8_lower",
    x$cast(arrow::string())
  ))
  out <- new_decimal(values, scale = x$type$scale())
  scale <- decimal_resolve_scale(scale)
  if (is.null(scale)) {
    return(out)
  }
  decimal_set_scale(out, scale)
}

decimal_from_arrow <- function(x, scale) {
  decimal_check_arrow()
  if (decimal_is_arrow_decimal(x$type)) {
    return(decimal_from_arrow_decimal(x, scale))
  }
  # Any other Arrow type converts to R first, then follows the ordinary
  # `as_decimal()` rules for that R type.
  as_decimal(as.vector(x), scale = scale)
}

#' @rdname as_decimal
#' @export
as_decimal.Array <- function(x, scale = NULL) {
  decimal_from_arrow(x, scale)
}

#' @rdname as_decimal
#' @export
as_decimal.ChunkedArray <- function(x, scale = NULL) {
  decimal_from_arrow(x, scale)
}

decimal_arrow_precision <- function(x) {
  adj <- adjusted(x)
  if (all(is.na(adj))) {
    return(1L)
  }
  max(max(adj, na.rm = TRUE) + 1L + decimal_scale(x), 1L)
}

decimal_arrow_type <- function(x) {
  decimal_check_arrow()

  special <- is.infinite(x) | is.nan(x)
  if (any(special)) {
    rlang::abort(
      paste0(
        "Arrow decimal types cannot represent infinities or NaNs; ",
        "element ",
        which(special)[1L],
        " is `",
        as.character(x)[which(special)[1L]],
        "`."
      )
    )
  }

  precision <- decimal_arrow_precision(x)
  if (precision <= 38L) {
    return(arrow::decimal128(precision, decimal_scale(x)))
  }
  if (precision <= 76L) {
    return(arrow::decimal256(precision, decimal_scale(x)))
  }

  rlang::abort(
    paste0(
      "`x` needs ",
      precision,
      " digits of precision, more than the 76 digits `arrow::decimal256()` ",
      "allows. Cast to `arrow::string()` instead, or reduce the scale."
    )
  )
}

# Registered on `arrow::infer_type()` in `.onLoad()`.
infer_type.decimal <- function(x, ...) {
  decimal_arrow_type(x)
}

# Registered on `arrow::as_arrow_array()` in `.onLoad()`.
as_arrow_array.decimal <- function(x, ..., type = NULL) {
  if (is.null(type)) {
    type <- decimal_arrow_type(x)
  }
  arrow::Array$create(vctrs::vec_data(x))$cast(type)
}

decimal_register_arrow_methods <- function() {
  vctrs::s3_register("arrow::infer_type", "decimal")
  vctrs::s3_register("arrow::as_arrow_array", "decimal")
}

#' Convert an Arrow table to a data frame, keeping decimal columns exact
#'
#' `as.data.frame()` on an Arrow `Table` or `RecordBatch` converts decimal
#' columns through `double`, which silently drops digits beyond the
#' seventeenth. `arrow_as_data_frame()` converts the decimal columns with
#' [as_decimal()] instead, so they arrive as `decimal` vectors with the scale
#' declared by their Arrow type. Every other column is converted by arrow in
#' the usual way.
#'
#' @param x An Arrow `Table` or `RecordBatch`.
#'
#' @return A data frame whose decimal columns are `decimal` vectors.
#' @examples
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   tab <- arrow::arrow_table(
#'     id = 1:2,
#'     amount = arrow::Array$create(
#'       c("100.05", "99999999999999999999.99")
#'     )$cast(arrow::decimal128(25, 2))
#'   )
#'   arrow_as_data_frame(tab)
#' }
#' @export
arrow_as_data_frame <- function(x) {
  decimal_check_arrow()
  if (!inherits(x, "Table") && !inherits(x, "RecordBatch")) {
    rlang::abort("`x` must be an Arrow `Table` or `RecordBatch`.")
  }

  fields <- x$schema$fields
  columns <- lapply(seq_along(fields), function(i) {
    column <- x[[i]]
    if (decimal_is_arrow_decimal(fields[[i]]$type)) {
      return(as_decimal(column))
    }
    as.vector(column)
  })

  names(columns) <- vapply(fields, function(field) field$name, character(1))
  vctrs::new_data_frame(columns, n = x$num_rows)
}
