new_decimal <- function(x = character(), scale = 0L, validate = FALSE) {
  if (!is.character(x)) {
    rlang::abort("`x` must be a character vector.")
  }

  if (validate) {
    x <- .decimal_canonicalize_strings(x)
  }

  vctrs::new_vctr(x, scale = as.integer(scale), class = "decimal")
}

decimal_scale <- function(x) {
  scale <- attr(x, "scale")
  if (is.null(scale)) 0L else scale
}

decimal_resolve_scale <- function(scale) {
  if (!is.null(scale)) {
    return(decimal_scalar_integer(scale, "scale"))
  }

  default <- getOption("decimal.default_scale")
  if (is.null(default)) {
    return(NULL)
  }

  decimal_scalar_integer(default, "decimal.default_scale")
}

# Fractional digits implied by each canonical (already-validated) decimal
# string: `coefficient digits after the point - exponent`. NA for elements
# that are NA, infinities, or NaNs (they carry no fractional-digit count).
decimal_string_scale <- function(x) {
  m <- regmatches(
    x,
    regexec("^-?([0-9]+)(?:\\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$", x)
  )

  vapply(
    m,
    function(g) {
      if (length(g) == 0L) {
        return(NA_integer_)
      }
      frac <- if (nzchar(g[3])) nchar(g[3]) else 0L
      expo <- if (nzchar(g[4])) as.integer(g[4]) else 0L
      frac - expo
    },
    integer(1)
  )
}

decimal_infer_scale <- function(x) {
  digits <- decimal_string_scale(x)
  if (all(is.na(digits))) 0L else max(digits, na.rm = TRUE)
}

# Rescale canonical decimal strings to a shared vector scale (fractional
# digit count; may be negative, meaning rounding into the integer part).
#
# NA, infinities, and NaNs pass through unchanged: GDA quantize treats a
# finite quantum against an infinite operand as invalid, which would
# otherwise trap on values that have no scale to begin with.
#
# Elements already at `scale` are left untouched rather than round-tripped
# through native quantize: construction must stay exact and independent of
# the active context, and quantize is a context-precision-consuming
# operation. Only elements that actually need rescaling touch the native
# kernel.
decimal_rescale_strings <- function(values, scale) {
  current <- decimal_string_scale(values)
  needs_rescale <- !is.na(current) & current != scale
  if (!any(needs_rescale)) {
    return(values)
  }

  out <- values
  quantum <- rep_len(decimal_quantum_string(-scale), sum(needs_rescale))
  out[needs_rescale] <- .decimal_quantize_strings(
    values[needs_rescale],
    quantum
  )
  out
}

decimal_set_scale <- function(x, scale) {
  scale <- decimal_scalar_integer(scale, "scale")
  if (identical(decimal_scale(x), scale)) {
    return(x)
  }
  new_decimal(decimal_rescale_strings(vctrs::vec_data(x), scale), scale = scale)
}

decimal_abort_unsupported <- function(x, arg = "x") {
  rlang::abort(
    paste0(
      "`",
      arg,
      "` must be a decimal, character, integer, or double vector, ",
      "not ",
      paste(class(x), collapse = "/"),
      "."
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
  # Exact string comparison is intentional, not just numeric: a stored
  # trailing zero (including one introduced by fixed-vector-scale padding,
  # e.g. "-0" padded to "-0.0" alongside "1.5") is declared significance that
  # a plain double cannot represent, so it counts as a lossy cast even when
  # the numeric values match ("1.0" vs "1", "-0.0" vs "-0").
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

decimal_new_result <- function(x, scale) {
  new_decimal(decimal_rescale_strings(x, scale), scale = scale)
}

decimal_binary_arith <- function(op, x, y) {
  # The result's scale is always inferred from what mpdecimal actually
  # computed, never forced to a precomputed "ideal" target (e.g. max(sx, sy)
  # for +/-, sx + sy for *). Under sufficient precision the two coincide, by
  # the General Decimal Arithmetic ideal-exponent rules. But when precision
  # forces early rounding, the raw result is coarser than the ideal target,
  # and forcibly padding it back up both overstates the precision actually
  # computed and can itself exceed the context's precision (observed as a
  # spurious `invalid_operation` on ordinary context-constrained rounding,
  # e.g. `decimal("1.25") + decimal("0")` under `precision = 2`).
  args <- vctrs::vec_recycle_common(
    decimal_arith_input(x, "x"),
    decimal_arith_input(y, "y")
  )
  raw <- .decimal_binary_op_strings(
    vctrs::vec_data(args[[1]]),
    vctrs::vec_data(args[[2]]),
    op
  )
  decimal_new_result(raw, decimal_infer_scale(raw))
}

decimal_unary_arith <- function(op, x) {
  x <- decimal_arith_input(x, "x")
  decimal_new_result(
    .decimal_unary_op_strings(vctrs::vec_data(x), op),
    decimal_scale(x)
  )
}

decimal_compare <- function(op, x, y) {
  args <- vctrs::vec_recycle_common(
    decimal_compare_input(x, "x"),
    decimal_compare_input(y, "y")
  )

  .decimal_compare_strings(
    vctrs::vec_data(args[[1]]),
    vctrs::vec_data(args[[2]]),
    op
  )
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

decimal_unary_math <- function(x, op, scale = NULL) {
  x <- decimal_math_input(x)
  raw <- .decimal_math_op_strings(vctrs::vec_data(x), op)
  # For exact ops (abs, ...) the raw result already has the same number of
  # fractional digits as `x`. For ops with no exact terminating scale (sqrt,
  # exp, log, log10), mpdecimal computes to the active context's precision,
  # so inferring the target from what it actually produced preserves that
  # precision instead of collapsing to `x`'s (often much coarser) scale.
  target <- if (is.null(scale)) decimal_infer_scale(raw) else scale
  decimal_new_result(raw, target)
}

decimal_quantum_string <- function(exponent) {
  ifelse(exponent >= 0L, paste0("1E+", exponent), paste0("1E", exponent))
}

decimal_quantize <- function(x, quantum) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(x, "x"),
    decimal_math_input(quantum, "quantum")
  )
  dx <- args[[1]]
  dq <- args[[2]]

  new_decimal(
    .decimal_quantize_strings(vctrs::vec_data(dx), vctrs::vec_data(dq)),
    scale = decimal_scale(dq)
  )
}

decimal_summary_prepare <- function(
  ...,
  na.rm = FALSE,
  mode = c("arith", "compare")
) {
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
#' `decimal()` creates an immutable decimal vector backed by exact strings, at
#' a single shared scale (number of fractional digits) for the whole vector.
#' Character and integer inputs are converted exactly. Double inputs use the
#' exact IEEE 754 binary value and require either an explicit `scale` or the
#' `decimal.default_scale` option.
#'
#' When `scale` is `NULL`, `getOption("decimal.default_scale")` is used when
#' set. Otherwise, character input infers the largest number of fractional
#' digits present in `x`, and integer input uses scale zero. Because scale is
#' a property of the vector, not the element, `decimal("1.2") ==
#' decimal("1.20")`, and combining them yields one uniformly scaled vector.
#'
#' @param x A decimal, character, integer, or double vector.
#' @param scale An integer scalar giving the number of fractional digits to
#'   store. `NULL` uses the `decimal.default_scale` option when set, then
#'   falls back to input-specific inference. Negative values round into the
#'   integer part (e.g. `scale = -2` rounds to the nearest hundred).
#'
#' @return A `decimal` vector.
#' @examples
#' decimal(c("1.20", "2.30"))
#' @export
decimal <- function(x = character(), scale = NULL) {
  as_decimal(x, scale = scale)
}

#' Test whether an object is a decimal vector
#'
#' `is_decimal()` reports whether `x` inherits from the `decimal` vector
#' class. It does not attempt to parse or convert other objects.
#'
#' @param x An object to test.
#'
#' @return A single logical value.
#' @examples
#' is_decimal(decimal("1.5"))
#' @export
is_decimal <- function(x) {
  inherits(x, "decimal")
}

#' Convert a vector to decimal
#'
#' `as_decimal()` is the conversion generic for decimal vectors. Character
#' values are parsed exactly, integer values are converted exactly, and
#' existing decimal vectors are returned or rescaled. Double values are
#' converted from their exact IEEE 754 representation and therefore require
#' an explicit or globally configured scale.
#'
#' When `scale` is `NULL`, `getOption("decimal.default_scale")` is used when
#' set. Without that option, character input uses the largest number of
#' fractional digits found in the input, integer input uses scale zero, and
#' double input raises an error. Quantization uses the active
#' [decimal_context()].
#'
#' @param x A decimal, character, integer, or double vector.
#' @param scale An integer scalar giving the number of fractional digits to
#'   store, or `NULL` to use the global default or input-specific inference.
#'
#' @return A `decimal` vector.
#' @examples
#' as_decimal(c("1.2", "3.45"))
#' @export
as_decimal <- function(x, scale = NULL) {
  UseMethod("as_decimal")
}

#' @rdname as_decimal
#' @export
as_decimal.decimal <- function(x, scale = NULL) {
  scale <- decimal_resolve_scale(scale)
  if (is.null(scale)) {
    return(x)
  }
  decimal_set_scale(x, scale)
}

#' @rdname as_decimal
#' @export
as_decimal.character <- function(x, scale = NULL) {
  canon <- .decimal_canonicalize_strings(x)
  scale <- decimal_resolve_scale(scale)
  scale <- if (is.null(scale)) {
    decimal_infer_scale(canon)
  } else {
    scale
  }
  new_decimal(decimal_rescale_strings(canon, scale), scale = scale)
}

#' @rdname as_decimal
#' @export
as_decimal.integer <- function(x, scale = NULL) {
  scale <- decimal_resolve_scale(scale)
  scale <- if (is.null(scale)) 0L else scale
  new_decimal(decimal_rescale_strings(as.character(x), scale), scale = scale)
}

#' @rdname as_decimal
#' @export
as_decimal.numeric <- function(x, scale = NULL) {
  decimal_from_double(x, scale = scale)
}

#' @rdname as_decimal
#' @export
as_decimal.default <- function(x, scale = NULL) {
  decimal_abort_unsupported(x)
}

#' Exact conversion from double
#'
#' Converts each IEEE 754 double to its exact decimal value. This differs from
#' parsing a character literal such as `"0.1"`. Because the exact binary value
#' of a double can require dozens of fractional digits, a scale must be given
#' explicitly or configured with `options(decimal.default_scale = )`. The
#' result is quantized to that scale using the active context's rounding and
#' trap settings.
#'
#' @param x A double vector.
#' @param scale An integer scalar giving the number of fractional digits to
#'   store, or `NULL` to use `getOption("decimal.default_scale")`.
#'
#' @return A `decimal` vector.
#' @examples
#' decimal_from_double(0.1, scale = 20)
#' decimal_from_double(c(0.5, 0.25), scale = 2)
#' @export
decimal_from_double <- function(x, scale = NULL) {
  if (!is.double(x)) {
    rlang::abort("`x` must be a double vector.")
  }
  scale <- decimal_resolve_scale(scale)
  if (is.null(scale)) {
    rlang::abort(
      paste0(
        "`scale` must be provided for exact double conversion, or set ",
        "`options(decimal.default_scale = )`."
      )
    )
  }

  new_decimal(
    decimal_rescale_strings(.decimal_from_double_strings(x), scale),
    scale = scale
  )
}

#' Missing decimal scalar
#'
#' A length-one missing decimal value.
#'
#' @format A length-one `decimal` vector.
#' @examples
#' c(decimal("1"), NA_decimal_)
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
  new_decimal(scale = max(decimal_scale(x), decimal_scale(y)))
}

#' @export
vec_ptype2.decimal.integer <- function(x, y, ...) {
  new_decimal(scale = decimal_scale(x))
}

#' @export
vec_ptype2.integer.decimal <- function(x, y, ...) {
  new_decimal(scale = decimal_scale(y))
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
  decimal_set_scale(x, decimal_scale(to))
}

#' @export
vec_cast.decimal.character <- function(x, to, ...) {
  as_decimal.character(x)
}

#' @export
vec_cast.decimal.integer <- function(x, to, ...) {
  as_decimal.integer(x, scale = decimal_scale(to))
}

#' @export
vec_cast.decimal.double <- function(x, to, ...) {
  rlang::abort(
    "Casting `double` to `decimal` requires an explicit scale; use `decimal_from_double(x, scale = )`."
  )
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
`==.decimal` <- function(e1, e2) {
  decimal_compare("==", e1, e2)
}

#' @export
`!=.decimal` <- function(e1, e2) {
  decimal_compare("!=", e1, e2)
}

#' @export
`<.decimal` <- function(e1, e2) {
  decimal_compare("<", e1, e2)
}

#' @export
`<=.decimal` <- function(e1, e2) {
  decimal_compare("<=", e1, e2)
}

#' @export
`>.decimal` <- function(e1, e2) {
  decimal_compare(">", e1, e2)
}

#' @export
`>=.decimal` <- function(e1, e2) {
  decimal_compare(">=", e1, e2)
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

#' @method vec_arith.decimal decimal
#' @export
vec_arith.decimal.decimal <- function(op, x, y, ...) {
  decimal_binary_arith(op, x, y)
}

#' @method vec_arith.decimal numeric
#' @export
vec_arith.decimal.numeric <- function(op, x, y, ...) {
  if (!decimal_is_integerish_numeric(y)) {
    vctrs::stop_incompatible_op(op, x, y)
  }

  decimal_binary_arith(op, x, y)
}

#' @method vec_arith.decimal MISSING
#' @export
vec_arith.decimal.MISSING <- function(op, x, y, ...) {
  if (!op %in% c("+", "-")) {
    vctrs::stop_incompatible_op(op, x, y)
  }

  decimal_unary_arith(op, x)
}

#' @method vec_arith.decimal default
#' @export
vec_arith.decimal.default <- function(op, x, y, ...) {
  vctrs::stop_incompatible_op(op, x, y)
}

#' @method vec_arith.numeric decimal
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
    sign = decimal_unary_math(.x, "sign", scale = 0L),
    sqrt = decimal_unary_math(.x, "sqrt"),
    floor = decimal_unary_math(.x, "floor", scale = 0L),
    ceiling = decimal_unary_math(.x, "ceiling", scale = 0L),
    trunc = decimal_unary_math(.x, "trunc", scale = 0L),
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
    stop(
      sprintf("`%s()` is not implemented for decimal vectors.", .fn),
      call. = FALSE
    )
  )
}

#' @export
Summary.decimal <- function(..., na.rm = FALSE) {
  switch(
    .Generic,
    sum = vec_math.decimal(
      "sum",
      do.call(vctrs::vec_c, lapply(list(...), decimal_arith_input, arg = "x")),
      na.rm = na.rm
    ),
    prod = vec_math.decimal(
      "prod",
      do.call(vctrs::vec_c, lapply(list(...), decimal_arith_input, arg = "x")),
      na.rm = na.rm
    ),
    min = decimal_extrema(list(...), na.rm = na.rm, which = "min"),
    max = decimal_extrema(list(...), na.rm = na.rm, which = "max"),
    stop(
      sprintf("`%s()` is not implemented for decimal vectors.", .Generic),
      call. = FALSE
    )
  )
}

#' @export
log.decimal <- function(x, base = exp(1)) {
  out <- decimal_unary_math(x, "log")

  if (
    missing(base) ||
      (is.double(base) && length(base) == 1L && identical(base, exp(1)))
  ) {
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
  quantum <- ifelse(
    is.na(exponents),
    NA_character_,
    decimal_quantum_string(exponents)
  )

  # `signif()` targets a per-element exponent (each element keeps `digits`
  # significant digits), which is incompatible with one shared vector scale.
  # Quantize per element first, then uniformly rescale to the coarsest scale
  # that keeps every element's requested precision.
  raw <- .decimal_quantize_strings(vctrs::vec_data(x), quantum)
  target_scale <- if (all(is.na(exponents))) {
    decimal_scale(x)
  } else {
    max(-exponents, na.rm = TRUE)
  }
  decimal_new_result(raw, target_scale)
}

#' Identify quiet NaN values
#'
#' `is_qnan()` identifies quiet not-a-number values. Signaling NaNs and R
#' missing values are not quiet NaNs.
#'
#' @param x A decimal-compatible vector.
#'
#' @return A logical vector with the same length as `x`.
#' @examples
#' is_qnan(decimal(c("NaN", "sNaN", "1")))
#' @export
is_qnan <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "qnan")
}

#' Identify signaling NaN values
#'
#' `is_snan()` identifies signaling not-a-number values without performing an
#' arithmetic operation or raising the `invalid_operation` signal.
#'
#' @param x A decimal-compatible vector.
#'
#' @return A logical vector with the same length as `x`.
#' @examples
#' is_snan(decimal(c("sNaN", "NaN", "1")))
#' @export
is_snan <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "snan")
}

#' Identify normal decimal values
#'
#' `is_normal()` reports whether each finite, nonzero value is normal under
#' the active decimal context. Normality depends on the context's exponent
#' limits and precision.
#'
#' @param x A decimal-compatible vector.
#'
#' @return A logical vector with the same length as `x`.
#' @examples
#' is_normal(decimal(c("1", "0", "Infinity")))
#' @export
is_normal <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "normal")
}

#' Identify subnormal decimal values
#'
#' `is_subnormal()` reports whether each finite, nonzero value is subnormal
#' under the active decimal context. A value can therefore be subnormal in one
#' context and normal in another.
#'
#' @param x A decimal-compatible vector.
#'
#' @return A logical vector with the same length as `x`.
#' @examples
#' x <- decimal("0.001")
#' with_decimal_context(
#'   decimal_context(precision = 3L, emin = -2L),
#'   is_subnormal(x)
#' )
#' @export
is_subnormal <- function(x) {
  .decimal_predicate_strings(
    vctrs::vec_data(decimal_math_input(x)),
    "subnormal"
  )
}

#' Identify values with a negative sign
#'
#' `is_signed()` inspects the stored sign bit rather than comparing with zero.
#' It therefore identifies negative zero as signed.
#'
#' @param x A decimal-compatible vector.
#'
#' @return A logical vector with the same length as `x`.
#' @examples
#' is_signed(decimal(c("-2", "2", "-0", "0")))
#' @export
is_signed <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "signed")
}

#' Identify decimal zeros
#'
#' `is_zero()` identifies both positive and negative zero, regardless of the
#' vector's scale.
#'
#' @param x A decimal-compatible vector.
#'
#' @return A logical vector with the same length as `x`.
#' @examples
#' is_zero(decimal(c("0.00", "-0", "1")))
#' @export
is_zero <- function(x) {
  .decimal_predicate_strings(vctrs::vec_data(decimal_math_input(x)), "zero")
}

#' Classify decimal values
#'
#' `number_class()` returns the General Decimal Arithmetic class of each
#' value. Possible finite classes include `"+Normal"`, `"-Normal"`,
#' `"+Subnormal"`, `"-Subnormal"`, `"+Zero"`, and `"-Zero"`; infinities and
#' NaNs have their corresponding class names. Normal and subnormal classes
#' depend on the active decimal context.
#'
#' @param x A decimal-compatible vector.
#'
#' @return A character vector with the same length as `x`. R missing values
#'   produce `NA_character_`.
#' @examples
#' number_class(decimal(c("1", "-0", "Infinity", "NaN")))
#' @export
number_class <- function(x) {
  .decimal_classify_strings(vctrs::vec_data(decimal_math_input(x)))
}

#' Compute the adjusted exponent
#'
#' `adjusted()` returns the position of the most significant digit after
#' accounting for the stored exponent. For a finite nonzero value, this is
#' equivalent to the base-10 order of magnitude. The representation of zero
#' retains its exponent, so differently scaled zeros can have different
#' adjusted exponents.
#'
#' @param x A decimal-compatible vector.
#'
#' @return An integer vector with the same length as `x`. Infinities, NaNs,
#'   and R missing values produce `NA_integer_`.
#' @examples
#' adjusted(decimal(c("123", "0.01")))
#' @export
adjusted <- function(x) {
  .decimal_adjusted_strings(vctrs::vec_data(decimal_math_input(x)))
}

#' Quantize decimal values to a scale
#'
#' `quantize()` rounds each value in `x` to the scale declared by `quantum`.
#' The operation uses the active context's rounding mode, updates sticky
#' flags, and raises any enabled traps. The arguments follow normal vctrs
#' recycling rules.
#'
#' Reducing the scale is the explicit purpose of `quantize()` (and of
#' `round()` and `signif()`, both implemented on top of it), so the `inexact`
#' and `rounded` signals this commonly raises are not reported as warnings
#' the way other operations' signals are (see [decimal_context()]); they
#' still accumulate as sticky flags.
#'
#' @param x A decimal-compatible vector to quantize.
#' @param quantum A decimal-compatible vector whose shared scale determines
#'   the result scale.
#'
#' @return A `decimal` vector with the shared scale of `quantum`.
#' @examples
#' quantize(decimal("1.23456"), decimal("0.01"))
#' @export
quantize <- function(x, quantum) {
  decimal_quantize(x, quantum)
}

#' Remove unnecessary trailing zeros
#'
#' `normalize()` reduces each finite value to its shortest equivalent decimal
#' representation, then chooses the finest scale required by any element so
#' the result remains a valid shared-scale decimal vector. Special values pass
#' through unchanged.
#'
#' @param x A decimal-compatible vector.
#'
#' @return A normalized `decimal` vector.
#' @examples
#' normalize(decimal(c("1.2300", "1.2")))
#' @export
normalize <- function(x) {
  # Strip each element down to its own minimal (trailing-zero-free) exponent,
  # then uniformly rescale the vector to the finest scale actually needed, so
  # the shared-scale invariant holds without discarding any element's
  # significance.
  x <- decimal_math_input(x)
  reduced <- .decimal_math_op_strings(vctrs::vec_data(x), "normalize")
  decimal_new_result(reduced, decimal_infer_scale(reduced))
}

#' Fused multiply-add
#'
#' `fma()` computes `x * y + z` with a single final rounding step. This can be
#' more accurate than evaluating multiplication and addition separately under
#' a limited-precision context. The arguments follow normal vctrs recycling
#' rules.
#'
#' @param x,y,z Decimal-compatible vectors.
#'
#' @return A `decimal` vector.
#' @examples
#' fma(decimal("2"), decimal("3"), decimal("4"))
#' @export
fma <- function(x, y, z) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(x, "x"),
    decimal_math_input(y, "y"),
    decimal_math_input(z, "z")
  )
  dx <- args[[1]]
  dy <- args[[2]]
  dz <- args[[3]]

  # Scale is inferred from the raw result rather than forced to the ideal
  # max(sx + sy, sz), for the same reason as decimal_binary_arith(): forcing
  # it can demand more precision than the context allows even when the raw,
  # context-rounded result is already correct.
  raw <- .decimal_fma_strings(
    vctrs::vec_data(dx),
    vctrs::vec_data(dy),
    vctrs::vec_data(dz)
  )
  decimal_new_result(raw, decimal_infer_scale(raw))
}

#' Compare decimal vector scales
#'
#' `same_quantum()` tests whether `x` and `y` have the same shared vector
#' scale. Scale is a vector-level property in this package, so every recycled
#' element comparison receives the same result.
#'
#' @param x,y Decimal-compatible vectors.
#'
#' @return A logical vector with the common recycled size of `x` and `y`.
#' @examples
#' same_quantum(decimal("1.00"), decimal("2.0"))
#' @export
same_quantum <- function(x, y) {
  args <- vctrs::vec_recycle_common(
    decimal_math_input(x, "x"),
    decimal_math_input(y, "y")
  )
  rep_len(
    decimal_scale(args[[1]]) == decimal_scale(args[[2]]),
    length(args[[1]])
  )
}

#' @export
range.decimal <- function(x, ..., na.rm = FALSE, finite = FALSE) {
  if (isTRUE(finite)) {
    rlang::abort("`finite = TRUE` is not implemented for decimal vectors.")
  }

  prep <- decimal_summary_prepare(
    c(list(x), list(...)),
    na.rm = na.rm,
    mode = "compare"
  )
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
