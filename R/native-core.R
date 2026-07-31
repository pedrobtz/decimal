decimal_native_result <- function(result, op) {
  decimal_update_flags(result$flags)

  if (!is.na(result$trap_signal)) {
    header <- paste0(
      "Decimal trap during `",
      op,
      "` at element ",
      result$trap_index,
      ": ",
      result$trap_signal,
      "."
    )
    rlang::abort(
      message = c(header, decimal_trap_hint(op, result$trap_signal)),
      class = c(
        paste0("decimal_", result$trap_signal),
        "decimal_trap",
        "error",
        "condition"
      ),
      signal = result$trap_signal,
      index = result$trap_index,
      flags = result$flags,
      operation = op
    )
  }

  # No trap fired, so every signal raised by this operation is non-trapped.
  # Unless reporting is disabled, surface them as a warning -- the third
  # disposition between an error (trapped) and a silent sticky flag.
  decimal_report_flags(result$flags, op)

  result$values
}

# TRUE when non-trapped signals should be surfaced as warnings. Controlled by
# the global `decimal.report_flags` option; reporting is on by default.
decimal_report_flags_enabled <- function() {
  isTRUE(getOption("decimal.report_flags", TRUE))
}

decimal_report_flags <- function(flags, op) {
  if (!decimal_report_flags_enabled()) {
    return(invisible())
  }

  flags <- setdiff(flags, decimal_expected_signals(op))
  if (length(flags) == 0L) {
    return(invisible())
  }

  header <- paste0(
    "Decimal `",
    op,
    "` raised ",
    if (length(flags) == 1L) "signal: " else "signals: ",
    paste(flags, collapse = ", "),
    "."
  )
  rlang::warn(
    message = header,
    class = c(
      paste0("decimal_", flags, "_warning"),
      "decimal_flags_warning",
      "warning",
      "condition"
    ),
    signals = flags,
    operation = op
  )

  invisible()
}

# Operations whose `inexact`/`rounded` signals are the guaranteed, expected
# outcome of calling them rather than a surprise -- they still accumulate as
# sticky flags, just without a warning.
#
# `quantize()` (and `round()`/`signif()`, built on it) exist specifically to
# reduce precision to a requested scale. `sqrt()`, `exp()`, `log()`, and
# `log10()` are irrational for nearly every input, so at any finite context
# precision they are inexact almost every time they're called -- warning on
# that would fire on nearly every use, unlike e.g. `/`, which is only
# sometimes inexact and so still warns.
decimal_expected_signals <- function(op) {
  if (op %in% c("quantize", "sqrt", "exp", "log", "log10")) {
    return(c("inexact", "rounded"))
  }

  character()
}

# Explain *why* a trap fired, since the raw GDA signal name alone rarely tells
# the caller what to change. Returns a named character vector of rlang bullets
# (or NULL when we have nothing more specific to add than the signal itself).
decimal_trap_hint <- function(op, signal) {
  if (identical(op, "quantize") && identical(signal, "invalid_operation")) {
    precision <- get_decimal_context()$precision
    return(c(
      i = paste0(
        "The requested scale needs more significant digits than the context ",
        "precision (",
        precision,
        ") allows."
      ),
      i = "Raise the precision with `decimal_context(precision = )`, or use a smaller scale."
    ))
  }

  NULL
}

decimal_context_call <- function(fun, ...) {
  ctx <- get_decimal_context()
  fun(
    ...,
    ctx$precision,
    ctx$rounding,
    ctx$emax,
    ctx$emin,
    ctx$traps,
    ctx$flags,
    ctx$clamp,
    TRUE
  )
}

.decimal_validate_strings <- function(x) {
  .Call(decimal_c_validate_strings, x)
}

.decimal_canonicalize_strings <- function(x) {
  .Call(decimal_c_canonicalize_strings, x)
}

.decimal_classify_strings <- function(x) {
  decimal_context_call(.Call, decimal_c_classify_strings, x)
}

.decimal_format_strings <- function(x, style = c("sci", "eng")) {
  style <- rlang::arg_match(style, c("sci", "eng"))
  .Call(decimal_c_format_strings, x, style)
}

.decimal_from_double_strings <- function(x) {
  .Call(decimal_c_from_double_strings, x)
}

.decimal_to_double_strings <- function(x) {
  .Call(decimal_c_to_double_strings, x)
}

.decimal_to_integer_strings <- function(x) {
  .Call(decimal_c_to_integer_strings, x)
}

.decimal_equal_proxy_strings <- function(x) {
  .Call(decimal_c_equal_proxy_strings, x)
}

.decimal_order_proxy_strings <- function(x) {
  .Call(decimal_c_order_proxy_strings, x)
}

.decimal_unary_op_strings <- function(x, op) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_unary_op_strings, x, op),
    op = op
  )
}

.decimal_binary_op_strings <- function(x, y, op) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_binary_op_strings, x, y, op),
    op = op
  )
}

.decimal_compare_strings <- function(x, y, op) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_compare_strings, x, y, op),
    op = op
  )
}

.decimal_math_op_strings <- function(x, op) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_math_op_strings, x, op),
    op = op
  )
}

.decimal_quantize_strings <- function(x, y) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_quantize_strings, x, y),
    op = "quantize"
  )
}

.decimal_rescale_exact_strings <- function(x, exponent) {
  .Call(decimal_c_rescale_exact_strings, x, as.integer(exponent))
}

.decimal_fma_strings <- function(x, y, z) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_fma_strings, x, y, z),
    op = "fma"
  )
}

.decimal_same_quantum_strings <- function(x, y) {
  .Call(decimal_c_same_quantum_strings, x, y)
}

.decimal_adjusted_strings <- function(x) {
  .Call(decimal_c_adjusted_strings, x)
}

.decimal_predicate_strings <- function(x, predicate) {
  decimal_context_call(.Call, decimal_c_predicate_strings, x, predicate)
}

.decimal_apply_context <- function(x) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_apply_context, x),
    op = "context"
  )
}

.decimal_divide_strings <- function(x, y) {
  decimal_native_result(
    decimal_context_call(.Call, decimal_c_divide_strings, x, y),
    op = "divide"
  )
}
