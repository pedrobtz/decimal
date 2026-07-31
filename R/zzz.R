#' @keywords internal
.onLoad <- function(libname, pkgname) {
  decimal_runtime_smoke_test()
  decimal_set_initial_context()
}
