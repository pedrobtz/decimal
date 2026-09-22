# Arrow interoperability.
#
# Two facts keep this file small. Arrow's decimal-to-string cast and
# mpdecimal's `mpd_to_sci()` implement the same General Decimal Arithmetic
# rule, so Arrow's own C++ cast produces this package's canonical storage form
# apart from the exponent letter, which Arrow writes as `E` and mpdecimal as
# `e` (ADR 005). And an Arrow extension type carries a real decimal as its
# storage while leaving the conversion back to R in this package's hands, so a
# column written from R returns as a `decimal` vector on every read path and
# every other reader sees a plain decimal (ADR 006).
#
# The `as_decimal()` methods belong to this package's generic and dispatch only
# when an Arrow object arrives. The methods on arrow's generics are registered
# by NAMESPACE when arrow loads, and the extension type from `.onLoad()`.

#' Arrow interoperability
#'
#' @description
#' `decimal` vectors convert to and from Arrow decimal arrays exactly, in both
#' directions, when the arrow package is installed.
#'
#' **Arrow to decimal.** [as_decimal()] accepts an Arrow `Array` or
#' `ChunkedArray`. A `decimal32()`, `decimal64()`, `decimal128()` or
#' `decimal256()` array converts exactly, taking its scale from the Arrow
#' type. An integer array of any width converts exactly too. Other Arrow
#' types convert to the equivalent R vector first and follow the ordinary
#' [as_decimal()] rules. [arrow_as_data_frame()] applies the same conversion
#' to every decimal field of a `Table` or `RecordBatch`.
#'
#' **Decimal to Arrow.** A `decimal` vector becomes a decimal field wherever
#' arrow infers types: `arrow::as_arrow_array()`, `arrow::arrow_table()`,
#' `arrow::write_parquet()` and `arrow::write_dataset()`. By default the field
#' is an Arrow *extension type* whose storage is a real `decimal128()` or
#' `decimal256()` with the vector's scale and a precision inferred from the
#' values. Other readers see the storage, a plain decimal column. In R the
#' column returns as a `decimal` vector on every read path, `as.data.frame()`,
#' `arrow::read_parquet()` and `dplyr::collect()` included.
#' [arrow_decimal_type()] pins a precision and scale.
#'
#' Arrow's compute engine does not operate on extension columns, so arrow-side
#' arithmetic or filtering on such a column fails. To write a plain field
#' instead, pass a plain Arrow decimal type as `type` to
#' `arrow::as_arrow_array()`, or set the option below. A plain field comes
#' back from arrow's own conversion as a `double` wearing the `decimal` class,
#' because arrow reapplies the column's recorded R attributes; the package
#' refuses to format such an object. Read those tables with
#' [arrow_as_data_frame()].
#'
#' Infinities and NaNs have no Arrow decimal representation and raise an error
#' on conversion to Arrow.
#'
#' @section Options:
#' `decimal.arrow_extension`: `TRUE` (the default) writes the extension type;
#' `FALSE` writes plain decimal fields everywhere.
#'
#' @seealso `vignette("arrow-decimal-types")`.
#' @name decimal_arrow
NULL

decimal_check_arrow <- function() {
  rlang::check_installed("arrow", reason = "to convert Arrow decimal values.")
}

decimal_is_arrow_decimal <- function(type) {
  inherits(type, "DecimalType")
}

decimal_is_arrow_integer <- function(type) {
  inherits(
    type,
    c("Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64")
  )
}

decimal_is_arrow_extension <- function(type) {
  inherits(type, "DecimalExtensionType")
}

# The extension type -------------------------------------------------------

decimal_arrow_env <- new.env(parent = emptyenv())

# `self` is bound by R6 inside the methods below.
utils::globalVariables("self")

# Built on first use rather than at load, because the class inherits from
# arrow's and arrow is only suggested.
decimal_arrow_extension_class <- function() {
  if (is.null(decimal_arrow_env$class)) {
    decimal_arrow_env$class <- R6::R6Class(
      "DecimalExtensionType",
      inherit = arrow::ExtensionType,
      public = list(
        as_vector = function(extension_array) {
          as_decimal(decimal_arrow_storage(extension_array))
        },
        ToString = function() {
          paste0("decimal<", self$storage_type()$ToString(), ">")
        }
      )
    )
  }
  decimal_arrow_env$class
}

decimal_arrow_extension_type <- function(storage) {
  arrow::new_extension_type(
    storage_type = storage,
    extension_name = "r.decimal",
    type_class = decimal_arrow_extension_class()
  )
}

# Registering the name is enough: arrow rebuilds an instance for whatever
# storage type a file declares.
decimal_register_arrow_extension <- function() {
  arrow::reregister_extension_type(
    decimal_arrow_extension_type(arrow::decimal128(1L, 0L))
  )
  invisible()
}

# Called from `.onLoad()`. arrow may load later, or never.
decimal_register_arrow <- function() {
  if (isNamespaceLoaded("arrow")) {
    decimal_register_arrow_extension()
    return(invisible())
  }
  setHook(
    packageEvent("arrow", "onLoad"),
    function(...) decimal_register_arrow_extension()
  )
  invisible()
}

# The plain decimal array beneath an extension array, or `x` unchanged.
decimal_arrow_storage <- function(x) {
  if (!decimal_is_arrow_extension(x$type)) {
    return(x)
  }
  if (inherits(x, "ChunkedArray")) {
    chunks <- lapply(x$chunks, function(chunk) chunk$storage())
    return(do.call(
      arrow::ChunkedArray$create,
      c(chunks, list(type = x$type$storage_type()))
    ))
  }
  x$storage()
}

#' Arrow type for a decimal column
#'
#' Builds the Arrow extension type this package writes `decimal` vectors as,
#' with a chosen precision and scale rather than ones inferred from the
#' values. Use it to pin the type of a column that will be appended to, for
#' example through the `schema` argument of `arrow::arrow_table()` or the
#' `type` argument of `arrow::as_arrow_array()`. The storage is
#' `arrow::decimal128()` up to 38 digits of precision and
#' `arrow::decimal256()` above that.
#'
#' @param precision Total number of digits, at most 76.
#' @param scale Number of fractional digits.
#'
#' @return An Arrow extension type.
#' @seealso [decimal_arrow] for how the type behaves.
#' @examples
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   arrow_decimal_type(20, 2)
#'   arrow::as_arrow_array(decimal("1.25"), type = arrow_decimal_type(20, 2))
#' }
#' @export
arrow_decimal_type <- function(precision, scale = 0L) {
  decimal_check_arrow()
  storage <- if (precision <= 38L) {
    arrow::decimal128(precision, scale)
  } else {
    arrow::decimal256(precision, scale)
  }
  decimal_arrow_extension_type(storage)
}

# Arrow to decimal ---------------------------------------------------------

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
  x <- decimal_arrow_storage(x)
  if (decimal_is_arrow_decimal(x$type)) {
    return(decimal_from_arrow_decimal(x, scale))
  }
  if (decimal_is_arrow_integer(x$type)) {
    # Arrow's cast to string is exact at every width. `as.vector()` would hand
    # back an integer64, or a rounded double, for int64 and uint64 values.
    return(as_decimal(as.vector(x$cast(arrow::string())), scale = scale))
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

# Decimal to Arrow ---------------------------------------------------------

decimal_arrow_check_representable <- function(x) {
  special <- is.infinite(x) | is.nan(x)
  if (any(special)) {
    first <- which(special)[1L]
    rlang::abort(paste0(
      "Arrow decimal types cannot represent infinities or NaNs; element ",
      first,
      " is `",
      as.character(x)[first],
      "`."
    ))
  }
  invisible(x)
}

decimal_arrow_precision <- function(x) {
  adj <- adjusted(x)
  if (all(is.na(adj))) {
    return(1L)
  }
  max(max(adj, na.rm = TRUE) + 1L + decimal_scale(x), 1L)
}

# The plain Arrow decimal type that holds every value of `x`.
decimal_arrow_storage_type <- function(x) {
  decimal_arrow_check_representable(x)
  precision <- decimal_arrow_precision(x)
  scale <- decimal_scale(x)
  if (precision <= 38L) {
    return(arrow::decimal128(precision, scale))
  }
  if (precision <= 76L) {
    return(arrow::decimal256(precision, scale))
  }
  rlang::abort(paste0(
    "`x` needs ",
    precision,
    " digits of precision, more than the 76 digits `arrow::decimal256()` ",
    "allows. Cast to `arrow::string()` instead, or reduce the scale."
  ))
}

decimal_arrow_use_extension <- function() {
  isTRUE(getOption("decimal.arrow_extension", TRUE))
}

#' @exportS3Method arrow::infer_type
infer_type.decimal <- function(x, ...) {
  decimal_check_arrow()
  storage <- decimal_arrow_storage_type(x)
  if (decimal_arrow_use_extension()) {
    return(decimal_arrow_extension_type(storage))
  }
  storage
}

#' @exportS3Method arrow::as_arrow_array
as_arrow_array.decimal <- function(x, ..., type = NULL) {
  decimal_check_arrow()
  if (is.null(type)) {
    type <- infer_type.decimal(x)
  }
  storage <- if (decimal_is_arrow_extension(type)) {
    type$storage_type()
  } else {
    type
  }
  if (decimal_is_arrow_decimal(storage)) {
    decimal_arrow_check_representable(x)
  }
  out <- arrow::Array$create(vctrs::vec_data(x))$cast(storage)
  if (decimal_is_arrow_extension(type)) {
    return(arrow::new_extension_array(out, type))
  }
  out
}

# Tables -------------------------------------------------------------------

#' Convert an Arrow table to a data frame, keeping decimal columns exact
#'
#' `as.data.frame()` on an Arrow `Table` or `RecordBatch` converts a plain
#' decimal field through `double`, which silently drops digits beyond the
#' seventeenth. `arrow_as_data_frame()` converts those fields with
#' [as_decimal()] instead, so they arrive as `decimal` vectors with the scale
#' declared by their Arrow type. Every other column, including decimal columns
#' this package wrote as its extension type, is converted by arrow in the
#' usual way.
#'
#' @param x An Arrow `Table` or `RecordBatch`.
#'
#' @return A data frame whose decimal columns are `decimal` vectors.
#' @seealso [decimal_arrow] for when a decimal field is plain and when it is
#'   the extension type.
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
  if (!inherits(x, c("Table", "RecordBatch"))) {
    rlang::abort("`x` must be an Arrow `Table` or `RecordBatch`.")
  }

  out <- as.data.frame(x)
  fields <- x$schema$fields
  for (i in seq_along(fields)) {
    if (decimal_is_arrow_decimal(fields[[i]]$type)) {
      out[[i]] <- as_decimal(x[[i]])
    }
  }
  out
}
