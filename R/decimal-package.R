#' decimal: Arbitrary-Precision Decimal Vectors for R
#'
#' `decimal` provides arbitrary-precision decimal vectors for R backed by the
#' vendored `mpdecimal` C library.
#'
#' The package follows a three-part model:
#'
#' - immutable decimal values stored as exact strings;
#' - an active arithmetic context controlling precision, rounding, exponent
#'   limits, traps, and sticky flags; and
#' - vector semantics implemented with `vctrs`.
#'
#' Version 0.1.0 is a correctness-first release. It supports exact
#' construction, context-aware arithmetic, comparison, summaries, special
#' values, and tibble/data-frame use. Some advanced Python `decimal`
#' capabilities remain deferred and are documented in the package README and
#' vignettes.
#'
#' @keywords internal
#' @name decimal-package
#' @useDynLib decimal, .registration = TRUE
#' @import methods
#' @import rlang
#' @import vctrs
NULL
