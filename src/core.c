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
    {"division_by_zero", MPD_Division_by_zero},
    {"inexact", MPD_Inexact},
    {"invalid_operation", MPD_IEEE_Invalid_operation | MPD_Not_implemented},
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

/* mpd_del() dereferences its argument, so freeing a partially allocated set of
 * handles needs a NULL check first. Kernels that hold several handles allocate
 * them all with mpd_qnew() and check afterwards, because decimal_qnew_checked()
 * raising on the second allocation would leak the first. */
static void decimal_del_if_allocated(mpd_t *dec) {
  if (dec != NULL) {
    mpd_del(dec);
  }
}

/* An owned copy of `s` from the mpdecimal allocator, or NULL. The key builders
 * return this for special values so that every key is freed the same way. */
static char *decimal_string_copy(const char *s) {
  size_t n = strlen(s) + 1;
  char *copy = mpd_alloc(n, 1);

  if (copy != NULL) {
    memcpy(copy, s, n);
  }

  return copy;
}

/* Rf_mkChar() allocates, and an R allocation failure longjmps. A kernel frees
 * its handles before calling this, so the mpdecimal string is the only native
 * memory still live, and R_UnwindProtect() frees it whether Rf_mkChar()
 * returns or unwinds. `cont` is the kernel's continuation token, made before
 * the loop so that its own allocation cannot leak anything. */
static SEXP decimal_mkchar_body(void *data) {
  return Rf_mkChar((const char *)data);
}

static void decimal_mkchar_cleanup(void *data, Rboolean jump) {
  (void)jump;
  mpd_free(data);
}

static SEXP decimal_mkchar_consume(char *text, SEXP cont) {
  return R_UnwindProtect(decimal_mkchar_body, text, decimal_mkchar_cleanup,
                         text, cont);
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

/* Parsing never raises: Rf_error() longjmps past the caller's mpd_del() calls,
 * so a caller frees the handles it holds and then calls decimal_abort_parse().
 *
 * Returns 1 when `dec` holds the parsed value, 0 when `status` explains why
 * it does not. */
static int decimal_parse_exact(mpd_t *dec, SEXP x, R_xlen_t index,
                               uint32_t *status) {
  *status = 0;
  mpd_qset_string_exact(dec, CHAR(STRING_ELT(x, index)), status);
  return *status == 0;
}

NORET static void decimal_abort_parse(uint32_t status, R_xlen_t index) {
  if (status & MPD_Malloc_error) {
    Rf_error("mpdecimal allocation failure while parsing element %lld",
             (long long)index + 1);
  }

  if (status & MPD_Conversion_syntax) {
    Rf_error("Invalid decimal string at element %lld", (long long)index + 1);
  }

  Rf_error("Unable to parse decimal string at element %lld",
           (long long)index + 1);
}

static SEXP decimal_result_list(SEXP values, uint32_t status, uint32_t trap,
                                int trap_index) {
  SEXP out, names, flags, trap_signal, trap_index_sexp;
  const char *trap_name;

  /* Callers unprotect `values` before handing it over, so protect it here
   * before the allocations below can trigger a garbage collection. */
  PROTECT(values);

  out = PROTECT(Rf_allocVector(VECSXP, 4));
  names = PROTECT(Rf_allocVector(STRSXP, 4));
  flags = PROTECT(decimal_signal_names_from_bits(status));
  trap_name = decimal_first_signal_name(trap);
  trap_signal = PROTECT(Rf_ScalarString(
      trap_name == NULL ? NA_STRING : Rf_mkChar(trap_name)));
  trap_index_sexp =
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

  UNPROTECT(6);
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

static void decimal_encode_i64_ascending(char out[21], mpd_ssize_t value) {
  uint64_t biased = ((uint64_t)(int64_t)value) ^ UINT64_C(0x8000000000000000);
  snprintf(out, 21, "%020llu", (unsigned long long)biased);
}

static void decimal_encode_i64_descending(char out[21], mpd_ssize_t value) {
  uint64_t biased = ((uint64_t)(int64_t)value) ^ UINT64_C(0x8000000000000000);
  biased = ULLONG_MAX - biased;
  snprintf(out, 21, "%020llu", (unsigned long long)biased);
}

/* The key under which numerically equal values match: the reduced form, so
 * "1.20" and "1.2" agree. Returns an owned string, or NULL on allocation
 * failure. Never raises, because the caller still holds `dec`. */
static char *decimal_equal_key(const mpd_t *dec) {
  mpd_context_t ctx;
  mpd_t *reduced;
  uint32_t status = 0;
  char *text;

  if (mpd_isnan(dec)) {
    return decimal_string_copy("NaN");
  }
  if (mpd_isinfinite(dec)) {
    const char *name = mpd_isnegative(dec) ? "-Infinity" : "Infinity";
    return decimal_string_copy(name);
  }
  if (mpd_iszero(dec)) {
    return decimal_string_copy("0");
  }

  mpd_maxcontext(&ctx);
  ctx.traps = 0;
  ctx.status = 0;
  ctx.newtrap = 0;

  reduced = mpd_qnew();
  if (reduced == NULL) {
    return NULL;
  }

  mpd_qreduce(reduced, dec, &ctx, &status);
  if (status & MPD_Malloc_error) {
    mpd_del(reduced);
    return NULL;
  }

  text = mpd_to_sci(reduced, 0);
  mpd_del(reduced);
  return text;
}

/* A key whose byte order is numeric order: a class digit, the biased adjusted
 * exponent, then the significant digits, complemented for negatives so that
 * larger magnitudes sort first. The terminator sorts below any digit for
 * positives and above for negatives, so a prefix orders correctly against a
 * longer key. Returns an owned string, or NULL on allocation failure. Never
 * raises, because the caller still holds `dec`. */
static char *decimal_order_key(const mpd_t *dec) {
  mpd_context_t ctx;
  mpd_t *reduced;
  uint32_t status = 0;
  char *text;
  char exp_key[21];
  char *key;
  size_t digits_len = 0;
  size_t i;
  size_t j;
  int negative;
  mpd_ssize_t adjexp;

  if (mpd_isnan(dec)) {
    return decimal_string_copy("6/");
  }
  if (mpd_isinfinite(dec)) {
    return decimal_string_copy(mpd_isnegative(dec) ? "1/" : "5/");
  }
  if (mpd_iszero(dec)) {
    return decimal_string_copy("3/0");
  }

  mpd_maxcontext(&ctx);
  ctx.traps = 0;
  ctx.status = 0;
  ctx.newtrap = 0;

  reduced = mpd_qnew();
  if (reduced == NULL) {
    return NULL;
  }

  mpd_qreduce(reduced, dec, &ctx, &status);
  if (status & MPD_Malloc_error) {
    mpd_del(reduced);
    return NULL;
  }

  negative = mpd_isnegative(reduced);
  adjexp = mpd_adjexp(reduced);
  text = mpd_to_sci(reduced, 0);
  mpd_del(reduced);
  if (text == NULL) {
    return NULL;
  }

  for (i = 0; text[i] != '\0' && text[i] != 'E' && text[i] != 'e'; ++i) {
    if (text[i] >= '0' && text[i] <= '9') {
      ++digits_len;
    }
  }

  key = mpd_alloc(1 + 20 + digits_len + 2, 1);
  if (key == NULL) {
    mpd_free(text);
    return NULL;
  }

  if (negative) {
    decimal_encode_i64_descending(exp_key, adjexp);
    key[0] = '2';
  } else {
    decimal_encode_i64_ascending(exp_key, adjexp);
    key[0] = '4';
  }
  memcpy(key + 1, exp_key, 20);

  j = 21;
  for (i = 0; text[i] != '\0' && text[i] != 'E' && text[i] != 'e'; ++i) {
    if (text[i] >= '0' && text[i] <= '9') {
      key[j++] = negative ? (char)('9' - (text[i] - '0')) : text[i];
    }
  }
  key[j++] = negative ? ':' : '/';
  key[j] = '\0';

  mpd_free(text);
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

/* Returns 0 when `result` holds the exact value, otherwise the status that
 * explains why it does not. Never raises: the caller owns `result` and must
 * free it before reporting. */
static uint32_t decimal_set_from_double_exact(mpd_t *result, double value) {
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
    return status;
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

  sig = mpd_qnew();
  pow2 = mpd_qnew();
  exp = mpd_qnew();
  if (sig == NULL || pow2 == NULL || exp == NULL) {
    decimal_del_if_allocated(sig);
    decimal_del_if_allocated(pow2);
    decimal_del_if_allocated(exp);
    return MPD_Malloc_error;
  }

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

  return status;
}

SEXP decimal_c_normalize_context(SEXP precision, SEXP rounding, SEXP emax,
                                 SEXP emin, SEXP traps, SEXP flags,
                                 SEXP clamp, SEXP allcr) {
  mpd_context_t ctx;
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 7));
  SEXP names = PROTECT(Rf_allocVector(STRSXP, 7));

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

  SET_STRING_ELT(names, 0, Rf_mkChar("precision"));
  SET_STRING_ELT(names, 1, Rf_mkChar("rounding"));
  SET_STRING_ELT(names, 2, Rf_mkChar("emax"));
  SET_STRING_ELT(names, 3, Rf_mkChar("emin"));
  SET_STRING_ELT(names, 4, Rf_mkChar("traps"));
  SET_STRING_ELT(names, 5, Rf_mkChar("flags"));
  SET_STRING_ELT(names, 6, Rf_mkChar("clamp"));
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

/* Fractional digits implied by a decimal string, matching the grammar the R
 * implementation used before this was moved to C:
 *
 *   ^-?([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$
 *
 * The result is (digits after the point) - (exponent). Anything that does not
 * match that grammar has no fractional-digit count and yields NA: that covers
 * NA, infinities and NaNs, and also deliberately rejects forms mpdecimal would
 * otherwise accept, such as a leading "+", a bare ".5" or a trailing "1.".
 *
 * Accumulation is done in int64 so that an exponent outside int range, or a
 * difference that leaves it, yields NA exactly as R's integer arithmetic did.
 */
static int decimal_scan_string_scale(const char *s) {
  const char *p = s;
  int64_t frac = 0;
  int64_t expo = 0;
  int64_t scale;

  if (*p == '-') {
    ++p;
  }

  if (*p < '0' || *p > '9') {
    return NA_INTEGER;
  }
  while (*p >= '0' && *p <= '9') {
    ++p;
  }

  if (*p == '.') {
    ++p;
    if (*p < '0' || *p > '9') {
      return NA_INTEGER;
    }
    while (*p >= '0' && *p <= '9') {
      ++p;
      ++frac;
      if (frac > INT_MAX) {
        return NA_INTEGER;
      }
    }
  }

  if (*p == 'e' || *p == 'E') {
    int negative = 0;

    ++p;
    if (*p == '+' || *p == '-') {
      negative = (*p == '-');
      ++p;
    }
    if (*p < '0' || *p > '9') {
      return NA_INTEGER;
    }
    while (*p >= '0' && *p <= '9') {
      expo = expo * 10 + (*p - '0');
      if (expo > (int64_t)INT_MAX + 1) {
        return NA_INTEGER;
      }
      ++p;
    }
    if (negative) {
      expo = -expo;
    }
    /* as.integer() rejected anything outside int range, including +2147483648 */
    if (expo > INT_MAX || expo < -INT_MAX) {
      return NA_INTEGER;
    }
  }

  if (*p != '\0') {
    return NA_INTEGER;
  }

  scale = frac - expo;
  if (scale > INT_MAX || scale < -INT_MAX) {
    return NA_INTEGER;
  }

  return (int)scale;
}

SEXP decimal_c_string_scale(SEXP x) {
  R_xlen_t i;
  SEXP out;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(INTSXP, XLENGTH(x)));

  for (i = 0; i < XLENGTH(x); ++i) {
    SEXP elt = STRING_ELT(x, i);

    if (i % 8192 == 0) {
      R_CheckUserInterrupt();
    }

    INTEGER(out)[i] =
        elt == NA_STRING ? NA_INTEGER : decimal_scan_string_scale(CHAR(elt));
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_canonicalize_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;
  SEXP cont;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    uint32_t parse_status = 0;
    char *text;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      decimal_abort_parse(parse_status, i);
    }

    text = mpd_to_sci(dec, 0);
    mpd_del(dec);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(out, i, decimal_mkchar_consume(text, cont));
  }

  UNPROTECT(2);
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
    uint32_t parse_status = 0;
    const char *name;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      decimal_abort_parse(parse_status, i);
    }

    name = mpd_class(dec, &ctx);
    mpd_del(dec);
    SET_STRING_ELT(out, i, Rf_mkChar(name));
  }

  UNPROTECT(1);
  return out;
}

SEXP decimal_c_format_strings(SEXP x, SEXP style) {
  R_xlen_t i;
  int use_eng;
  SEXP out;
  SEXP cont;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }
  if (TYPEOF(style) != STRSXP || XLENGTH(style) != 1) {
    Rf_error("`style` must be a length-one character vector");
  }

  use_eng = strcmp(CHAR(STRING_ELT(style, 0)), "eng") == 0;
  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    uint32_t parse_status = 0;
    char *text;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      decimal_abort_parse(parse_status, i);
    }

    text = use_eng ? mpd_to_eng(dec, 0) : mpd_to_sci(dec, 0);
    mpd_del(dec);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(out, i, decimal_mkchar_consume(text, cont));
  }

  UNPROTECT(2);
  return out;
}

SEXP decimal_c_from_double_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;
  SEXP cont;

  if (TYPEOF(x) != REALSXP) {
    Rf_error("`x` must be a double vector");
  }

  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

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
      uint32_t status;
      char *text;

      status = decimal_set_from_double_exact(dec, value);
      if (status != 0) {
        mpd_del(dec);
        decimal_abort_status(status, "Unable to convert double exactly");
      }

      text = mpd_to_sci(dec, 0);
      mpd_del(dec);
      if (text == NULL) {
        Rf_error("Unable to format exact double conversion");
      }

      SET_STRING_ELT(out, i, decimal_mkchar_consume(text, cont));
    }
  }

  UNPROTECT(2);
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
    uint32_t parse_status = 0;
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
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      decimal_abort_parse(parse_status, i);
    }

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
    uint32_t parse_status = 0;
    int32_t value;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      INTEGER(out)[i] = NA_INTEGER;
      continue;
    }

    dec = mpd_qnew();
    trunc = mpd_qnew();
    if (dec == NULL || trunc == NULL) {
      decimal_del_if_allocated(dec);
      decimal_del_if_allocated(trunc);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      mpd_del(trunc);
      decimal_abort_parse(parse_status, i);
    }

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
  SEXP cont;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    uint32_t parse_status = 0;
    char *key;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      decimal_abort_parse(parse_status, i);
    }

    key = decimal_equal_key(dec);
    mpd_del(dec);
    if (key == NULL) {
      Rf_error("mpdecimal allocation failure during normalization");
    }

    SET_STRING_ELT(out, i, decimal_mkchar_consume(key, cont));
  }

  UNPROTECT(2);
  return out;
}

SEXP decimal_c_order_proxy_strings(SEXP x) {
  R_xlen_t i;
  SEXP out;
  SEXP cont;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  out = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *dec;
    uint32_t parse_status = 0;
    char *key;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }

    dec = decimal_qnew_checked();
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      decimal_abort_parse(parse_status, i);
    }

    key = decimal_order_key(dec);
    mpd_del(dec);
    if (key == NULL) {
      Rf_error("mpdecimal allocation failure during ordering");
    }

    SET_STRING_ELT(out, i, decimal_mkchar_consume(key, cont));
  }

  UNPROTECT(2);
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
  SEXP cont;
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
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *input;
    mpd_t *result;
    uint32_t parse_status = 0;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    input = mpd_qnew();
    result = mpd_qnew();
    if (input == NULL || result == NULL) {
      decimal_del_if_allocated(input);
      decimal_del_if_allocated(result);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(input, x, i, &parse_status)) {
      mpd_del(input);
      mpd_del(result);
      decimal_abort_parse(parse_status, i);
    }

    fun(result, input, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(input);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during unary arithmetic");
    }

    text = mpd_to_sci(result, 0);
    mpd_del(input);
    mpd_del(result);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, decimal_mkchar_consume(text, cont));

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }
  }

  UNPROTECT(2);
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
  SEXP cont;
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
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    mpd_t *result;
    uint32_t parse_status = 0;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    lhs = mpd_qnew();
    rhs = mpd_qnew();
    result = mpd_qnew();
    if (lhs == NULL || rhs == NULL || result == NULL) {
      decimal_del_if_allocated(lhs);
      decimal_del_if_allocated(rhs);
      decimal_del_if_allocated(result);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(lhs, x, i, &parse_status) ||
        !decimal_parse_exact(rhs, y, i, &parse_status)) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      decimal_abort_parse(parse_status, i);
    }

    fun(result, lhs, rhs, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during arithmetic");
    }

    text = mpd_to_sci(result, 0);
    mpd_del(lhs);
    mpd_del(rhs);
    mpd_del(result);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, decimal_mkchar_consume(text, cont));

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }
  }

  UNPROTECT(2);
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
    uint32_t parse_status = 0;
    int cmp;
    int value;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      LOGICAL(values)[i] = NA_LOGICAL;
      continue;
    }

    lhs = mpd_qnew();
    rhs = mpd_qnew();
    if (lhs == NULL || rhs == NULL) {
      decimal_del_if_allocated(lhs);
      decimal_del_if_allocated(rhs);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(lhs, x, i, &parse_status) ||
        !decimal_parse_exact(rhs, y, i, &parse_status)) {
      mpd_del(lhs);
      mpd_del(rhs);
      decimal_abort_parse(parse_status, i);
    }

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
  SEXP cont;
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
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *input;
    mpd_t *result;
    uint32_t parse_status = 0;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    input = mpd_qnew();
    result = mpd_qnew();
    if (input == NULL || result == NULL) {
      decimal_del_if_allocated(input);
      decimal_del_if_allocated(result);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(input, x, i, &parse_status)) {
      mpd_del(input);
      mpd_del(result);
      decimal_abort_parse(parse_status, i);
    }

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
    mpd_del(input);
    mpd_del(result);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, decimal_mkchar_consume(text, cont));

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }
  }

  UNPROTECT(2);
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
  SEXP cont;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP) {
    Rf_error("`x` and `y` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y)) {
    Rf_error("`x` and `y` must have the same length");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    mpd_t *result;
    uint32_t parse_status = 0;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    lhs = mpd_qnew();
    rhs = mpd_qnew();
    result = mpd_qnew();
    if (lhs == NULL || rhs == NULL || result == NULL) {
      decimal_del_if_allocated(lhs);
      decimal_del_if_allocated(rhs);
      decimal_del_if_allocated(result);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(lhs, x, i, &parse_status) ||
        !decimal_parse_exact(rhs, y, i, &parse_status)) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      decimal_abort_parse(parse_status, i);
    }

    mpd_qquantize(result, lhs, rhs, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during quantize");
    }

    text = mpd_to_sci(result, 0);
    mpd_del(lhs);
    mpd_del(rhs);
    mpd_del(result);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, decimal_mkchar_consume(text, cont));

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }
  }

  UNPROTECT(2);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}

SEXP decimal_c_rescale_exact_strings(SEXP x, SEXP exponent) {
  R_xlen_t i;
  mpd_context_t ctx;
  mpd_ssize_t target_exponent;
  SEXP values;
  SEXP cont;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }
  if (TYPEOF(exponent) != INTSXP || XLENGTH(exponent) != 1 ||
      INTEGER(exponent)[0] == NA_INTEGER) {
    Rf_error("`exponent` must be an integer scalar");
  }

  target_exponent = (mpd_ssize_t)INTEGER(exponent)[0];
  mpd_maxcontext(&ctx);
  ctx.traps = 0;
  ctx.status = 0;
  ctx.newtrap = 0;
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *input;
    mpd_t *result;
    uint32_t parse_status = 0;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    input = mpd_qnew();
    result = mpd_qnew();
    if (input == NULL || result == NULL) {
      decimal_del_if_allocated(input);
      decimal_del_if_allocated(result);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(input, x, i, &parse_status)) {
      mpd_del(input);
      mpd_del(result);
      decimal_abort_parse(parse_status, i);
    }

    mpd_qrescale(result, input, target_exponent, &ctx, &status);

    if (status != 0) {
      mpd_del(input);
      mpd_del(result);
      decimal_abort_status(status, "Unable to rescale decimal exactly");
    }

    text = mpd_to_sci(result, 0);
    mpd_del(input);
    mpd_del(result);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, decimal_mkchar_consume(text, cont));
  }

  UNPROTECT(2);
  return values;
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
  SEXP cont;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP || TYPEOF(z) != STRSXP) {
    Rf_error("`x`, `y`, and `z` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y) || XLENGTH(x) != XLENGTH(z)) {
    Rf_error("`x`, `y`, and `z` must have the same length");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    mpd_t *add;
    mpd_t *result;
    uint32_t parse_status = 0;
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

    lhs = mpd_qnew();
    rhs = mpd_qnew();
    add = mpd_qnew();
    result = mpd_qnew();
    if (lhs == NULL || rhs == NULL || add == NULL || result == NULL) {
      decimal_del_if_allocated(lhs);
      decimal_del_if_allocated(rhs);
      decimal_del_if_allocated(add);
      decimal_del_if_allocated(result);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(lhs, x, i, &parse_status) ||
        !decimal_parse_exact(rhs, y, i, &parse_status) ||
        !decimal_parse_exact(add, z, i, &parse_status)) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(add);
      mpd_del(result);
      decimal_abort_parse(parse_status, i);
    }

    mpd_qfma(result, lhs, rhs, add, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(add);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during fma");
    }

    text = mpd_to_sci(result, 0);
    mpd_del(lhs);
    mpd_del(rhs);
    mpd_del(add);
    mpd_del(result);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, decimal_mkchar_consume(text, cont));

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }
  }

  UNPROTECT(2);
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
    uint32_t parse_status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      LOGICAL(out)[i] = NA_LOGICAL;
      continue;
    }

    lhs = mpd_qnew();
    rhs = mpd_qnew();
    if (lhs == NULL || rhs == NULL) {
      decimal_del_if_allocated(lhs);
      decimal_del_if_allocated(rhs);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(lhs, x, i, &parse_status) ||
        !decimal_parse_exact(rhs, y, i, &parse_status)) {
      mpd_del(lhs);
      mpd_del(rhs);
      decimal_abort_parse(parse_status, i);
    }

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
    uint32_t parse_status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      INTEGER(out)[i] = NA_INTEGER;
      continue;
    }

    dec = decimal_qnew_checked();
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      decimal_abort_parse(parse_status, i);
    }

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
    uint32_t parse_status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      LOGICAL(out)[i] = strcmp(name, "na") == 0 ? TRUE : FALSE;
      continue;
    }

    dec = decimal_qnew_checked();
    if (!decimal_parse_exact(dec, x, i, &parse_status)) {
      mpd_del(dec);
      decimal_abort_parse(parse_status, i);
    }

    /* Several mpd_is*() predicates return masked flag bits rather than 0 or 1
       -- mpd_isnan() yields MPD_NAN (4) or MPD_SNAN (8), mpd_isinfinite()
       yields MPD_INF (2). Storing those directly produces an LGLSXP holding
       values R never expects, which prints as TRUE but breaks sum(), which(),
       identical() and comparison against TRUE. Normalise every branch. */
    if (strcmp(name, "na") == 0) {
      LOGICAL(out)[i] = mpd_isnan(dec) ? TRUE : FALSE;
    } else if (strcmp(name, "nan") == 0) {
      LOGICAL(out)[i] = mpd_isnan(dec) ? TRUE : FALSE;
    } else if (strcmp(name, "finite") == 0) {
      LOGICAL(out)[i] = mpd_isspecial(dec) ? FALSE : TRUE;
    } else if (strcmp(name, "qnan") == 0) {
      LOGICAL(out)[i] = mpd_isqnan(dec) ? TRUE : FALSE;
    } else if (strcmp(name, "snan") == 0) {
      LOGICAL(out)[i] = mpd_issnan(dec) ? TRUE : FALSE;
    } else if (strcmp(name, "infinite") == 0) {
      LOGICAL(out)[i] = mpd_isinfinite(dec) ? TRUE : FALSE;
    } else if (strcmp(name, "signed") == 0) {
      LOGICAL(out)[i] = mpd_issigned(dec) ? TRUE : FALSE;
    } else if (strcmp(name, "zero") == 0) {
      LOGICAL(out)[i] = mpd_iszero(dec) ? TRUE : FALSE;
    } else if (strcmp(name, "normal") == 0) {
      LOGICAL(out)[i] = mpd_isnormal(dec, &ctx) ? TRUE : FALSE;
    } else if (strcmp(name, "subnormal") == 0) {
      LOGICAL(out)[i] = mpd_issubnormal(dec, &ctx) ? TRUE : FALSE;
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
  SEXP cont;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *input;
    mpd_t *result;
    uint32_t parse_status = 0;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    input = mpd_qnew();
    result = mpd_qnew();
    if (input == NULL || result == NULL) {
      decimal_del_if_allocated(input);
      decimal_del_if_allocated(result);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(input, x, i, &parse_status)) {
      mpd_del(input);
      mpd_del(result);
      decimal_abort_parse(parse_status, i);
    }

    mpd_qplus(result, input, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(input);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during context application");
    }

    text = mpd_to_sci(result, 0);
    mpd_del(input);
    mpd_del(result);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, decimal_mkchar_consume(text, cont));

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }
  }

  UNPROTECT(2);
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
  SEXP cont;

  if (TYPEOF(x) != STRSXP || TYPEOF(y) != STRSXP) {
    Rf_error("`x` and `y` must be character vectors");
  }
  if (XLENGTH(x) != XLENGTH(y)) {
    Rf_error("`x` and `y` must have the same length");
  }

  decimal_context_from_args(&ctx, precision, rounding, emax, emin, traps, flags,
                            clamp, allcr);
  values = PROTECT(Rf_allocVector(STRSXP, XLENGTH(x)));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < XLENGTH(x); ++i) {
    mpd_t *lhs;
    mpd_t *rhs;
    mpd_t *result;
    uint32_t parse_status = 0;
    char *text;
    uint32_t status = 0;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING || STRING_ELT(y, i) == NA_STRING) {
      SET_STRING_ELT(values, i, NA_STRING);
      continue;
    }

    lhs = mpd_qnew();
    rhs = mpd_qnew();
    result = mpd_qnew();
    if (lhs == NULL || rhs == NULL || result == NULL) {
      decimal_del_if_allocated(lhs);
      decimal_del_if_allocated(rhs);
      decimal_del_if_allocated(result);
      Rf_error("mpdecimal allocation failure");
    }
    if (!decimal_parse_exact(lhs, x, i, &parse_status) ||
        !decimal_parse_exact(rhs, y, i, &parse_status)) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      decimal_abort_parse(parse_status, i);
    }

    mpd_qdiv(result, lhs, rhs, &ctx, &status);

    if (status & MPD_Malloc_error) {
      mpd_del(lhs);
      mpd_del(rhs);
      mpd_del(result);
      Rf_error("mpdecimal allocation failure during division");
    }

    text = mpd_to_sci(result, 0);
    mpd_del(lhs);
    mpd_del(rhs);
    mpd_del(result);
    if (text == NULL) {
      Rf_error("Unable to format decimal at element %lld",
               (long long)i + 1);
    }

    SET_STRING_ELT(values, i, decimal_mkchar_consume(text, cont));

    aggregate_status |= status;
    if (trap_index < 0 && (status & ctx.traps) != 0) {
      trap_index = (int)i + 1;
      trap_status = status & ctx.traps;
    }
  }

  UNPROTECT(2);
  return decimal_result_list(values, aggregate_status, trap_status, trap_index);
}
