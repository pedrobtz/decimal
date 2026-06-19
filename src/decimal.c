#include <R.h>
#include <Rinternals.h>

#include <mpdecimal.h>

SEXP decimal_mpd_version(void) {
  return Rf_mkString(mpd_version());
}
