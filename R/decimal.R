new_decimal <- function(x = character(), validate = FALSE) {
  if (!is.character(x)) {
    rlang::abort("`x` must be a character vector.")
  }

  if (validate) {
    x <- .decimal_canonicalize_strings(x)
  }

  vctrs::new_vctr(x, class = "decimal")
}

decimal_abort_unsupported <- function(x, arg = "x") {
  rlang::abort(
    paste0(
      "`", arg, "` must be a decimal, character, integer, or double vector, ",
      "not ", paste(class(x), collapse = "/"), "."
    )
  )
}

decimal_warn_lossy <- function(lossy, to) {
  if (any(lossy)) {
    warning(
      paste0("Lossy conversion from `decimal` to `", to, "`."),
      call. = FALSE
    )
  }
}

decimal_lossy_double <- function(x, out) {
  values <- vctrs::vec_data(x)
  roundtrip <- .decimal_from_double_strings(out)
  !is.na(values) & (is.na(roundtrip) | roundtrip != values)
}

decimal_lossy_integer <- function(x, out) {
  values <- vctrs::vec_data(x)
  roundtrip <- rep_len(NA_character_, length(out))
  non_missing <- !is.na(out)
  roundtrip[non_missing] <- as.character(out[non_missing])
  !is.na(values) & (is.na(roundtrip) | roundtrip != values)
}

decimal_scalar_digits <- function(x, arg = "digits", min = NULL) {
  if (!rlang::is_integerish(x, n = 1, finite = TRUE) || is.na(x)) {
    rlang::abort(paste0("`", arg, "` must be a finite integer scalar."))
  }

  x <- as.integer(x)

  if (!is.null(min) && x < min) {
    rlang::abort(paste0("`", arg, "` must be >= ", min, "."))
  }

  x
}

decimal_is_integerish_numeric <- function(x) {
  is.numeric(x) && !is.object(x) && typeof(x) == "integer"
}

decimal_arith_input <- function(x, arg) {
  if (is_decimal(x)) {
    return(x)
  }

  if (decimal_is_integerish_numeric(x)) {
    return(as_decimal.integer(x))
  }

  rlang::abort(
    paste0(
      "Decimal arithmetic requires decimal or integer vectors, not `",
      paste(class(x), collapse = "/"),
      "`."
    )
  )
}

decimal_compare_input <- function(x, arg) {
  if (is_decimal(x)) {
    return(x)
  }

  if (decimal_is_integerish_numeric(x)) {
    return(as_decimal.integer(x))
  }

  rlang::abort(
    paste0(
      "Decimal comparison requires decimal or integer vectors, not `",
      paste(class(x), collapse = "/"),
      "`."
    )
  )
}

decimal_new_result <- function(x) {
  new_decimal(x)
}

decimal_binary_arith <- function(op, x, y) {
  args <- vctrs::vec_recycle_common(
    decimal_arith_input(x, "x"),
    decimal_arith_input(y, "y")
  )

  decimal_new_result(
    .decimal_binary_op_strings(vctrs::vec_data(args[[1]]), vctrs::vec_data(args[[2]]), op)
  )
}

decimal_unary_arith <- function(op, x) {
  x <- decimal_arith_input(x, "x")
  decimal_new_result(.decimal_unary_op_strings(vctrs::vec_data(x), op))
}

decimal_compare <- function(op, x, y) {
  args <- vctrs::vec_recycle_common(
    decimal_compare_input(x, "x"),
    decimal_compare_input(y, "y")
  )

  .decimal_compare_strings(vctrs::vec_data(args[[1]]), vctrs::vec_data(args[[2]]), op)
}

decimal_math_input <- function(x, arg = "x") {
  if (is_decimal(x)) {
    return(x)
  }

  if (decimal_is_integerish_numeric(x)) {
    return(as_decimal.integer(x))
  }

  if (is.character(x) || is.double(x)) {
    return(as_decimal(x))
  }

  decimal_abort_unsupported(x, arg = arg)
}

decimal_unary_math <- function(x, op) {
  x <- decimal_math_input(x)
  decimal_new_result(.decimal_math_op_strings(vctrs::vec_data(x), op))
}

decimal_quantum_string <- function(exponent) {
  ifelse(exponent >= 0L,
         paste0("1E+", exponent),
         paste0("1E", exponent))
}

decimal_quantize <- function(x, quantum) {
  args <- vctrs::vec_recycle_common(decimal_math_input(x, "x"),
                                    decimal_math_input(quantum, "quantum"))
  decimal_new_result(
    .decimal_quantize_strings(vctrs::vec_data(args[[1]]), vctrs::vec_data(args[[2]]))
  )
}

decimal_summary_prepare <- function(..., na.rm = FALSE, mode = c("arith", "compare")) {
  mode <- match.arg(mode)
  xs <- list(...)
  if (length(xs) == 1L && is.list(xs[[1L]]) && !is_decimal(xs[[1L]])) {
    xs <- xs[[1L]]
  }

  cast <- if (mode == "arith") decimal_arith_input else decimal_compare_input
  xs <- lapply(xs, cast, arg = "x")
  x <- do.call(vctrs::vec_c, xs)
  classes <- number_class(x)

  if (na.rm) {
    x <- x[!is.na(x)]
    return(list(kind = "values", x = x))
  }

  if (any(is.na(vctrs::vec_data(x)))) {
    return(list(kind = "na"))
  }

  if (any(classes == "sNaN", na.rm = TRUE)) {
    return(list(kind = "snan"))
  }

  if (any(classes == "NaN", na.rm = TRUE)) {
    return(list(kind = "qnan"))
  }

  list(kind = "values", x = x)
}

decimal_reduce <- function(x, op) {
  acc <- x[1L]

  if (length(x) == 1L) {
    return(acc)
  }

  for (i in 2:length(x)) {
    acc <- switch(
      op,
      "+" = acc + x[i],
      "*" = acc * x[i],
      stop("Unsupported reduction operation.", call. = FALSE)
    )
  }

  acc
}

decimal_extrema <- function(..., na.rm = FALSE, which = c("min", "max")) {
  which <- match.arg(which)
  prep <- decimal_summary_prepare(..., na.rm = na.rm, mode = "compare")

  if (prep$kind == "na") {
    return(NA_decimal_)
  }
  if (prep$kind == "snan") {
    return(decimal_unary_math(decimal("sNaN"), "abs"))
  }
  if (prep$kind == "qnan") {
    return(decimal("NaN"))
  }
  if (length(prep$x) == 0L) {
    if (which == "min") {
      warning("no non-missing arguments to min; returning Inf", call. = FALSE)
      return(decimal("Infinity"))
    }

    warning("no non-missing arguments to max; returning -Inf", call. = FALSE)
    return(decimal("-Infinity"))
  }

  sorted <- sort(prep$x)
  if (which == "min") sorted[1L] else sorted[length(sorted)]
}

#' Construct decimal vectors
#'
#' `decimal()` creates an immutable decimal vector backed by exact strings.
#' Character and integer inputs are converted exactly. Double inputs use the
#' exact IEEE 754 binary value, matching the intent of Python's
#' `Decimal.from_float()`.
#'
#' @param x A decimal, character, integer, or double vector.
#'
#' @return A `decimal` vector.
#' @examples
#' decimal(c("1.20", "2.30"))
#' decimal(1:3)
#' is_decimal(decimal("1.5"))
#' as_decimal("0.1")
#' @export
decimal <- function(x = character()) {
  as_decimal(x)
}

#' @rdname decimal
#' @export
is_decimal <- function(x) {
  inherits(x, "decimal")
}

#' @rdname decimal
#' @export
as_decimal <- function(x) {
  UseMethod("as_decimal")
}

#' @rdname decimal
#' @export
as_decimal.decimal <- function(x) {
  x
}

#' @rdname decimal
#' @export
as_decimal.character <- function(x) {
  new_decimal(x, validate = TRUE)
}

#' @rdname decimal
#' @export
as_decimal.integer <- function(x) {
  new_decimal(as.character(x))
}

#' @rdname decimal
#' @export
as_decimal.numeric <- function(x) {
  decimal_from_double(x)
}

#' @rdname decimal
#' @export
as_decimal.default <- function(x) {
  decimal_abort_unsupported(x)
}

#' Exact conversion from double
#'
#' Converts each IEEE 754 double to its exact decimal value. This differs from
#' parsing a character literal such as `"0.1"`.
#'
#' @param x A double vector.
#'
#' @return A `decimal` vector.
#' @examples
#' decimal_from_double(0.1)
#' decimal_from_double(c(0.5, 0.25))
#' @export
decimal_from_double <- function(x) {
  if (!is.double(x)) {
    rlang::abort("`x` must be a double vector.")
  }

  new_decimal(.decimal_from_double_strings(x))
}

#' Missing decimal scalar
#'
#' A length-one missing decimal value.
#'
#' @format A length-one `decimal` vector.
#' @rdname decimal
#' @export
NA_decimal_ <- new_decimal(NA_character_)

#' @export
format.decimal <- function(x, ..., engineering = FALSE) {
  values <- vctrs::vec_data(x)

  if (isTRUE(engineering)) {
    .decimal_format_strings(values, style = "eng")
  } else {
    values
  }
}

#' @export
as.character.decimal <- function(x, ...) {
  vctrs::vec_data(x)
}

#' @export
as.double.decimal <- function(x, ...) {
  out <- .decimal_to_double_strings(vctrs::vec_data(x))
  decimal_warn_lossy(decimal_lossy_double(x, out), "double")
  out
}

#' @export
as.integer.decimal <- function(x, ...) {
  out <- .decimal_to_integer_strings(vctrs::vec_data(x))
  decimal_warn_lossy(decimal_lossy_integer(x, out), "integer")
  out
}

#' @export
vec_ptype_abbr.decimal <- function(x, ...) {
  "dec"
}

#' @export
vec_ptype_full.decimal <- function(x, ...) {
  "decimal"
}

#' @export
vec_ptype2.decimal.decimal <- function(x, y, ...) {
  new_decimal()
}

#' @export
vec_ptype2.decimal.integer <- function(x, y, ...) {
  new_decimal()
}

#' @export
vec_ptype2.integer.decimal <- function(x, y, ...) {
  new_decimal()
}

#' @export
vec_ptype2.decimal.default <- function(x, y, ..., x_arg = "", y_arg = "") {
  vctrs::vec_default_ptype2(x, y, ..., x_arg = x_arg, y_arg = y_arg)
}

#' @export
vec_ptype2.default.decimal <- function(x, y, ..., x_arg = "", y_arg = "") {
  vctrs::vec_default_ptype2(x, y, ..., x_arg = x_arg, y_arg = y_arg)
}

#' @export
vec_cast.decimal.decimal <- function(x, to, ...) {
  x
}

#' @export
vec_cast.decimal.character <- function(x, to, ...) {
  as_decimal.character(x)
}

#' @export
vec_cast.decimal.integer <- function(x, to, ...) {
  as_decimal.integer(x)
}

#' @export
vec_cast.decimal.double <- function(x, to, ...) {
  decimal_from_double(x)
}

#' @export
vec_cast.decimal.default <- function(x, to, ..., x_arg = "", to_arg = "") {
  vctrs::vec_default_cast(x, to, ..., x_arg = x_arg, to_arg = to_arg)
}

#' @export
vec_cast.character.decimal <- function(x, to, ...) {
  as.character(x)
}

#' @export
vec_cast.double.decimal <- function(x, to, ..., x_arg = "", to_arg = "") {
  out <- .decimal_to_double_strings(vctrs::vec_data(x))
  lossy <- decimal_lossy_double(x, out)

  vctrs::maybe_lossy_cast(
    out,
    x,
    to,
    lossy = lossy,
    x_arg = x_arg,
    to_arg = to_arg
  )
}

#' @export
vec_cast.integer.decimal <- function(x, to, ..., x_arg = "", to_arg = "") {
  out <- .decimal_to_integer_strings(vctrs::vec_data(x))
  lossy <- decimal_lossy_integer(x, out)

  vctrs::maybe_lossy_cast(
    out,
    x,
    to,
    lossy = lossy,
    x_arg = x_arg,
    to_arg = to_arg
  )
}

#' @export
vec_cast.default.decimal <- function(x, to, ..., x_arg = "", to_arg = "") {
  vctrs::vec_default_cast(x, to, ..., x_arg = x_arg, to_arg = to_arg)
}

#' @exportS3Method pillar::pillar_shaft
pillar_shaft.decimal <- function(x, ...) {
  pillar::new_pillar_shaft_simple(format(x), align = "right")
}

#' @export
Ops.decimal <- function(e1, e2) {
  op <- .Generic

  if (op %in% c("==", "!=", "<", "<=", ">", ">=")) {
    return(decimal_compare(op, e1, e2))
  }

  if (missing(e2)) {
    return(vctrs::vec_arith(op, e1, vctrs::MISSING()))
  }

  vctrs::vec_arith(op, e1, e2)
}

#' Arithmetic for decimal vectors
#'
#' Implements the \pkg{vctrs} arithmetic group generic ([vctrs::vec_arith()])
#' for decimal vectors. It is not normally called directly; it dispatches when
#' decimals are combined with operators such as `+`, `-`, `*`, and `/`.
#'
#' @param op A length-one character vector giving the arithmetic operator.
#' @param x,y A pair of vectors, at least one of which is a `decimal`.
#' @param ... Passed on to methods.
#'
#' @return A `decimal` vector with the result of the operation.
#' @examples
#' decimal("1.5") + decimal("2.5")
#' decimal(c("10", "20")) * 3L
#' @keywords internal
#' @method vec_arith decimal
#' @export
vec_arith.decimal <- function(op, x, y, ...) {
  UseMethod("vec_arith.decimal", y)
}

#' @export
vec_arith.decimal.decimal <- function(op, x, y, ...) {
  decimal_binary_arith(op, x, y)
}

#' @export
vec_arith.decimal.numeric <- function(op, x, y, ...) {
  if (!decimal_is_integerish_numeric(y)) {
    vctrs::stop_incompatible_op(op, x, y)
  }

  decimal_binary_arith(op, x, y)
}

#' @export
vec_arith.decimal.MISSING <- function(op, x, y, ...) {
  if (!op %in% c("+", "-")) {
    vctrs::stop_incompatible_op(op, x, y)
  }

  decimal_unary_arith(op, x)
}

#' @export
vec_arith.decimal.default <- function(op, x, y, ...) {
  vctrs::stop_incompatible_op(op, x, y)
}

#' @export
vec_arith.numeric.decimal <- function(op, x, y, ...) {
  if (!decimal_is_integerish_numeric(x)) {
    vctrs::stop_incompatible_op(op, x, y)
  }

  decimal_binary_arith(op, x, y)
}

#' @export
vec_proxy_equal.decimal <- function(x, ...) {
  .decimal_equal_proxy_strings(vctrs::vec_data(x))
}

#' @export
vec_proxy_compare.decimal <- function(x, ...) {
  .decimal_order_proxy_strings(vctrs::vec_data(x))
}

#' @export
vec_proxy_order.decimal <- function(x, ...) {
  .decimal_order_proxy_strings(vctrs::vec_data(x))
}

#' @export
vec_math.decimal <- function(.fn, .x, ...) {
  dots <- list(...)
  na_rm <- if ("na.rm" %in% names(dots)) dots$na.rm else FALSE

  switch(
    .fn,
    abs = decimal_unary_math(.x, "abs"),
    sign = decimal_unary_math(.x, "sign"),
    sqrt = decimal_unary_math(.x, "sqrt"),
    floor = decimal_unary_math(.x, "floor"),
    ceiling = decimal_unary_math(.x, "ceiling"),
    trunc = decimal_unary_math(.x, "trunc"),
    exp = decimal_unary_math(.x, "exp"),
    log10 = decimal_unary_math(.x, "log10"),
    log = log.decimal(.x, ...),
    sum = {
      prep <- decimal_summary_prepare(.x, na.rm = na_rm, mode = "arith")
      if (prep$kind == "na") {
        NA_decimal_
      } else if (prep$kind == "snan") {
        decimal_unary_math(decimal("sNaN"), "abs")
      } else if (prep$kind == "qnan") {
        decimal("NaN")
      } else if (length(prep$x) == 0L) {
        decimal("0")
      } else {
        decimal_reduce(prep$x, "+")
      }
    },
    prod = {
      prep <- decimal_summary_prepare(.x, na.rm = na_rm, mode = "arith")
      if (prep$kind == "na") {
        NA_decimal_
      } else if (prep$kind == "snan") {
        decimal_unary_math(decimal("sNaN"), "abs")
      } else if (prep$kind == "qnan") {
        decimal("NaN")
      } else if (length(prep$x) == 0L) {
        decimal("1")
      } else {
        decimal_reduce(prep$x, "*")
      }
    },
    min = {
      decimal_extrema(.x, na.rm = na_rm, which = "min")
    },
    max = {
      decimal_extrema(.x, na.rm = na_rm, which = "max")
    },
    mean = {
      prep <- decimal_summary_prepare(.x, na.rm = na_rm, mode = "arith")
      if (prep$kind == "na") {
        NA_decimal_
      } else if (prep$kind == "snan") {
        decimal_unary_math(decimal("sNaN"), "abs")
      } else if (prep$kind == "qnan") {
        decimal("NaN")
      } else if (length(prep$x) == 0L) {
        decimal("NaN")
      } else {
        decimal_reduce(prep$x, "+") / as.integer(length(prep$x))
      }
    },
    stop(sprintf("`%s()` is not implemented for decimal vectors.", .fn), call. = FALSE)
  )
}

#' @export
Summary.decimal <- function(..., na.rm = FALSE) {
  switch(
    .Generic,
    sum = vec_math.decimal("sum", do.call(vctrs::vec_c, lapply(list(...), decimal_arith_input, arg = "x")), na.rm = na.rm),
    prod = vec_math.decimal("prod", do.call(vctrs::vec_c, lapply(list(...), decimal_arith_input, arg = "x")), na.rm = na.rm),
    min = decimal_extrema(list(...), na.rm = na.rm, which = "min"),
    max = decimal_extrema(list(...), na.rm = na.rm, which = "max"),
    stop(sprintf("`%s()` is not implemented for decimal vectors.", .Generic), call. = FALSE)
  )
}

#' @export
log.decimal <- function(x, base = exp(1)) {
  out <- decimal_unary_math(x, "log")

  if (missing(base) || (is.double(base) && length(base) == 1L && identical(base, exp(1)))) {
    return(out)
  }

  out / log(decimal_math_input(base, "base"))
}

#' @export
round.decimal <- function(x, digits = 0) {
  digits <- decimal_scalar_digits(digits)
  quantum <- decimal(decimal_quantum_string(-digits))
  decimal_quantize(x, quantum)
}

#' @export
signif.decimal <- function(x, digits = 6) {
  digits <- decimal_scalar_digits(digits, min = 1L)
  x <- decimal_math_input(x)
  adj <- adjusted(x)
  exponents <- ifelse(is.na(adj), NA_integer_, adj - digits + 1L)
  quantum <- new_decimal(ifelse(is.na(exponents), NA_character_, decimal_quantum_string(exponents)))
  decimal_quantize(x, quantum)
}

#' Decimal predicates and classification
#'
#' @param x A decimal-compatible vector.
#'
#' @return A logical vector for predicates, an integer vector for `adjusted()`,
#'   or a character vector for `number_class()`.
#' @examples
#' x <- decimal(c("1.0", "NaN", "Infinity", "0"))
#' is_qnan(x)
#' is_zero(x)
#' number_class(x)
#' adjusted(decimal(c("123", "0.01")))
#' @export
is_qnan <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "qnan")
}

#' @rdname is_qnan
#' @export
is_snan <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "snan")
}

#' @rdname is_qnan
#' @export
is_normal <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "normal")
}

#' @rdname is_qnan
#' @export
is_subnormal <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "subnormal")
}

#' @rdname is_qnan
#' @export
is_signed <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "signed")
}

#' @rdname is_qnan
#' @export
is_zero <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "zero")
}

#' @rdname is_qnan
#' @export
number_class <- function(x) {
  .decimal_classify_strings(vctrs::vec_data(decimal_math_input(x)))
}

#' @rdname is_qnan
#' @export
adjusted <- function(x) {
  .decimal_adjusted_strings(vctrs::vec_data(decimal_math_input(x)))
}

#' Decimal-specific operations
#'
#' @param x,y,z,quantum Decimal-compatible vectors.
#'
#' @return A decimal vector, except `same_quantum()` which returns a logical
#'   vector.
#' @examples
#' quantize(decimal("1.23456"), decimal("0.01"))
#' normalize(decimal("1.2300"))
#' fma(decimal("2"), decimal("3"), decimal("4"))
#' same_quantum(decimal("1.00"), decimal("2.00"))
#' @export
quantize <- function(x, quantum) {
  decimal_quantize(x, quantum)
}

#' @rdname quantize
#' @export
normalize <- function(x) {
  decimal_unary_math(x, "normalize")
}

#' @rdname quantize
#' @export
fma <- function(x, y, z) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(x, "x"),
    decimal_math_input(y, "y"),
    decimal_math_input(z, "z")
  )

  decimal_new_result(
    .decimal_fma_strings(vctrs::vec_data(args[[1]]), vctrs::vec_data(args[[2]]), vctrs::vec_data(args[[3]]))
  )
}

#' @rdname quantize
#' @export
same_quantum <- function(x, y) {
  args <- vctrs::vec_recycle_common(decimal_math_input(x, "x"),
                                    decimal_math_input(y, "y"))
  .decimal_same_quantum_strings(vctrs::vec_data(args[[1]]), vctrs::vec_data(args[[2]]))
}

#' @export
range.decimal <- function(x, ..., na.rm = FALSE, finite = FALSE) {
  if (isTRUE(finite)) {
    rlang::abort("`finite = TRUE` is not implemented for decimal vectors.")
  }

  prep <- decimal_summary_prepare(c(list(x), list(...)), na.rm = na.rm, mode = "compare")
  if (prep$kind == "na") {
    return(c(NA_decimal_, NA_decimal_))
  }
  if (prep$kind == "snan") {
    value <- decimal_unary_math(decimal("sNaN"), "abs")
    return(c(value, value))
  }
  if (prep$kind == "qnan") {
    value <- decimal("NaN")
    return(c(value, value))
  }
  if (length(prep$x) == 0L) {
    warning("no non-missing arguments to min; returning Inf", call. = FALSE)
    return(decimal(c("Infinity", "-Infinity")))
  }

  sorted <- sort(prep$x)
  c(sorted[1L], sorted[length(sorted)])
}

#' @export
min.decimal <- function(x, ..., na.rm = FALSE) {
  decimal_extrema(c(list(x), list(...)), na.rm = na.rm, which = "min")
}

#' @export
max.decimal <- function(x, ..., na.rm = FALSE) {
  decimal_extrema(c(list(x), list(...)), na.rm = na.rm, which = "max")
}

#' @export
is.na.decimal <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(x), "na")
}

#' @export
is.nan.decimal <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(x), "nan")
}

#' @export
is.finite.decimal <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(x), "finite")
}

#' @export
is.infinite.decimal <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(x), "infinite")
}
