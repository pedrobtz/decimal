#include <R.h>
#include <R_ext/Rdynload.h>
#include <Rinternals.h>

SEXP decimal_mpd_version(void);
SEXP decimal_c_normalize_context(SEXP precision, SEXP rounding, SEXP emax,
                                 SEXP emin, SEXP traps, SEXP flags,
                                 SEXP clamp, SEXP allcr);
SEXP decimal_c_validate_strings(SEXP x);
SEXP decimal_c_canonicalize_strings(SEXP x);
SEXP decimal_c_classify_strings(SEXP x, SEXP precision, SEXP rounding,
                                SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                                SEXP clamp, SEXP allcr);
SEXP decimal_c_format_strings(SEXP x, SEXP style);
SEXP decimal_c_from_double_strings(SEXP x);
SEXP decimal_c_to_double_strings(SEXP x);
SEXP decimal_c_to_integer_strings(SEXP x);
SEXP decimal_c_equal_proxy_strings(SEXP x);
SEXP decimal_c_order_proxy_strings(SEXP x);
SEXP decimal_c_unary_op_strings(SEXP x, SEXP op, SEXP precision, SEXP rounding,
                                SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                                SEXP clamp, SEXP allcr);
SEXP decimal_c_binary_op_strings(SEXP x, SEXP y, SEXP op, SEXP precision,
                                 SEXP rounding, SEXP emax, SEXP emin,
                                 SEXP traps, SEXP flags, SEXP clamp,
                                 SEXP allcr);
SEXP decimal_c_compare_strings(SEXP x, SEXP y, SEXP op, SEXP precision,
                               SEXP rounding, SEXP emax, SEXP emin, SEXP traps,
                               SEXP flags, SEXP clamp, SEXP allcr);
SEXP decimal_c_math_op_strings(SEXP x, SEXP op, SEXP precision, SEXP rounding,
                               SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                               SEXP clamp, SEXP allcr);
SEXP decimal_c_quantize_strings(SEXP x, SEXP y, SEXP precision, SEXP rounding,
                                SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                                SEXP clamp, SEXP allcr);
SEXP decimal_c_rescale_exact_strings(SEXP x, SEXP exponent);
SEXP decimal_c_fma_strings(SEXP x, SEXP y, SEXP z, SEXP precision,
                           SEXP rounding, SEXP emax, SEXP emin, SEXP traps,
                           SEXP flags, SEXP clamp, SEXP allcr);
SEXP decimal_c_same_quantum_strings(SEXP x, SEXP y);
SEXP decimal_c_adjusted_strings(SEXP x);
SEXP decimal_c_predicate_strings(SEXP x, SEXP predicate, SEXP precision,
                                 SEXP rounding, SEXP emax, SEXP emin,
                                 SEXP traps, SEXP flags, SEXP clamp,
                                 SEXP allcr);
SEXP decimal_c_apply_context(SEXP x, SEXP precision, SEXP rounding, SEXP emax,
                             SEXP emin, SEXP traps, SEXP flags, SEXP clamp,
                             SEXP allcr);
SEXP decimal_c_divide_strings(SEXP x, SEXP y, SEXP precision, SEXP rounding,
                              SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                              SEXP clamp, SEXP allcr);

static const R_CallMethodDef CallEntries[] = {
    {"decimal_mpd_version", (DL_FUNC) &decimal_mpd_version, 0},
    {"decimal_c_normalize_context", (DL_FUNC) &decimal_c_normalize_context, 8},
    {"decimal_c_validate_strings", (DL_FUNC) &decimal_c_validate_strings, 1},
    {"decimal_c_canonicalize_strings", (DL_FUNC) &decimal_c_canonicalize_strings, 1},
    {"decimal_c_classify_strings", (DL_FUNC) &decimal_c_classify_strings, 9},
    {"decimal_c_format_strings", (DL_FUNC) &decimal_c_format_strings, 2},
    {"decimal_c_from_double_strings", (DL_FUNC) &decimal_c_from_double_strings, 1},
    {"decimal_c_to_double_strings", (DL_FUNC) &decimal_c_to_double_strings, 1},
    {"decimal_c_to_integer_strings", (DL_FUNC) &decimal_c_to_integer_strings, 1},
    {"decimal_c_equal_proxy_strings", (DL_FUNC) &decimal_c_equal_proxy_strings, 1},
    {"decimal_c_order_proxy_strings", (DL_FUNC) &decimal_c_order_proxy_strings, 1},
    {"decimal_c_unary_op_strings", (DL_FUNC) &decimal_c_unary_op_strings, 10},
    {"decimal_c_binary_op_strings", (DL_FUNC) &decimal_c_binary_op_strings, 11},
    {"decimal_c_compare_strings", (DL_FUNC) &decimal_c_compare_strings, 11},
    {"decimal_c_math_op_strings", (DL_FUNC) &decimal_c_math_op_strings, 10},
    {"decimal_c_quantize_strings", (DL_FUNC) &decimal_c_quantize_strings, 10},
    {"decimal_c_rescale_exact_strings",
     (DL_FUNC) &decimal_c_rescale_exact_strings, 2},
    {"decimal_c_fma_strings", (DL_FUNC) &decimal_c_fma_strings, 11},
    {"decimal_c_same_quantum_strings", (DL_FUNC) &decimal_c_same_quantum_strings, 2},
    {"decimal_c_adjusted_strings", (DL_FUNC) &decimal_c_adjusted_strings, 1},
    {"decimal_c_predicate_strings", (DL_FUNC) &decimal_c_predicate_strings, 10},
    {"decimal_c_apply_context", (DL_FUNC) &decimal_c_apply_context, 9},
    {"decimal_c_divide_strings", (DL_FUNC) &decimal_c_divide_strings, 10},
    {NULL, NULL, 0}
};

void R_init_decimal(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
