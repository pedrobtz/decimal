/* Arrow decimal arrays in the C Data Interface.
 *
 * These kernels read and write Arrow decimal32, decimal64, decimal128 and
 * decimal256 arrays directly, so the conversion needs neither the arrow nor
 * the nanoarrow nor the zuarrow package. A handle is an external pointer in
 * nanoarrow's `r.h` layout: its address is the C struct, an array's tag is
 * its schema's external pointer, and a finalizer releases what it owns. Any
 * producer that follows that layout, nanoarrow and zuarrow included, can
 * pass its handles here.
 *
 * An Arrow decimal is a little-endian two's-complement integer of 4, 8, 16
 * or 32 bytes, the coefficient of a value whose exponent is minus the type's
 * scale. mpdecimal imports and exports integers in base 2^16, so the bytes
 * cross in 16-bit words, least significant first, whatever the host's byte
 * order. */

#include <R.h>
#include <R_ext/Utils.h>
#include <Rinternals.h>

#include <mpdecimal.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The C Data Interface ABI, as the Arrow specification publishes it for
 * copying. The guard lets another definition of the same ABI win. */
#ifndef ARROW_C_DATA_INTERFACE
#define ARROW_C_DATA_INTERFACE

#define ARROW_FLAG_DICTIONARY_ORDERED 1
#define ARROW_FLAG_NULLABLE 2
#define ARROW_FLAG_MAP_KEYS_SORTED 4

struct ArrowSchema {
  const char *format;
  const char *name;
  const char *metadata;
  int64_t flags;
  int64_t n_children;
  struct ArrowSchema **children;
  struct ArrowSchema *dictionary;
  void (*release)(struct ArrowSchema *);
  void *private_data;
};

struct ArrowArray {
  int64_t length;
  int64_t null_count;
  int64_t offset;
  int64_t n_buffers;
  int64_t n_children;
  const void **buffers;
  struct ArrowArray **children;
  struct ArrowArray *dictionary;
  void (*release)(struct ArrowArray *);
  void *private_data;
};

#endif

/* The widest decimal, decimal256, is 32 bytes. */
#define DECIMAL_ARROW_MAX_BYTES 32

typedef struct {
  int precision;
  int scale;
  int bits;
} decimal_arrow_type;

/* ---- the decimal type ---------------------------------------------------- */

static int decimal_arrow_max_precision(int bits) {
  switch (bits) {
  case 32:
    return 9;
  case 64:
    return 18;
  case 128:
    return 38;
  case 256:
    return 76;
  default:
    return -1;
  }
}

/* Parses `d:precision,scale[,bits]`. Without bits the type is decimal128. */
static int decimal_arrow_parse_format(const char *format,
                                      decimal_arrow_type *type) {
  char tail;
  int matched;

  if (format == NULL || strncmp(format, "d:", 2) != 0) {
    return 0;
  }

  type->bits = 128;
  matched = sscanf(format + 2, "%d,%d,%d%c", &type->precision, &type->scale,
                   &type->bits, &tail);
  if (matched != 2 && matched != 3) {
    return 0;
  }

  if (decimal_arrow_max_precision(type->bits) < 0 || type->precision < 1) {
    return 0;
  }

  return 1;
}

/* Negates a little-endian two's-complement integer in place. */
static void decimal_arrow_negate(unsigned char *bytes, int width) {
  int carry = 1;
  int i;

  for (i = 0; i < width; ++i) {
    int value = (unsigned char)~bytes[i] + carry;
    bytes[i] = (unsigned char)(value & 0xff);
    carry = value >> 8;
  }
}

/* ---- handles ------------------------------------------------------------- */

static void decimal_arrow_finalize_schema(SEXP xptr) {
  struct ArrowSchema *schema = (struct ArrowSchema *)R_ExternalPtrAddr(xptr);

  if (schema == NULL) {
    return;
  }
  if (schema->release != NULL) {
    schema->release(schema);
  }
  free(schema);
  R_ClearExternalPtr(xptr);
}

static void decimal_arrow_finalize_array(SEXP xptr) {
  struct ArrowArray *array = (struct ArrowArray *)R_ExternalPtrAddr(xptr);

  if (array == NULL) {
    return;
  }
  if (array->release != NULL) {
    array->release(array);
  }
  free(array);
  R_ClearExternalPtr(xptr);
}

static void decimal_arrow_release_schema(struct ArrowSchema *schema) {
  free((void *)schema->format);
  free((void *)schema->name);
  schema->release = NULL;
}

static void decimal_arrow_release_array(struct ArrowArray *array) {
  if (array->buffers != NULL) {
    free((void *)array->buffers[0]);
    free((void *)array->buffers[1]);
    free((void *)array->buffers);
  }
  array->release = NULL;
}

/* The schema handle given, or the one the array handle carries in its tag. */
static const struct ArrowSchema *decimal_arrow_schema_of(SEXP array_xptr,
                                                         SEXP schema_xptr) {
  struct ArrowSchema *schema;

  if (schema_xptr == R_NilValue) {
    schema_xptr = R_ExternalPtrTag(array_xptr);
  }
  if (TYPEOF(schema_xptr) != EXTPTRSXP ||
      !Rf_inherits(schema_xptr, "nanoarrow_schema")) {
    Rf_error("The array handle does not carry its schema");
  }

  schema = (struct ArrowSchema *)R_ExternalPtrAddr(schema_xptr);
  if (schema == NULL || schema->release == NULL) {
    Rf_error("The array's schema has been released");
  }

  return schema;
}

static const struct ArrowArray *decimal_arrow_array_of(SEXP array_xptr) {
  struct ArrowArray *array;

  if (TYPEOF(array_xptr) != EXTPTRSXP ||
      !Rf_inherits(array_xptr, "nanoarrow_array")) {
    Rf_error("`array` must be an Arrow array handle");
  }

  array = (struct ArrowArray *)R_ExternalPtrAddr(array_xptr);
  if (array == NULL || array->release == NULL) {
    Rf_error("The array has been released");
  }

  return array;
}

/* ---- Arrow to decimal ---------------------------------------------------- */

static SEXP decimal_arrow_mkchar_body(void *data) {
  return Rf_mkChar((const char *)data);
}

static void decimal_arrow_mkchar_cleanup(void *data, Rboolean jump) {
  (void)jump;
  mpd_free(data);
}

/* `schema_xptr` is `NULL` to use the array's own schema. Returns
 * `list(values, precision, scale, bits)`: the canonical strings this
 * package stores, `NA` for a null, and the Arrow type. */
SEXP decimal_c_arrow_decode(SEXP array_xptr, SEXP schema_xptr) {
  const struct ArrowArray *array = decimal_arrow_array_of(array_xptr);
  const struct ArrowSchema *schema =
      decimal_arrow_schema_of(array_xptr, schema_xptr);
  decimal_arrow_type type;
  const unsigned char *validity;
  const unsigned char *values;
  mpd_context_t ctx;
  int width;
  int64_t i;
  SEXP strings;
  SEXP cont;
  SEXP out;
  SEXP names;
  /* A static decimal holds every 256-bit coefficient without allocating, so
   * no R error in the loop can leak it. */
  mpd_uint_t data[MPD_MINALLOC_MAX];
  mpd_t dec = {MPD_STATIC | MPD_STATIC_DATA, 0, 0, 0, MPD_MINALLOC_MAX, data};

  if (!decimal_arrow_parse_format(schema->format, &type)) {
    Rf_error("The array is not an Arrow decimal; its format is `%s`",
             schema->format == NULL ? "" : schema->format);
  }
  if (array->n_buffers != 2) {
    Rf_error("An Arrow decimal array must have 2 buffers, not %lld",
             (long long)array->n_buffers);
  }
  if (array->length < 0 || array->offset < 0 ||
      array->length > R_XLEN_T_MAX) {
    Rf_error("The array's length or offset is invalid");
  }

  width = type.bits / 8;
  validity = array->null_count == 0
                 ? NULL
                 : (const unsigned char *)array->buffers[0];
  values = (const unsigned char *)array->buffers[1];
  if (array->length > 0 && values == NULL) {
    Rf_error("The array has no value buffer");
  }

  mpd_maxcontext(&ctx);
  ctx.traps = 0;

  strings = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)array->length));
  cont = PROTECT(R_MakeUnwindCont());

  for (i = 0; i < array->length; ++i) {
    int64_t j = array->offset + i;
    unsigned char bytes[DECIMAL_ARROW_MAX_BYTES];
    uint16_t words[DECIMAL_ARROW_MAX_BYTES / 2];
    size_t n_words = (size_t)width / 2;
    uint8_t sign = MPD_POS;
    uint32_t status = 0;
    char *text;
    size_t k;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (validity != NULL && !((validity[j >> 3] >> (j & 7)) & 1)) {
      SET_STRING_ELT(strings, (R_xlen_t)i, NA_STRING);
      continue;
    }

    memcpy(bytes, values + j * width, (size_t)width);
    if (bytes[width - 1] & 0x80) {
      sign = MPD_NEG;
      decimal_arrow_negate(bytes, width);
    }
    for (k = 0; k < n_words; ++k) {
      words[k] = (uint16_t)(bytes[2 * k] | (bytes[2 * k + 1] << 8));
    }
    while (n_words > 1 && words[n_words - 1] == 0) {
      --n_words;
    }

    mpd_qimport_u16(&dec, words, n_words, sign, 65536, &ctx, &status);
    if (status != 0) {
      Rf_error("Unable to read the Arrow decimal at element %lld",
               (long long)i + 1);
    }
    /* The integer is the coefficient; the type's scale gives the exponent. */
    dec.exp = -(mpd_ssize_t)type.scale;

    text = mpd_to_sci(&dec, 0);
    if (text == NULL) {
      Rf_error("Unable to format the Arrow decimal at element %lld",
               (long long)i + 1);
    }
    SET_STRING_ELT(strings, (R_xlen_t)i,
                   R_UnwindProtect(decimal_arrow_mkchar_body, text,
                                   decimal_arrow_mkchar_cleanup, text, cont));
  }

  out = PROTECT(Rf_allocVector(VECSXP, 4));
  SET_VECTOR_ELT(out, 0, strings);
  SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(type.precision));
  SET_VECTOR_ELT(out, 2, Rf_ScalarInteger(type.scale));
  SET_VECTOR_ELT(out, 3, Rf_ScalarInteger(type.bits));
  names = PROTECT(Rf_allocVector(STRSXP, 4));
  SET_STRING_ELT(names, 0, Rf_mkChar("values"));
  SET_STRING_ELT(names, 1, Rf_mkChar("precision"));
  SET_STRING_ELT(names, 2, Rf_mkChar("scale"));
  SET_STRING_ELT(names, 3, Rf_mkChar("bits"));
  Rf_setAttrib(out, R_NamesSymbol, names);

  UNPROTECT(4);
  return out;
}

/* ---- decimal to Arrow ---------------------------------------------------- */

/* Writes the coefficient of `dec` at exponent `-scale` into `bytes` as a
 * `width`-byte two's-complement integer. Returns 0 on success, or 1 when the
 * value has more fractional digits than the scale, 2 when it has more digits
 * than the precision, and 3 when mpdecimal fails. */
static int decimal_arrow_encode_one(mpd_t *dec, const decimal_arrow_type *type,
                                    const mpd_context_t *ctx,
                                    unsigned char *bytes) {
  int width = type->bits / 8;
  int negative = mpd_isnegative(dec);
  uint16_t *words = NULL;
  uint32_t status = 0;
  size_t n_words;
  size_t k;

  /* Moving to a smaller exponent appends zeros and is exact; moving to a
   * larger one would round, which the status reports. */
  mpd_qrescale(dec, dec, -(mpd_ssize_t)type->scale, ctx, &status);
  if (status & MPD_Inexact) {
    return 1;
  }
  /* Dropping trailing zeros is exact but reported as rounded. */
  if (status & ~(uint32_t)(MPD_Rounded | MPD_Clamped)) {
    return 3;
  }
  if (dec->digits > type->precision) {
    return 2;
  }

  dec->exp = 0;
  mpd_set_positive(dec);
  n_words = mpd_qexport_u16(&words, 0, 65536, dec, &status);
  if (n_words == SIZE_MAX || status != 0) {
    if (words != NULL) {
      mpd_free(words);
    }
    return 3;
  }
  if (n_words > (size_t)width / 2) {
    mpd_free(words);
    return 2;
  }

  memset(bytes, 0, (size_t)width);
  for (k = 0; k < n_words; ++k) {
    bytes[2 * k] = (unsigned char)(words[k] & 0xff);
    bytes[2 * k + 1] = (unsigned char)(words[k] >> 8);
  }
  mpd_free(words);

  if (negative) {
    decimal_arrow_negate(bytes, width);
  }

  return 0;
}

static char *decimal_arrow_strdup(const char *s) {
  size_t n = strlen(s) + 1;
  char *copy = (char *)malloc(n);

  if (copy != NULL) {
    memcpy(copy, s, n);
  }

  return copy;
}

/* Builds an Arrow decimal array of the type `precision`, `scale` and `bits`
 * from canonical decimal strings, `NA` as a null. Returns the array handle,
 * whose tag is its schema handle. */
SEXP decimal_c_arrow_encode(SEXP x, SEXP precision, SEXP scale, SEXP bits) {
  decimal_arrow_type type;
  mpd_context_t ctx;
  R_xlen_t n;
  R_xlen_t i;
  R_xlen_t null_count = 0;
  int width;
  char format[64];
  SEXP values;
  SEXP validity;
  SEXP schema_xptr;
  SEXP array_xptr;
  SEXP cls;
  struct ArrowSchema *schema;
  struct ArrowArray *array;
  char *format_copy;
  char *name_copy;
  const void **buffers;
  void *value_buffer;
  void *validity_buffer = NULL;
  size_t value_bytes;
  size_t validity_bytes;

  if (TYPEOF(x) != STRSXP) {
    Rf_error("`x` must be a character vector");
  }
  if (TYPEOF(precision) != INTSXP || XLENGTH(precision) != 1 ||
      TYPEOF(scale) != INTSXP || XLENGTH(scale) != 1 ||
      TYPEOF(bits) != INTSXP || XLENGTH(bits) != 1 ||
      INTEGER(precision)[0] == NA_INTEGER ||
      INTEGER(scale)[0] == NA_INTEGER || INTEGER(bits)[0] == NA_INTEGER) {
    Rf_error("`precision`, `scale` and `bits` must be integer scalars");
  }

  type.precision = INTEGER(precision)[0];
  type.scale = INTEGER(scale)[0];
  type.bits = INTEGER(bits)[0];
  if (decimal_arrow_max_precision(type.bits) < 0) {
    Rf_error("`bits` must be 32, 64, 128 or 256");
  }
  if (type.precision < 1 ||
      type.precision > decimal_arrow_max_precision(type.bits)) {
    Rf_error("A %d-bit Arrow decimal cannot have precision %d", type.bits,
             type.precision);
  }

  if (type.bits == 128) {
    snprintf(format, sizeof(format), "d:%d,%d", type.precision, type.scale);
  } else {
    snprintf(format, sizeof(format), "d:%d,%d,%d", type.precision, type.scale,
             type.bits);
  }

  n = XLENGTH(x);
  width = type.bits / 8;
  value_bytes = (size_t)n * (size_t)width;
  validity_bytes = ((size_t)n + 7) / 8;
  mpd_maxcontext(&ctx);
  ctx.traps = 0;

  /* The buffers are filled in R memory first, so an interrupt or an error in
   * the loop leaks nothing. They are copied to C memory at the end, because
   * a consumer may release the array after R has collected the handle. */
  values = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t)value_bytes));
  validity = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t)validity_bytes));
  memset(RAW(values), 0, value_bytes);
  memset(RAW(validity), 0, validity_bytes);

  for (i = 0; i < n; ++i) {
    mpd_t *dec;
    uint32_t status = 0;
    int result;

    if (i % 1024 == 0) {
      R_CheckUserInterrupt();
    }

    if (STRING_ELT(x, i) == NA_STRING) {
      ++null_count;
      continue;
    }

    dec = mpd_qnew();
    if (dec == NULL) {
      Rf_error("mpdecimal allocation failure");
    }
    mpd_qset_string_exact(dec, CHAR(STRING_ELT(x, i)), &status);
    if (status != 0 || mpd_isspecial(dec)) {
      mpd_del(dec);
      Rf_error("Element %lld is not a finite decimal", (long long)i + 1);
    }

    result = decimal_arrow_encode_one(dec, &type, &ctx,
                                      RAW(values) + (size_t)i * width);
    mpd_del(dec);
    if (result == 1) {
      Rf_error("Element %lld has more fractional digits than scale %d",
               (long long)i + 1, type.scale);
    }
    if (result == 2) {
      Rf_error("Element %lld has more digits than precision %d",
               (long long)i + 1, type.precision);
    }
    if (result == 3) {
      Rf_error("mpdecimal failed to convert element %lld", (long long)i + 1);
    }

    RAW(validity)[i >> 3] |= (Rbyte)(1u << (i & 7));
  }

  /* The handles exist, empty, before any C memory does: from here to the
   * end nothing allocates on the R heap, so nothing can leak. */
  schema_xptr = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
  R_RegisterCFinalizer(schema_xptr, &decimal_arrow_finalize_schema);
  cls = PROTECT(Rf_mkString("nanoarrow_schema"));
  Rf_setAttrib(schema_xptr, R_ClassSymbol, cls);
  array_xptr = PROTECT(R_MakeExternalPtr(NULL, schema_xptr, R_NilValue));
  R_RegisterCFinalizer(array_xptr, &decimal_arrow_finalize_array);
  cls = PROTECT(Rf_mkString("nanoarrow_array"));
  Rf_setAttrib(array_xptr, R_ClassSymbol, cls);

  schema = (struct ArrowSchema *)malloc(sizeof(struct ArrowSchema));
  array = (struct ArrowArray *)malloc(sizeof(struct ArrowArray));
  format_copy = decimal_arrow_strdup(format);
  name_copy = decimal_arrow_strdup("");
  buffers = (const void **)malloc(2 * sizeof(void *));
  /* One byte at least, so an empty array still has a value buffer. */
  value_buffer = malloc(value_bytes == 0 ? 1 : value_bytes);
  if (null_count > 0) {
    validity_buffer = malloc(validity_bytes);
  }
  if (schema == NULL || array == NULL || format_copy == NULL ||
      name_copy == NULL || buffers == NULL || value_buffer == NULL ||
      (null_count > 0 && validity_buffer == NULL)) {
    free(schema);
    free(array);
    free(format_copy);
    free(name_copy);
    free((void *)buffers);
    free(value_buffer);
    free(validity_buffer);
    Rf_error("Unable to allocate an Arrow decimal array");
  }

  memcpy(value_buffer, RAW(values), value_bytes);
  if (validity_buffer != NULL) {
    memcpy(validity_buffer, RAW(validity), validity_bytes);
  }
  buffers[0] = validity_buffer;
  buffers[1] = value_buffer;

  schema->format = format_copy;
  schema->name = name_copy;
  schema->metadata = NULL;
  schema->flags = ARROW_FLAG_NULLABLE;
  schema->n_children = 0;
  schema->children = NULL;
  schema->dictionary = NULL;
  schema->release = &decimal_arrow_release_schema;
  schema->private_data = NULL;

  array->length = (int64_t)n;
  array->null_count = (int64_t)null_count;
  array->offset = 0;
  array->n_buffers = 2;
  array->n_children = 0;
  array->buffers = buffers;
  array->children = NULL;
  array->dictionary = NULL;
  array->release = &decimal_arrow_release_array;
  array->private_data = NULL;

  R_SetExternalPtrAddr(schema_xptr, schema);
  R_SetExternalPtrAddr(array_xptr, array);

  UNPROTECT(6);
  return array_xptr;
}
