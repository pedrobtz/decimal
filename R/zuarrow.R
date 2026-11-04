# zuarrow interoperability.
#
# zuarrow converts Arrow columns on the rule "exact or error". Without a
# registration, every Arrow decimal column is an error that names this package.
# When zuarrow is loaded, this package registers itself as the exact R form of
# every Arrow decimal type (`"d:*"`) and of its own `r.decimal` extension
# type.
#
# Both handlers read and write the Arrow buffers directly, in src/arrow.c,
# without calling back into zuarrow.

#' zuarrow interoperability
#'
#' @description
#' When the zuarrow package is installed, `decimal` registers itself with
#' zuarrow as the exact R form of every Arrow decimal type. zuarrow then
#' converts decimal columns in both directions without loss, where it would
#' otherwise raise an error. The registration happens when both packages are
#' loaded, in either order.
#'
#' **Arrow to decimal.** A `decimal32`, `decimal64`, `decimal128` or
#' `decimal256` column becomes a `decimal` vector with the scale of its Arrow
#' type. A `decimal` vector has no precision, so the Arrow precision is not
#' kept. Nulls become `NA`. A column of this package's `r.decimal` extension
#' type, as written through the arrow package, converts the same way.
#'
#' **Decimal to Arrow.** A `decimal` vector becomes a `decimal128` array of
#' precision 38 when the scale and every value fit in 38 digits, and a
#' `decimal256` array of precision 76 when they fit in 76. The scale is the
#' vector's scale. The precision is the width's maximum rather than the
#' smallest that holds the values, so every batch of a column gets the same
#' type. `NA` becomes a null and a negative zero becomes zero.
#'
#' A vector that needs more than 76 digits, or that holds an infinity or a
#' NaN, has no Arrow decimal form and raises an error of class
#' `decimal_arrow_error`. Values are never rounded.
#'
#' @seealso [decimal_arrow] for the arrow package.
#' @name decimal_zuarrow
#' @examples
#' if (requireNamespace("zuarrow", quietly = TRUE)) {
#'   array <- zuarrow::arrow_array(decimal(c("1.25", NA, "-1000.50")))
#'   array
#'   zuarrow::arrow_to_r(array)
#' }
NULL

decimal_zuarrow_keys <- c("d:*", "r.decimal")

# Arrow C Data handles -----------------------------------------------------
#
# The conversion itself needs no Arrow package: src/arrow.c reads and writes
# the decimal buffers of a handle in nanoarrow's `r.h` layout. The zuarrow
# handlers below are thin wrappers, and methods for nanoarrow's generics can
# call the same two functions.

# An Arrow decimal array handle to a `decimal` vector with the type's scale.
# `schema` defaults to the schema the array handle carries in its tag.
decimal_arrow_decode <- function(array, schema = NULL) {
  out <- .Call(decimal_c_arrow_decode, array, schema)
  new_decimal(out$values, scale = out$scale)
}

# The Arrow decimal type for `x`: decimal128 up to 38 digits, decimal256 up
# to 76, each at the width's maximum precision so the type does not depend on
# which rows a batch holds.
decimal_arrow_handle_type <- function(x) {
  decimal_arrow_check_representable(x)
  scale <- decimal_scale(x)
  digits <- decimal_arrow_precision(x)
  if (digits <= 38L) {
    return(list(precision = 38L, scale = scale, bits = 128L))
  }
  if (digits <= 76L) {
    return(list(precision = 76L, scale = scale, bits = 256L))
  }
  rlang::abort(
    paste0(
      "`x` needs ",
      digits,
      " digits of precision, more than the 76 digits an Arrow decimal256 ",
      "holds."
    ),
    class = "decimal_arrow_error"
  )
}

# A `decimal` vector to an Arrow decimal array handle, whose tag is its
# schema handle.
decimal_arrow_encode <- function(x) {
  type <- decimal_arrow_handle_type(x)
  .Call(
    decimal_c_arrow_encode,
    vctrs::vec_data(x),
    type$precision,
    type$scale,
    type$bits
  )
}

# zuarrow handlers ---------------------------------------------------------

decimal_zuarrow_to <- function(array, schema) {
  decimal_arrow_decode(array, schema)
}

decimal_zuarrow_from <- function(x) {
  decimal_arrow_encode(x)
}

# Registration -------------------------------------------------------------

decimal_register_zuarrow_now <- function() {
  # Registering a key again replaces it with a message naming both packages.
  # A reload of this package replaces its own registrations, quietly.
  registry <- zuarrow::arrow_registry()
  ours <- registry$key[registry$package %in% "decimal"]
  for (key in intersect(ours, decimal_zuarrow_keys)) {
    zuarrow::arrow_unregister(key)
  }
  zuarrow::arrow_register(
    "d:*",
    to = decimal_zuarrow_to,
    from = decimal_zuarrow_from,
    class = "decimal",
    package = "decimal"
  )
  zuarrow::arrow_register(
    "r.decimal",
    to = decimal_zuarrow_to,
    package = "decimal"
  )
  invisible()
}

# Called from `.onLoad()`. zuarrow is suggested: it may load later, or never.
# Its registry lives in its namespace, so a fresh load of zuarrow needs the
# registration again; the hook gives it that.
decimal_register_zuarrow <- function() {
  # One hook, even after this package reloads: drop the one an earlier load
  # set, whose functions belong to the old namespace.
  event <- packageEvent("zuarrow", "onLoad")
  hooks <- Filter(\(f) !isTRUE(attr(f, "decimal")), getHook(event))
  hook <- function(...) {
    if (isNamespaceLoaded("decimal")) {
      decimal_register_zuarrow_safely()
    }
  }
  attr(hook, "decimal") <- TRUE
  setHook(event, c(hooks, hook), "replace")
  if (isNamespaceLoaded("zuarrow")) {
    decimal_register_zuarrow_safely()
  }
  invisible()
}

# A zuarrow without the registry, or one that refuses the registration, must
# not stop either package from loading.
decimal_register_zuarrow_safely <- function() {
  tryCatch(
    decimal_register_zuarrow_now(),
    error = function(e) {
      warning(
        "decimal could not register with zuarrow: ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )
  invisible()
}
