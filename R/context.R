decimal_rounding_names <- function() {
  c(
    "up",
    "down",
    "ceiling",
    "floor",
    "half_up",
    "half_down",
    "half_even",
    "05up"
  )
}

decimal_signal_names <- function() {
  c(
    "clamped",
    "conversion_syntax",
    "division_by_zero",
    "division_impossible",
    "division_undefined",
    "fpu_error",
    "inexact",
    "invalid_context",
    "invalid_operation",
    "insufficient_storage",
    "not_implemented",
    "overflow",
    "rounded",
    "subnormal",
    "underflow"
  )
}

decimal_default_traps <- function() {
  c("division_by_zero", "invalid_operation", "overflow")
}

decimal_scalar_integer <- function(x, arg) {
  if (!rlang::is_integerish(x, n = 1, finite = TRUE) || is.na(x)) {
    rlang::abort(paste0("`", arg, "` must be a finite integer scalar."))
  }

  as.integer(x)
}

decimal_scalar_flag <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    rlang::abort(paste0("`", arg, "` must be `TRUE` or `FALSE`."))
  }

  x
}

decimal_signal_vector <- function(x, arg) {
  if (is.null(x)) {
    x <- character()
  }

  if (!is.character(x) || anyNA(x)) {
    rlang::abort(paste0("`", arg, "` must be a character vector without missing values."))
  }

  bad <- setdiff(unique(x), decimal_signal_names())
  if (length(bad) != 0L) {
    rlang::abort(
      paste0(
        "`", arg, "` contains unsupported signals: ",
        paste(bad, collapse = ", "), "."
      )
    )
  }

  unique(x)
}

decimal_context_from_list <- function(x, arg = "x") {
  if (inherits(x, "decimal_context")) {
    return(decimal_context(
      precision = x$precision,
      rounding = x$rounding,
      emax = x$emax,
      emin = x$emin,
      traps = x$traps,
      flags = x$flags,
      clamp = x$clamp,
      allcr = x$allcr
    ))
  }

  if (!is.list(x)) {
    rlang::abort(paste0("`", arg, "` must be a `decimal_context` or list."))
  }

  required <- c(
    "precision", "rounding", "emax", "emin",
    "traps", "flags", "clamp", "allcr"
  )

  missing <- setdiff(required, names(x))
  if (length(missing) != 0L) {
    rlang::abort(
      paste0(
        "`", arg, "` is missing required fields: ",
        paste(missing, collapse = ", "), "."
      )
    )
  }

  decimal_context(
    precision = x$precision,
    rounding = x$rounding,
    emax = x$emax,
    emin = x$emin,
    traps = x$traps,
    flags = x$flags,
    clamp = x$clamp,
    allcr = x$allcr
  )
}

decimal_context_default <- function() {
  decimal_context(
    precision = 28L,
    rounding = "half_even",
    emax = 999999L,
    emin = -999999L,
    traps = decimal_default_traps(),
    flags = character(),
    clamp = FALSE,
    allcr = TRUE
  )
}

decimal_set_initial_context <- function() {
  .decimal_state$context <- decimal_context_default()
}

decimal_sort_signals <- function(x) {
  if (length(x) == 0L) {
    return(character())
  }

  signal_names <- decimal_signal_names()
  signal_names[signal_names %in% x]
}

decimal_update_flags <- function(flags) {
  ctx <- get_decimal_context()
  ctx$flags <- decimal_sort_signals(unique(c(ctx$flags, flags)))
  .decimal_state$context <- ctx

  invisible(ctx$flags)
}

#' Create a decimal arithmetic context
#'
#' Constructs a validated arithmetic context for native `mpdecimal`
#' operations. The context controls precision, rounding, exponent limits,
#' traps, sticky flags, and classification of normal versus subnormal values.
#'
#' @param precision Integer scalar precision.
#' @param rounding One of `"up"`, `"down"`, `"ceiling"`, `"floor"`,
#'   `"half_up"`, `"half_down"`, `"half_even"`, or `"05up"`.
#' @param emax Integer scalar maximum exponent.
#' @param emin Integer scalar minimum exponent.
#' @param traps Character vector of trapped signals.
#' @param flags Character vector of sticky signal flags.
#' @param clamp Logical scalar clamp mode.
#' @param allcr Logical scalar enabling correct-rounding mode in mpdecimal.
#'
#' @return A `decimal_context` object.
#' @examples
#' decimal_context(precision = 10L)
#' decimal_context(precision = 3L, rounding = "floor", traps = character())
#' @export
decimal_context <- function(
  precision = 28L,
  rounding = "half_even",
  emax = 999999L,
  emin = -999999L,
  traps = decimal_default_traps(),
  flags = character(),
  clamp = FALSE,
  allcr = TRUE
) {
  precision <- decimal_scalar_integer(precision, "precision")
  emax <- decimal_scalar_integer(emax, "emax")
  emin <- decimal_scalar_integer(emin, "emin")
  rounding <- rlang::arg_match(rounding, decimal_rounding_names())
  traps <- decimal_signal_vector(traps, "traps")
  flags <- decimal_signal_vector(flags, "flags")
  clamp <- decimal_scalar_flag(clamp, "clamp")
  allcr <- decimal_scalar_flag(allcr, "allcr")

  if (emax < 0L) {
    rlang::abort("`emax` must be non-negative.")
  }
  if (emin > 0L) {
    rlang::abort("`emin` must be non-positive.")
  }

  ctx <- .Call(
    decimal_c_normalize_context,
    precision,
    rounding,
    emax,
    emin,
    traps,
    flags,
    clamp,
    allcr
  )

  structure(ctx, class = "decimal_context")
}

#' Get the active decimal arithmetic context
#'
#' @return A `decimal_context` object.
#' @examples
#' get_decimal_context()
#' @export
get_decimal_context <- function() {
  decimal_context_from_list(.decimal_state$context)
}

#' Set the active decimal arithmetic context
#'
#' @param x A `decimal_context` object or compatible list.
#'
#' @return The previously active `decimal_context`, invisibly.
#' @examples
#' old <- set_decimal_context(decimal_context(precision = 5L))
#' set_decimal_context(old)
#' @export
set_decimal_context <- function(x) {
  old <- get_decimal_context()
  .decimal_state$context <- decimal_context_from_list(x, arg = "x")
  invisible(old)
}

#' Use a decimal context within a block
#'
#' @param x A `decimal_context` object or compatible list.
#' @param code Code evaluated with `x` installed as the active context.
#'
#' @return The result of `code`.
#' @examples
#' with_decimal_context(
#'   decimal_context(precision = 3L, traps = character()),
#'   decimal("1.25") + decimal("0")
#' )
#' @export
with_decimal_context <- function(x, code) {
  old <- set_decimal_context(x)
  on.exit(set_decimal_context(old), add = TRUE)
  eval.parent(substitute(code))
}

#' Install a decimal context for the current scope
#'
#' @param x A `decimal_context` object or compatible list.
#' @param .local_envir Environment whose scope should control restoration.
#'
#' @return `x`, invisibly.
#' @examples
#' f <- function() {
#'   local_decimal_context(decimal_context(precision = 2L, traps = character()))
#'   decimal("1.234") + decimal("0")
#' }
#' f()
#' @export
local_decimal_context <- function(x, .local_envir = parent.frame()) {
  old <- set_decimal_context(x)
  withr::defer(set_decimal_context(old), envir = .local_envir)
  invisible(get_decimal_context())
}

#' Read sticky decimal flags
#'
#' @return A character vector of active sticky flags.
#' @examples
#' decimal_flags()
#' @export
decimal_flags <- function() {
  get_decimal_context()$flags
}

#' Clear sticky decimal flags
#'
#' @return The previously active sticky flags, invisibly.
#' @examples
#' clear_decimal_flags()
#' @export
clear_decimal_flags <- function() {
  old <- decimal_flags()
  ctx <- get_decimal_context()
  ctx$flags <- character()
  .decimal_state$context <- ctx
  invisible(old)
}

#' @export
format.decimal_context <- function(x, ...) {
  paste0(
    "<decimal_context precision=", x$precision,
    " rounding=", x$rounding,
    " emin=", x$emin,
    " emax=", x$emax,
    " clamp=", tolower(as.character(x$clamp)),
    " allcr=", tolower(as.character(x$allcr)),
    " traps=[", paste(x$traps, collapse = ", "), "]",
    " flags=[", paste(x$flags, collapse = ", "), "]>"
  )
}

#' @export
print.decimal_context <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}
