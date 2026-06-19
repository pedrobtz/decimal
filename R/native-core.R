decimal_native_result <- function(result, op) {
  decimal_update_flags(result$flags)

  if (!is.na(result$trap_signal)) {
    rlang::abort(
      message = paste0(
        "Decimal trap during `", op, "` at element ",
        result$trap_index, ": ", result$trap_signal, "."
      ),
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

  result$values
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
    ctx$allcr
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
