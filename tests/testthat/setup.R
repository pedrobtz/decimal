# Non-trapped signals are reported as warnings by default. The suite exercises
# many intentionally inexact operations (division, sqrt, exp, log, reduced
# precision), so disable reporting session-wide and let the dedicated tests in
# test-context.R re-enable it locally where the behavior is asserted.
withr::local_options(decimal.report_flags = FALSE, .local_envir = teardown_env())
