#include <R.h>
#include <R_ext/Arith.h>
#include <R_ext/Utils.h>
#include <Rinternals.h>

#include <mpdecimal.h>

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

typedef struct {
  const char *name;
  uint32_t bit;
} decimal_signal_info;

typedef struct {
  const char *name;
  int value;
} decimal_rounding_info;

static const decimal_signal_info decimal_signals[] = {
    {"clamped", MPD_Clamped},
    {"conversion_syntax", MPD_Conversion_syntax},
    {"division_by_zero", MPD_Division_by_zero},
    {"division_impossible", MPD_Division_impossible},
    {"division_undefined", MPD_Division_undefined},
    {"fpu_error", MPD_Fpu_error},
    {"inexact", MPD_Inexact},
    {"invalid_context", MPD_Invalid_context},
    {"invalid_operation", MPD_Invalid_operation},
    {"insufficient_storage", MPD_Insufficient_storage},
    {"not_implemented", MPD_Not_implemented},
    {"overflow", MPD_Overflow},
    {"rounded", MPD_Rounded},
    {"subnormal", MPD_Subnormal},
    {"underflow", MPD_Underflow}};

static const decimal_rounding_info decimal_roundings[] = {
    {"up", MPD_ROUND_UP},
    {"down", MPD_ROUND_DOWN},
    {"ceiling", MPD_ROUND_CEILING},
    {"floor", MPD_ROUND_FLOOR},
    {"half_up", MPD_ROUND_HALF_UP},
    {"half_down", MPD_ROUND_HALF_DOWN},
    {"half_even", MPD_ROUND_HALF_EVEN},
    {"05up", MPD_ROUND_05UP}};

static int decimal_signal_count(void) {
  return (int)(sizeof(decimal_signals) / sizeof(decimal_signals[0]));
}

static int decimal_rounding_count(void) {
  return (int)(sizeof(decimal_roundings) / sizeof(decimal_roundings[0]));
}

static void decimal_abort_status(uint32_t status, const char *message) {
  if (status == 0) {
    return;
  }

  if (status & MPD_Malloc_error) {
    Rf_error("mpdecimal allocation failure");
  }

  Rf_error("%s", message);
}

static mpd_t *decimal_qnew_checked(void) {
  mpd_t *dec = mpd_qnew();

  if (dec == NULL) {
    Rf_error("mpdecimal allocation failure");
  }

  return dec;
}

static int decimal_rounding_from_name(const char *name) {
  int i;

  for (i = 0; i < decimal_rounding_count(); ++i) {
    if (strcmp(name, decimal_roundings[i].name) == 0) {
      return decimal_roundings[i].value;
    }
  }

  return -1;
}

static uint32_t decimal_signal_bits_from_names(SEXP names) {
  uint32_t bits = 0;
  R_xlen_t i;
  int j;

  for (i = 0; i < XLENGTH(names); ++i) {
    const char *name = CHAR(STRING_ELT(names, i));
    int matched = 0;

    for (j = 0; j < decimal_signal_count(); ++j) {
      if (strcmp(name, decimal_signals[j].name) == 0) {
        bits |= decimal_signals[j].bit;
        matched = 1;
        break;
      }
    }

    if (!matched) {
      Rf_error("Unsupported decimal signal name: %s", name);
    }
  }

  return bits;
}

static const char *decimal_first_signal_name(uint32_t bits) {
  int i;

  for (i = 0; i < decimal_signal_count(); ++i) {
    if (bits & decimal_signals[i].bit) {
      return decimal_signals[i].name;
    }
  }

  return NULL;
}

static SEXP decimal_signal_names_from_bits(uint32_t bits) {
  int i;
  int count = 0;
  int out_index = 0;
  SEXP out;

  for (i = 0; i < decimal_signal_count(); ++i) {
    if (bits & decimal_signals[i].bit) {
      ++count;
    }
  }

  out = PROTECT(Rf_allocVector(STRSXP, count));

  for (i = 0; i < decimal_signal_count(); ++i) {
    if (bits & decimal_signals[i].bit) {
      SET_STRING_ELT(out, out_index++, Rf_mkChar(decimal_signals[i].name));
    }
  }

  UNPROTECT(1);
  return out;
}

static void decimal_context_from_args(
    mpd_context_t *ctx,
    SEXP precision,
    SEXP rounding,
    SEXP emax,
    SEXP emin,
    SEXP traps,
    SEXP flags,
    SEXP clamp,
    SEXP allcr) {
  int round = decimal_rounding_from_name(CHAR(STRING_ELT(rounding, 0)));
  uint32_t trap_bits = decimal_signal_bits_from_names(traps);
  uint32_t flag_bits = decimal_signal_bits_from_names(flags);

  if (round < 0) {
    Rf_error("Unsupported decimal rounding mode");
  }

  mpd_maxcontext(ctx);
  ctx->status = 0;
  ctx->newtrap = 0;

  if (!mpd_qsetprec(ctx, INTEGER(precision)[0])) {
    Rf_error("Invalid decimal precision");
  }
  if (!mpd_qsetround(ctx, round)) {
    Rf_error("Invalid decimal rounding mode");
  }
  if (!mpd_qsetemax(ctx, INTEGER(emax)[0])) {
    Rf_error("Invalid decimal emax");
  }
  if (!mpd_qsetemin(ctx, INTEGER(emin)[0])) {
    Rf_error("Invalid decimal emin");
  }
  if (!mpd_qsettraps(ctx, trap_bits)) {
    Rf_error("Invalid decimal traps");
  }
  if (!mpd_qsetstatus(ctx, flag_bits)) {
    Rf_error("Invalid decimal flags");
  }
  if (!mpd_qsetclamp(ctx, LOGICAL(clamp)[0])) {
    Rf_error("Invalid decimal clamp");
  }
  if (!mpd_qsetcr(ctx, LOGICAL(allcr)[0])) {
    Rf_error("Invalid decimal allcr");
  }
}

static void decimal_parse_exact_checked(mpd_t *dec, SEXP x, R_xlen_t index) {
  uint32_t status = 0;

  mpd_qset_string_exact(dec, CHAR(STRING_ELT(x, index)), &status);

  if (status != 0) {
    if (status & MPD_Malloc_error) {
      Rf_error("mpdecimal allocation failure while parsing element %lld",
               (long long)index + 1);
    }

    if (status & MPD_Conversion_syntax) {
      Rf_error("Invalid decimal string at element %lld",
               (long long)index + 1);
    }

    Rf_error("Unable to parse decimal string at element %lld",
             (long long)index + 1);
  }
}

static SEXP decimal_result_list(SEXP values, uint32_t status, uint32_t trap,
                                int trap_index) {
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 4));
  SEXP names = PROTECT(Rf_allocVector(STRSXP, 4));
  SEXP flags = PROTECT(decimal_signal_names_from_bits(status));
  const char *trap_name = decimal_first_signal_name(trap);
  SEXP trap_signal = PROTECT(Rf_ScalarString(
      trap_name == NULL ? NA_STRING : Rf_mkChar(trap_name)));
  SEXP trap_index_sexp =
      PROTECT(Rf_ScalarInteger(trap_index < 0 ? NA_INTEGER : trap_index));

  SET_VECTOR_ELT(out, 0, values);
  SET_VECTOR_ELT(out, 1, flags);
  SET_VECTOR_ELT(out, 2, trap_signal);
  SET_VECTOR_ELT(out, 3, trap_index_sexp);

  SET_STRING_ELT(names, 0, Rf_mkChar("values"));
  SET_STRING_ELT(names, 1, Rf_mkChar("flags"));
  SET_STRING_ELT(names, 2, Rf_mkChar("trap_signal"));
  SET_STRING_ELT(names, 3, Rf_mkChar("trap_index"));
  Rf_setAttrib(out, R_NamesSymbol, names);

  UNPROTECT(5);
  return out;
}

static SEXP decimal_logical_result_list(SEXP values, uint32_t status,
                                        uint32_t trap, int trap_index) {
  return decimal_result_list(values, status, trap, trap_index);
}

typedef void (*decimal_unary_fn)(mpd_t *, const mpd_t *, const mpd_context_t *,
                                 uint32_t *);
typedef void (*decimal_binary_fn)(mpd_t *, const mpd_t *, const mpd_t *,
                                  const mpd_context_t *, uint32_t *);

static void decimal_abort_alloc_status(uint32_t status, const char *message) {
  if (status & MPD_Malloc_error) {
    Rf_error("%s", message);
  }
}

static char *decimal_digits_from_text(const char *text) {
  size_t n = strlen(text);
  char *digits = (char *)R_alloc(n + 2, sizeof(char));
  size_t i;
  size_t j = 0;

  for (i = 0; i < n && text[i] != 'E' && text[i] != 'e'; ++i) {
    if (text[i] >= '0' && text[i] <= '9') {
      digits[j++] = text[i];
    }
  }

  digits[j] = '\0';
  return digits;
}

static void decimal_encode_i64_ascending(char out[21], mpd_ssize_t value) {
  uint64_t biased = ((uint64_t)(int64_t)value) ^ UINT64_C(0x8000000000000000);
  snprintf(out, 21, "%020llu", (unsigned long long)biased);
}

static void decimal_encode_i64_descending(char out[21], mpd_ssize_t value) {
  uint64_t biased = ((uint64_t)(int64_t)value) ^ UINT64_C(0x8000000000000000);
  biased = ULLONG_MAX - biased;
  snprintf(out, 21, "%020llu", (unsigned long long)biased);
}

static char *decimal_equal_key(mpd_t *dec) {
  mpd_context_t ctx;
  mpd_t *reduced;
  uint32_t status = 0;
  char *text;

  if (mpd_isnan(dec)) {
    return "NaN";
  }
  if (mpd_isinfinite(dec)) {
    return mpd_isnegative(dec) ? "-Infinity" : "Infinity";
  }
  if (mpd_iszero(dec)) {
    return "0";
  }

  mpd_maxcontext(&ctx);
  ctx.traps = 0;
  ctx.status = 0;
  ctx.newtrap = 0;

  reduced = decimal_qnew_checked();
  mpd_qreduce(reduced, dec, &ctx, &status);
  decimal_abort_alloc_status(status,
                             "mpdecimal allocation failure during normalization");

  text = mpd_to_sci(reduced, 0);
  mpd_del(reduced);

  if (text == NULL) {
    Rf_error("Unable to format normalized decimal");
  }

  return text;
}

static char *decimal_order_key(mpd_t *dec) {
  mpd_context_t ctx;
  mpd_t *reduced;
  uint32_t status = 0;
  char *text;
  char *digits;
  char exp_key[21];
  char *key;
  size_t digits_len;
  size_t i;

  if (mpd_isnan(dec)) {
    key = (char *)R_alloc(3, sizeof(char));
    memcpy(key, "6/", 3);
    return key;
  }
  if (mpd_isinfinite(dec)) {
    key = (char *)R_alloc(3, sizeof(char));
    memcpy(key, mpd_isnegative(dec) ? "1/" : "5/", 3);
    return key;
  }
  if (mpd_iszero(dec)) {
    key = (char *)R_alloc(4, sizeof(char));
    memcpy(key, "3/0", 4);
    return key;
  }

  mpd_maxcontext(&ctx);
  ctx.traps = 0;
  ctx.status = 0;
  ctx.newtrap = 0;

  reduced = decimal_qnew_checked();
  mpd_qreduce(reduced, dec, &ctx, &status);
  decimal_abort_alloc_status(status,
                             "mpdecimal allocation failure during ordering");

  text = mpd_to_sci(reduced, 0);
  if (text == NULL) {
    mpd_del(reduced);
    Rf_error("Unable to format order proxy for decimal");
  }

  digits = decimal_digits_from_text(text);
  digits_len = strlen(digits);
  key = (char *)R_alloc(1 + 20 + digits_len + 2, sizeof(char));

  if (mpd_isnegative(reduced)) {
    decimal_encode_i64_descending(exp_key, mpd_adjexp(reduced));
    key[0] = '2';
    memcpy(key + 1, exp_key, 20);

    for (i = 0; i < digits_len; ++i) {
      key[21 + i] = (char)('9' - (digits[i] - '0'));
    }

    key[21 + digits_len] = ':';
    key[22 + digits_len] = '\0';
  } else {
    decimal_encode_i64_ascending(exp_key, mpd_adjexp(reduced));
    key[0] = '4';
    memcpy(key + 1, exp_key, 20);
    memcpy(key + 21, digits, digits_len);
    key[21 + digits_len] = '/';
    key[22 + digits_len] = '\0';
  }

  mpd_free(text);
  mpd_del(reduced);
  return key;
}

static decimal_unary_fn decimal_unary_fun_from_name(const char *op) {
  if (strcmp(op, "+") == 0) {
    return mpd_qplus;
  }
  if (strcmp(op, "-") == 0) {
    return mpd_qminus;
  }

  return NULL;
}

static decimal_binary_fn decimal_binary_fun_from_name(const char *op) {
  if (strcmp(op, "+") == 0) {
    return mpd_qadd;
  }
  if (strcmp(op, "-") == 0) {
    return mpd_qsub;
  }
  if (strcmp(op, "*") == 0) {
    return mpd_qmul;
  }
  if (strcmp(op, "/") == 0) {
    return mpd_qdiv;
  }
  if (strcmp(op, "^") == 0) {
    return mpd_qpow;
  }
  if (strcmp(op, "%%") == 0) {
    return mpd_qrem;
  }
  if (strcmp(op, "%/%") == 0) {
    return mpd_qdivint;
  }

  return NULL;
}

static decimal_unary_fn decimal_math_fun_from_name(const char *op) {
  if (strcmp(op, "abs") == 0) {
    return mpd_qabs;
  }
  if (strcmp(op, "sqrt") == 0) {
    return mpd_qsqrt;
  }
  if (strcmp(op, "floor") == 0) {
    return mpd_qfloor;
  }
  if (strcmp(op, "ceiling") == 0) {
    return mpd_qceil;
  }
  if (strcmp(op, "trunc") == 0) {
    return mpd_qtrunc;
  }
  if (strcmp(op, "exp") == 0) {
    return mpd_qexp;
  }
  if (strcmp(op, "log") == 0) {
    return mpd_qln;
  }
  if (strcmp(op, "log10") == 0) {
    return mpd_qlog10;
  }

  return NULL;
}

static void decimal_sign_op(mpd_t *result, const mpd_t *a,
                            const mpd_context_t *ctx, uint32_t *status) {
  uint32_t local_status = 0;

  if (mpd_issnan(a)) {
    mpd_qplus(result, a, ctx, &local_status);
    *status |= local_status;
    return;
  }

  if (mpd_isqnan(a)) {
    mpd_qplus(result, a, ctx, &local_status);
    *status |= local_status;
    return;
  }

  if (mpd_iszero(a)) {
    mpd_qset_i64_exact(result, 0, &local_status);
  } else if (mpd_isnegative(a)) {
    mpd_qset_i64_exact(result, -1, &local_status);
  } else {
    mpd_qset_i64_exact(result, 1, &local_status);
  }

  *status |= local_status;
}

static void decimal_normalize_op(mpd_t *result, const mpd_t *a,
                                 const mpd_context_t *ctx, uint32_t *status) {
  mpd_qreduce(result, a, ctx, status);
}

static void decimal_set_from_double_exact(mpd_t *result, double value) {
  union {
    double d;
    uint64_t u;
  } bits;
  uint32_t status = 0;
  uint64_t raw_exponent;
  uint64_t fraction;
  uint64_t significand;
  int sign;
  int64_t exponent2;
  mpd_context_t ctx;
  mpd_t *sig = NULL;
  mpd_t *pow2 = NULL;
  mpd_t *exp = NULL;

  bits.d = value;
  sign = (int)(bits.u >> 63);
  raw_exponent = (bits.u >> 52) & 0x7ffULL;
  fraction = bits.u & ((UINT64_C(1) << 52) - 1);

  if (raw_exponent == 0 && fraction == 0) {
    mpd_qset_u64_exact(result, 0, &status);
    if (sign) {
      mpd_set_negative(result);
    }
    decimal_abort_status(status, "Unable to convert zero from double");
    return;
  }

  significand = raw_exponent == 0 ? fraction : (fraction | (UINT64_C(1) << 52));
  exponent2 = raw_exponent == 0 ? -1074 : (int64_t)raw_exponent - 1023 - 52;

  mpd_maxcontext(&ctx);
  ctx.prec = (mpd_ssize_t)((exponent2 < 0 ? -exponent2 : exponent2) + 64);
  ctx.round = MPD_ROUND_HALF_EVEN;
  ctx.traps = 0;
  ctx.status = 0;
  ctx.clamp = 0;
  ctx.allcr = 1;
  ctx.newtrap = 0;

  sig = decimal_qnew_checked();
  pow2 = decimal_qnew_checked();
  exp = decimal_qnew_checked();

  mpd_qset_u64_exact(sig, significand, &status);
  mpd_qset_u64_exact(pow2, 2, &status);

  if (exponent2 > 0) {
    mpd_qset_i64_exact(exp, exponent2, &status);
    mpd_qpow(pow2, pow2, exp, &ctx, &status);
    mpd_qmul(result, sig, pow2, &ctx, &status);
  } else if (exponent2 < 0) {
    mpd_qset_i64_exact(exp, -exponent2, &status);
    mpd_qpow(pow2, pow2, exp, &ctx, &status);
    mpd_qdiv(result, sig, pow2, &ctx, &status);
  } else {
    mpd_qcopy(result, sig, &status);
  }

  if (sign) {
    mpd_set_negative(result);
  }

  mpd_del(sig);
  mpd_del(pow2);
  mpd_del(exp);

  decimal_abort_status(status, "Unable to convert double exactly");
}

SEXP decimal_c_normalize_context(SEXP precision, SEXP rounding, SEXP emax,
                                 SEXP emin, SEXP traps, SEXP flags,
                                 SEXP clamp, SEXP allcr) {
  mpd_context_t ctx;
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 8));
  SEXP names = PROTECT(Rf_allocVector(STRSXP, 8));

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);

  SET_VECTOR_ELT(out, 0, Rf_ScalarInteger((int)ctx.prec));
  SET_VECTOR_ELT(out, 1, Rf_ScalarString(Rf_mkChar(
                             decimal_roundings[ctx.round].name)));
  SET_VECTOR_ELT(out, 2, Rf_ScalarInteger((int)ctx.emax));
  SET_VECTOR_ELT(out, 3, Rf_ScalarInteger((int)ctx.emin));
  SET_VECTOR_ELT(out, 4, decimal_signal_names_from_bits(ctx.traps));
  SET_VECTOR_ELT(out, 5, decimal_signal_names_from_bits(ctx.status));
  SET_VECTOR_ELT(out, 6, Rf_ScalarLogical(ctx.clamp));
  SET_VECTOR_ELT(out, 7, Rf_ScalarLogical(ctx.allcr));

  SET_STRING_ELT(names, 0, Rf_mkChar("precision"));
  SET_STRING_ELT(names, 1, Rf_mkChar("rounding"));
  SET_STRING_ELT(names, 2, Rf_mkChar("emax"));
  SET_STRING_ELT(names, 3, Rf_mkChar("emin"));
  SET_STRING_ELT(names, 4, Rf_mkChar("traps"));
  SET_STRING_ELT(names, 5, Rf_mkChar("flags"));
  SET_STRING_ELT(names, 6, Rf_mkChar("clamp"));
  SET_STRING_ELT(names, 7, Rf_mkChar("allcr"));
  Rf_setAttrib(out, R_NamesSymbol, names);

  UNPROTECT(2);
  return out;
}

SEXP decimal_c_validate_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(LGLSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      LOGICAL(out)[i] = NA_LOGICAL;
      continue;
    }

    dec = decimal_qnew_checked();
    mpd_qset_string_exact(dec, CHAR(STRING_ELT(x, i)), &status);
    LOGICAL(out)[i] = status == 0 ? TRUE : FALSE;
    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_canonicalize_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    char *text;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);
    text = mpd_to_sci(dec, 0);

    if (text == NULL) {
      mpd_del(dec);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(out, i, Rf_mkChar(text));
    mpd_free(text);
    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_classify_strings(SEXP x, SEXP precision, SEXP rounding,
                                SEXP emax, SEXP emin, SEXP traps,
                                SEXP flags, SEXP clamp, SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);
    SET_STRING_ELT(out, i, Rf_mkChar(mpd_class(dec, &ctx)));
    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_format_strings(SEXP x, SEXP style) {
  R_xlen_t i;
  int use_eng;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }
  if (TYPEOF(style) != STRSXP || XLENGTH(style) != 1) {
    Rf_error("`style` must be a length-one character vector");
  }

  use_eng = strcmp(CHAR(STRING_ELT(style, 0)), "eng") == 0;
  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    char *text;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);
    text = use_eng ? mpd_to_eng(dec, 0) : mpd_to_sci(dec, 0);

    if (text == NULL) {
      mpd_del(dec);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(out, i, Rf_mkChar(text));
    mpd_free(text);
    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_from_double_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != REALSXP) {
    Rf_error("`x` must be a double vector");
  }

  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    double value = REAL(x)[i];

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (ISNA(value)) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    if (ISNAN(value)) {
      SET_STRING_ELT(out, i, Rf_mkChar("NaN"));
      continue;
    }

    if (!R_FINITE(value)) {
      SET_STRING_ELT(out, i,
                     Rf_mkChar(value > 0 ? "Infinity" : "-Infinity"));
      continue;
    }

    {
      mpd_t *dec = decimal_qnew_checked();
      char *text;

      decimal_set_from_double_exact(dec, value);
      text = mpd_to_sci(dec, 0);

      if (text == NULL) {
        mpd_del(dec);
        Rf_error("Unable to format exact double conversion");
      }

      SET_STRING_ELT(out, i, Rf_mkChar(text));
      mpd_free(text);
      mpd_del(dec);
    }
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_to_double_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(REALSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    char *text;
    char *end = NULL;
    double value;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      REAL(out)[i] = NA_REAL;
      continue;
    }

    dec = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);

    if (mpd_issnan(dec) || mpd_isqnan(dec)) {
      REAL(out)[i] = R_NaN;
      mpd_del(dec);
      continue;
    }

    if (mpd_isinfinite(dec)) {
      REAL(out)[i] = mpd_isnegative(dec) ? R_NegInf : R_PosInf;
      mpd_del(dec);
      continue;
    }

    text = mpd_to_sci(dec, 0);
    if (text == NULL) {
      mpd_del(dec);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    value = R_strtod(text, &end);
    if (end == text || *end != '\0') {
      mpd_free(text);
      mpd_del(dec);
      Rf_error("Unable to convert decimal to double at element %lld",
               (long long)i + 1);
    }

    REAL(out)[i] = value;

    mpd_free(text);
    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_to_integer_strings(SEXP x) {
  R_xlen_t i;
  mpd_context_t ctx;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  mpd_maxcontext(&ctx);
  ctx.traps = 0;
  ctx.status = 0;
  ctx.newtrap = 0;

  out = PROTECT(Rf_allocVector(INTSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    mpd_t *trunc;
    uint32_t status = 0;
    int32_t value;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      INTEGER(out)[i] = NA_INTEGER;
      continue;
    }

    dec = decimal_qnew_checked();
    trunc = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);
    mpd_qtrunc(trunc, dec, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(dec);
      mpd_del(trunc);
      Rf_error("mpdecimal allocation failure during integer conversion");
    }

    if (mpd_isspecial(trunc)) {
      INTEGER(out)[i] = NA_INTEGER;
      mpd_del(dec);
      mpd_del(trunc);
      continue;
    }

    status = 0;
    value = mpd_qget_i32(trunc, &status);
    INTEGER(out)[i] =
        (status & MPD_Invalid_operation) ? NA_INTEGER : (int)value;

    mpd_del(dec);
    mpd_del(trunc);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_equal_proxy_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    char *key;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);
    key = decimal_equal_key(dec);
    SET_STRING_ELT(out, i, Rf_mkChar(key));
    if (strcmp(key, "NaN") != 0 && strcmp(key, "0") != 0 &&
        strcmp(key, "Infinity") != 0 && strcmp(key, "-Infinity") != 0) {
      mpd_free(key);
    }
    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_order_proxy_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    char *key;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);
    key = decimal_order_key(dec);
    SET_STRING_ELT(out, i, Rf_mkChar(key));
    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_unary_op_strings(SEXP x, SEXP op, SEXP precision, SEXP rounding,
                                SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                                SEXP clamp, SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  uint32_t aggregate_status = 0;
  uint32_t trap_status = 0;
  int trap_index = -1;
  SEXP values;
  decimal_unary_fn fun;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }
  if (TYPEOF(op) != STRSXP || XLENGTH(op) != 1) {
    Rf_error("`op` must be a length-one character vector");
  }

  fun = decimal_unary_fun_from_name(CHAR(STRING_ELT(op, 0)));
  if (fun == NULL) {
    Rf_error("Unsupported unary decimal operation");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *input;
    mpd_t *result;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    input = decimal_qnew_checked();
    result = decimal_qnew_checked();
    decimal_parse_exact_checked(input, x, i);
    fun(result, input, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(input);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during unary arithmetic");
    }

    text = mpd_to_sci(result, 0);
    if (text == NULL) {
      mpd_del(input);
      mpd_del(result);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, Rf_mkChar(text));
    mpd_free(text);

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }

    mpd_del(input);
    mpd_del(result);
  }

  UNPROTECT(1);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}

SEXP decimal_c_binary_op_strings(SEXP x, SEXP y, SEXP op, SEXP precision,
                                 SEXP rounding, SEXP emax, SEXP emin,
                                 SEXP traps, SEXP flags, SEXP clamp,
                                 SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  uint32_t aggregate_status = 0;
  uint32_t trap_status = 0;
  int trap_index = -1;
  SEXP values;
  decimal_binary_fn fun;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP) {
    Rf_error("`x` and `y` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y)) {
    Rf_error("`x` and `y` must have the same length");
  }
  if (TYPEOF(op) != STRSXP || XLENGTH(op) != 1) {
    Rf_error("`op` must be a length-one character vector");
  }

  fun = decimal_binary_fun_from_name(CHAR(STRING_ELT(op, 0)));
  if (fun == NULL) {
    Rf_error("Unsupported binary decimal operation");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    mpd_t *result;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    lhs = decimal_qnew_checked();
    rhs = decimal_qnew_checked();
    result = decimal_qnew_checked();
    decimal_parse_exact_checked(lhs, x, i);
    decimal_parse_exact_checked(rhs, y, i);
    fun(result, lhs, rhs, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during arithmetic");
    }

    text = mpd_to_sci(result, 0);
    if (text == NULL) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, Rf_mkChar(text));
    mpd_free(text);

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }

    mpd_del(lhs);
    mpd_del(rhs);
    mpd_del(result);
  }

  UNPROTECT(1);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}

SEXP decimal_c_compare_strings(SEXP x, SEXP y, SEXP op, SEXP precision,
                               SEXP rounding, SEXP emax, SEXP emin, SEXP traps,
                               SEXP flags, SEXP clamp, SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  uint32_t aggregate_status = 0;
  uint32_t trap_status = 0;
  int trap_index = -1;
  SEXP values;
  const char *cmp_op;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP) {
    Rf_error("`x` and `y` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y)) {
    Rf_error("`x` and `y` must have the same length");
  }
  if (TYPEOF(op) != STRSXP || XLENGTH(op) != 1) {
    Rf_error("`op` must be a length-one character vector");
  }

  cmp_op = CHAR(STRING_ELT(op, 0));
  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(LGLSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    uint32_t status = 0;
    int cmp;
    int value;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      LOGICAL(values)[i] = NA_LOGICAL;
      continue;
    }

    lhs = decimal_qnew_checked();
    rhs = decimal_qnew_checked();
    decimal_parse_exact_checked(lhs, x, i);
    decimal_parse_exact_checked(rhs, y, i);

    if (mpd_issnan(lhs) || mpd_issnan(rhs)) {
      status |= MPD_Invalid_operation;
      LOGICAL(values)[i] = NA_LOGICAL;
      aggregate_status |= status;
      if (trap_index < 0 && (status & ctx.traps) != 0) {
        trap_index = (int)i + 1;
        trap_status = status & ctx.traps;
      }
      mpd_del(lhs);
      mpd_del(rhs);
      continue;
    }

    if (mpd_isqnan(lhs) || mpd_isqnan(rhs)) {
      LOGICAL(values)[i] = NA_LOGICAL;
      mpd_del(lhs);
      mpd_del(rhs);
      continue;
    }

    cmp = mpd_qcmp(lhs, rhs, &status);
    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      Rf_error("mpdecimal allocation failure during comparison");
    }

    if (strcmp(cmp_op, "==") == 0) {
      value = cmp == 0;
    } else if (strcmp(cmp_op, "!=") == 0) {
      value = cmp != 0;
    } else if (strcmp(cmp_op, "<") == 0) {
      value = cmp < 0;
    } else if (strcmp(cmp_op, "<=") == 0) {
      value = cmp <= 0;
    } else if (strcmp(cmp_op, ">") == 0) {
      value = cmp > 0;
    } else if (strcmp(cmp_op, ">=") == 0) {
      value = cmp >= 0;
    } else {
      mpd_del(lhs);
      mpd_del(rhs);
      Rf_error("Unsupported decimal comparison");
    }

    LOGICAL(values)[i] = value;
    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }

    mpd_del(lhs);
    mpd_del(rhs);
  }

  UNPROTECT(1);
  return decimal_logical_result_list(values, aggregate_status, trap_status,
                                     trap_index);
}

SEXP decimal_c_math_op_strings(SEXP x, SEXP op, SEXP precision, SEXP rounding,
                               SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                               SEXP clamp, SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  uint32_t aggregate_status = 0;
  uint32_t trap_status = 0;
  int trap_index = -1;
  SEXP values;
  const char *op_name;
  decimal_unary_fn fun;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }
  if (TYPEOF(op) != STRSXP || XLENGTH(op) != 1) {
    Rf_error("`op` must be a length-one character vector");
  }

  op_name = CHAR(STRING_ELT(op, 0));
  fun = decimal_math_fun_from_name(op_name);
  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *input;
    mpd_t *result;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    input = decimal_qnew_checked();
    result = decimal_qnew_checked();
    decimal_parse_exact_checked(input, x, i);

    if (strcmp(op_name, "sign") == 0) {
      decimal_sign_op(result, input, &ctx, &status);
    } else if (strcmp(op_name, "normalize") == 0) {
      decimal_normalize_op(result, input, &ctx, &status);
    } else if (fun != NULL) {
      fun(result, input, &ctx, &status);
    } else {
      mpd_del(input);
      mpd_del(result);
      Rf_error("Unsupported decimal math operation");
    }

    if (status & MPD_Malloc_error) {
      mpd_del(input);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during math operation");
    }

    text = mpd_to_sci(result, 0);
    if (text == NULL) {
      mpd_del(input);
      mpd_del(result);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, Rf_mkChar(text));
    mpd_free(text);

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }

    mpd_del(input);
    mpd_del(result);
  }

  UNPROTECT(1);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}

SEXP decimal_c_quantize_strings(SEXP x, SEXP y, SEXP precision, SEXP rounding,
                                SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                                SEXP clamp, SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  uint32_t aggregate_status = 0;
  uint32_t trap_status = 0;
  int trap_index = -1;
  SEXP values;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP) {
    Rf_error("`x` and `y` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y)) {
    Rf_error("`x` and `y` must have the same length");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    mpd_t *result;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    lhs = decimal_qnew_checked();
    rhs = decimal_qnew_checked();
    result = decimal_qnew_checked();
    decimal_parse_exact_checked(lhs, x, i);
    decimal_parse_exact_checked(rhs, y, i);
    mpd_qquantize(result, lhs, rhs, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during quantize");
    }

    text = mpd_to_sci(result, 0);
    if (text == NULL) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, Rf_mkChar(text));
    mpd_free(text);

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }

    mpd_del(lhs);
    mpd_del(rhs);
    mpd_del(result);
  }

  UNPROTECT(1);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}

SEXP decimal_c_fma_strings(SEXP x, SEXP y, SEXP z, SEXP precision,
                           SEXP rounding, SEXP emax, SEXP emin, SEXP traps,
                           SEXP flags, SEXP clamp, SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  uint32_t aggregate_status = 0;
  uint32_t trap_status = 0;
  int trap_index = -1;
  SEXP values;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP || TYPEOF(z) != STRSXP) {
    Rf_error("`x`, `y`, and `z` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y) || XLENGTH(x) != XLENGTH(z)) {
    Rf_error("`x`, `y`, and `z` must have the same length");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    mpd_t *add;
    mpd_t *result;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING ||
        STRING_ELT(z, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    lhs = decimal_qnew_checked();
    rhs = decimal_qnew_checked();
    add = decimal_qnew_checked();
    result = decimal_qnew_checked();
    decimal_parse_exact_checked(lhs, x, i);
    decimal_parse_exact_checked(rhs, y, i);
    decimal_parse_exact_checked(add, z, i);
    mpd_qfma(result, lhs, rhs, add, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(add);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during fma");
    }

    text = mpd_to_sci(result, 0);
    if (text == NULL) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(add);
      mpd_del(result);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, Rf_mkChar(text));
    mpd_free(text);

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }

    mpd_del(lhs);
    mpd_del(rhs);
    mpd_del(add);
    mpd_del(result);
  }

  UNPROTECT(1);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}

SEXP decimal_c_same_quantum_strings(SEXP x, SEXP y) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP) {
    Rf_error("`x` and `y` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y)) {
    Rf_error("`x` and `y` must have the same length");
  }

  out = PROTECT(Rf_allocVector(LGLSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      LOGICAL(out)[i] = NA_LOGICAL;
      continue;
    }

    lhs = decimal_qnew_checked();
    rhs = decimal_qnew_checked();
    decimal_parse_exact_checked(lhs, x, i);
    decimal_parse_exact_checked(rhs, y, i);
    LOGICAL(out)[i] = mpd_same_quantum(lhs, rhs);
    mpd_del(lhs);
    mpd_del(rhs);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_adjusted_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(INTSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      INTEGER(out)[i] = NA_INTEGER;
      continue;
    }

    dec = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);

    if (mpd_isspecial(dec)) {
      INTEGER(out)[i] = NA_INTEGER;
    } else {
      mpd_ssize_t adj = mpd_adjexp(dec);
      if (adj > INT_MAX || adj < INT_MIN) {
        mpd_del(dec);
        Rf_error("Adjusted exponent out of integer range at element %lld",
                 (long long)i + 1);
      }
      INTEGER(out)[i] = (int)adj;
    }

    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_predicate_strings(SEXP x, SEXP predicate, SEXP precision,
                                 SEXP rounding, SEXP emax, SEXP emin,
                                 SEXP traps, SEXP flags, SEXP clamp,
                                 SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  SEXP out;
  const char *name;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }
  if (TYPEOF(predicate) != STRSXP || XLENGTH(predicate) != 1) {
    Rf_error("`predicate` must be a length-one character vector");
  }

  name = CHAR(STRING_ELT(predicate, 0));
  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  out = PROTECT(Rf_allocVector(LGLSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      LOGICAL(out)[i] = strcmp(name, "na") == 0 ? TRUE : FALSE;
      continue;
    }

    dec = decimal_qnew_checked();
    decimal_parse_exact_checked(dec, x, i);

    if (strcmp(name, "na") == 0) {
      LOGICAL(out)[i] = mpd_isnan(dec);
    } else if (strcmp(name, "nan") == 0) {
      LOGICAL(out)[i] = mpd_isnan(dec);
    } else if (strcmp(name, "finite") == 0) {
      LOGICAL(out)[i] = !mpd_isspecial(dec);
    } else if (strcmp(name, "qnan") == 0) {
      LOGICAL(out)[i] = mpd_isqnan(dec);
    } else if (strcmp(name, "snan") == 0) {
      LOGICAL(out)[i] = mpd_issnan(dec);
    } else if (strcmp(name, "infinite") == 0) {
      LOGICAL(out)[i] = mpd_isinfinite(dec);
    } else if (strcmp(name, "signed") == 0) {
      LOGICAL(out)[i] = mpd_issigned(dec);
    } else if (strcmp(name, "zero") == 0) {
      LOGICAL(out)[i] = mpd_iszero(dec);
    } else if (strcmp(name, "normal") == 0) {
      LOGICAL(out)[i] = mpd_isnormal(dec, &ctx);
    } else if (strcmp(name, "subnormal") == 0) {
      LOGICAL(out)[i] = mpd_issubnormal(dec, &ctx);
    } else {
      mpd_del(dec);
      Rf_error("Unsupported decimal predicate");
    }

    mpd_del(dec);
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_apply_context(SEXP x, SEXP precision, SEXP rounding, SEXP emax,
                             SEXP emin, SEXP traps, SEXP flags, SEXP clamp,
                             SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  uint32_t aggregate_status = 0;
  uint32_t trap_status = 0;
  int trap_index = -1;
  SEXP values;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *input;
    mpd_t *result;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    input = decimal_qnew_checked();
    result = decimal_qnew_checked();
    decimal_parse_exact_checked(input, x, i);
    mpd_qplus(result, input, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(input);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during context application");
    }

    text = mpd_to_sci(result, 0);
    if (text == NULL) {
      mpd_del(input);
      mpd_del(result);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, Rf_mkChar(text));
    mpd_free(text);

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }

    mpd_del(input);
    mpd_del(result);
  }

  UNPROTECT(1);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}

SEXP decimal_c_divide_strings(SEXP x, SEXP y, SEXP precision, SEXP rounding,
                              SEXP emax, SEXP emin, SEXP traps, SEXP flags,
                              SEXP clamp, SEXP allcr) {
  R_xlen_t i;
  mpd_context_t ctx;
  uint32_t aggregate_status = 0;
  uint32_t trap_status = 0;
  int trap_index = -1;
  SEXP values;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP) {
    Rf_error("`x` and `y` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y)) {
    Rf_error("`x` and `y` must have the same length");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    mpd_t *result;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    lhs = decimal_qnew_checked();
    rhs = decimal_qnew_checked();
    result = decimal_qnew_checked();
    decimal_parse_exact_checked(lhs, x, i);
    decimal_parse_exact_checked(rhs, y, i);
    mpd_qdiv(result, lhs, rhs, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during division");
    }

    text = mpd_to_sci(result, 0);
    if (text == NULL) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, Rf_mkChar(text));
    mpd_free(text);

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }

    mpd_del(lhs);
    mpd_del(rhs);
    mpd_del(result);
  }

  UNPROTECT(1);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}
