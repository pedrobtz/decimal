.decimal_state <- new.env(parent = emptyenv())

decimal_mpd_expected_version <- function() {
  "4.0.1"
}

decimal_runtime_smoke_test <- function() {
  version <- mpdecimal_version()
  expected <- decimal_mpd_expected_version()

  if (!identical(version, expected)) {
    rlang::abort(
      paste0(
        "decimal loaded mpdecimal ", version,
        " but expected vendored mpdecimal ", expected, "."
      )
    )
  }

  .decimal_state$mpdecimal_version <- version

  invisible(version)
}

#' Report the bundled mpdecimal runtime version
#'
#' Returns the version string reported by the bundled `mpdecimal` library that
#' was loaded with the package DLL.
#'
#' @return A length-one character vector.
#' @export
#'
#' @examples
#' mpdecimal_version()
mpdecimal_version <- function() {
  .Call(decimal_mpd_version)
}
