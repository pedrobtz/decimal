# Arrow Decimal Types

Apache Arrow has exact decimal types — `decimal128(precision, scale)`
and `decimal256(precision, scale)` — and so does this package. They
agree on what a number *is*, so values can pass between them without
losing a digit. What they don’t share is a memory layout: Arrow packs a
decimal into a fixed-width integer, while a `decimal` vector stores text
and a shared scale
([`vignette("decimal-values")`](https://pedrobtz.github.io/decimal/dev/articles/decimal-values.md)).

The bridge between them is the **decimal string**. Both sides write and
read one exactly, which makes it a lossless interchange format, and the
package uses it in both directions for you. This vignette shows the
crossings and where the two type systems don’t quite line up.

``` r

library(decimal)
```

## A name collision to know about

`arrow` exports a
[`decimal()`](https://pedrobtz.github.io/decimal/dev/reference/decimal.md)
function of its own — it builds an Arrow *type*, not a vector — and
attaching `arrow` masks this package’s
[`decimal()`](https://pedrobtz.github.io/decimal/dev/reference/decimal.md):

``` r

library(arrow)
decimal(c("1.20", "2.30"))
#> Error: `precision` must be an integer
```

The masking runs whichever way you attach the two packages, so the
reliable fix is to qualify. This vignette never attaches `arrow`: every
Arrow function below is written `arrow::`, and decimal vectors are built
with
[`decimal::decimal()`](https://pedrobtz.github.io/decimal/dev/reference/decimal.md).
Adopting the same habit in a script that uses both packages will save
you a confusing error.

## From Arrow to decimal

Start with an Arrow array of exact decimals:

``` r

a <- arrow::Array$create(
  c("100.05", "99999999999999999999.99", "0.01")
)$cast(arrow::decimal128(25, 2))
a
#> Array
#> <decimal128(25, 2)>
#> [
#>   100.05,
#>   99999999999999999999.99,
#>   0.01
#> ]
```

The obvious move is [`as.vector()`](https://rdrr.io/r/base/vector.html).
Don’t — it converts through `double`:

``` r

format(as.vector(a), digits = 22)
#> [1] "1.000499999999999971578e+02" "1.000000000000000000000e+20"
#> [3] "1.000000000000000020817e-02"
```

The first value picked up a tail of garbage, and the second lost its
cents entirely: `99999999999999999999.99` came back as `1e+20`.
Twenty-two significant digits don’t fit in a double, which carries about
sixteen.

[`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
takes the array directly and keeps every digit:

``` r

as_decimal(a)
#> <decimal[3]>
#> [1] 100.05                  99999999999999999999.99 0.01
```

No `double` is involved. Arrow casts the column to text in its own exact
arithmetic, and that text is already the canonical form a `decimal`
vector stores, so the values move across without being re-parsed. That
makes the exact path about as fast as the lossy one.

### Scale comes along for free

An Arrow decimal type carries its own scale, and
[`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
reads it off the type rather than guessing from the text. That matters
when a column happens to hold only whole numbers — the declared cents
survive anyway:

``` r

whole <- arrow::Array$create(c("1", "2"))$cast(arrow::decimal128(9, 2))
as_decimal(whole)
#> <decimal[2]>
#> [1] 1.00 2.00
attr(as_decimal(whole), "scale")
#> [1] 2
```

Passing `scale` overrides the type, rescaling as usual — exactly when
the scale grows, and by quantizing under the active
[`decimal_context()`](https://pedrobtz.github.io/decimal/dev/reference/decimal_context.md)
when it shrinks:

``` r

as_decimal(a, scale = 4)
#> <decimal[3]>
#> [1] 100.0500                  99999999999999999999.9900
#> [3] 0.0100
```

### Nulls become `NA`

``` r

as_decimal(arrow::Array$create(c("1.50", NA, "2.25"))$cast(arrow::decimal128(9, 2)))
#> <decimal[3]>
#> [1] 1.50 <NA> 2.25
```

### Chunked arrays work the same way

A column read from Parquet or a dataset is usually a `ChunkedArray`
rather than an `Array`. It has its own
[`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
method, so no per-chunk bookkeeping is needed:

``` r

cs <- arrow::ChunkedArray$create(
  arrow::Array$create(c("1.25", "2.50"))$cast(arrow::decimal128(9, 2)),
  arrow::Array$create("3.75")$cast(arrow::decimal128(9, 2))
)
cs$num_chunks
#> [1] 2
as_decimal(cs)
#> <decimal[3]>
#> [1] 1.25 2.50 3.75
```

### Integer columns

An Arrow integer column converts exactly too, at every width, because
the values cross as text rather than through `double`. An `int64` value
beyond 2^53, which a double cannot hold, arrives intact:

``` r

as_decimal(arrow::Array$create("9007199254740993")$cast(arrow::int64()))
#> <decimal[1]>
#> [1] 9007199254740993
```

## From decimal to Arrow

A `decimal` vector converts to Arrow on its own, so it becomes a decimal
field wherever arrow infers types —
[`arrow::arrow_table()`](https://arrow.apache.org/docs/r/reference/table.html),
[`arrow::write_parquet()`](https://arrow.apache.org/docs/r/reference/write_parquet.html),
[`arrow::write_dataset()`](https://arrow.apache.org/docs/r/reference/write_dataset.html):

``` r

x <- decimal::decimal(c("1.25", "2.50", "-3.75"))
a <- arrow::as_arrow_array(x)
a$type
#> DecimalExtensionType
#> decimal<decimal128(3, 2)>
```

The type is an Arrow *extension type*. Its storage is a real
`decimal128`, with the vector’s own scale and a precision inferred from
the values present: the widest one here needs three digits, one before
the point and two after. The storage is what a file carries, so Spark,
DuckDB, pandas and every other reader see an ordinary decimal column.
The extension name is what lets arrow hand the column back to this
package on the way in, so in R it returns as a `decimal` vector on every
read path,
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) included:

``` r

as.vector(a)
#> <decimal[3]>
#> [1] 1.25  2.50  -3.75
```

### Pinning the type

A tight precision derived from today’s data may not fit tomorrow’s, so
for a column you’ll append to, pin a wider type.
[`arrow_decimal_type()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_decimal_type.md)
builds the extension type with the precision and scale you choose:

``` r

arrow::as_arrow_array(x, type = arrow_decimal_type(20, 2))$type
#> DecimalExtensionType
#> decimal<decimal128(20, 2)>
```

Passing a plain Arrow decimal type instead gives exactly that type, with
no extension:

``` r

arrow::as_arrow_array(x, type = arrow::decimal128(20, 2))$type
#> Decimal128Type
#> decimal128(20, 2)
```

Either way, Arrow refuses a cast that wouldn’t fit rather than rounding
silently:

``` r

arrow::as_arrow_array(x, type = arrow::decimal128(2, 2))
#> Error:
#> ! Invalid: Decimal value does not fit in precision 2
```

### Plain fields, and when you want one

Arrow’s compute engine does not operate on extension columns. A
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
or [`summarise()`](https://dplyr.tidyverse.org/reference/summarise.html)
evaluated inside arrow on the decimal column itself fails with “no
kernel matching input types”, while selecting, collecting, and filtering
on other columns work as usual. If you need arrow-side arithmetic on the
column, write it as a plain field: pass a plain type as above, or turn
the extension type off for every conversion:

``` r

options(decimal.arrow_extension = FALSE)
```

The price of a plain field is the trip back. Arrow records an R column’s
attributes in the schema and reapplies them blindly on read, so
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) on a
table built from a plain decimal field returns the double arrow
produced, wearing the `decimal` class. This package refuses to format
such an object rather than print rounded values. Read those tables with
[`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md),
described below, or drop the recorded attributes first with
`tab$ReplaceSchemaMetadata(NULL)`.

## Whole tables and Parquet files

A data frame with a decimal column becomes a table with a decimal field,
and comes back the same way:

``` r

tab <- arrow::arrow_table(
  id = 1:3,
  amount = decimal::decimal(c("100.05", "0.01", "12.30"))
)
tab$schema$GetFieldByName("amount")$type$ToString()
#> [1] "decimal<decimal128(5, 2)>"
tibble::as_tibble(as.data.frame(tab))
#> # A tibble: 3 × 2
#>      id amount
#>   <int>  <dec>
#> 1     1 100.05
#> 2     2   0.01
#> 3     3  12.30
```

A tibble is used here because pillar prints the column’s type, which
makes it easy to confirm the decimal survived the crossing.

Parquet preserves the Arrow type, so a file written with a decimal
column reads back as one, whether you take the data frame or the table:

``` r

path <- tempfile(fileext = ".parquet")
arrow::write_parquet(tab, path)
arrow::read_parquet(path)$amount
#> <decimal[3]>
#> [1] 100.05 0.01   12.30

t2 <- arrow::read_parquet(path, as_data_frame = FALSE)
t2$schema$GetFieldByName("amount")$type$ToString()
#> [1] "decimal<decimal128(5, 2)>"
as_decimal(t2$amount)
#> <decimal[3]>
#> [1] 100.05 0.01   12.30
```

### Decimal columns written elsewhere

A Parquet file from Spark, DuckDB or pandas carries plain decimal fields
with no extension name, and
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) converts
those to `double`.
[`arrow_as_data_frame()`](https://pedrobtz.github.io/decimal/dev/reference/arrow_as_data_frame.md)
converts the decimal fields with
[`as_decimal()`](https://pedrobtz.github.io/decimal/dev/reference/as_decimal.md)
instead, each with the scale its type declares, and leaves every other
column to arrow:

``` r

foreign <- arrow::arrow_table(
  id = 1:2,
  amount = arrow::Array$create(
    c("100.05", "99999999999999999999.99")
  )$cast(arrow::decimal128(25, 2))
)
tibble::as_tibble(arrow_as_data_frame(foreign))
#> # A tibble: 2 × 2
#>      id                  amount
#>   <int>                   <dec>
#> 1     1                  100.05
#> 2     2 99999999999999999999.99
```

To find the decimal fields in a schema you didn’t write, check the field
types:

``` r

types <- vapply(foreign$schema$fields, function(f) f$type$ToString(), character(1))
names(foreign)[grepl("^decimal", types)]
#> [1] "amount"
```

## Where the two type systems differ

Arrow’s decimals are fixed-width integers with a scale, which makes them
narrower than a `decimal` vector in two ways worth planning around.

**Infinity and NaN have no Arrow decimal.** A `decimal` vector holds
them happily; the conversion reports which element it cannot represent
rather than inventing a value:

``` r

arrow::as_arrow_array(decimal::decimal(c("1.50", "NaN")))
#> Error in `decimal_arrow_check_representable()`:
#> ! Arrow decimal types cannot represent infinities or NaNs; element 2 is `NaN`.
```

If a column can contain them, keep it as a string in Arrow, or map them
to `NA` before converting.

**Precision is capped.**
[`arrow::decimal128()`](https://arrow.apache.org/docs/r/reference/data-type.html)
allows at most 38 digits and
[`arrow::decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html)
at most 76; a `decimal` vector has no such limit. The type is chosen for
you —
[`decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html)
when the values need it, an error when even that is too narrow:

``` r

big <- decimal::decimal(
  c("12345678901234567890.12345678", "0.10000000000000000001"),
  scale = 20
)
arrow::infer_type(big)
#> DecimalExtensionType
#> decimal<decimal256(40, 20)>
```

``` r

arrow::infer_type(decimal::decimal(strrep("9", 90)))
#> Error in `decimal_arrow_storage_type()`:
#> ! `x` needs 90 digits of precision, more than the 76 digits `arrow::decimal256()` allows. Cast to `arrow::string()` instead, or reduce the scale.
```

Read back through `double`, those two wide values would have been
`12345678901234567168` and `0.10000000000000000555` — the first wrong
from its seventeenth digit, the second not 0.1 at all. Through Arrow’s
decimal type, they’re exact:

``` r

as_decimal(arrow::as_arrow_array(big))
#> <decimal[2]>
#> [1] 12345678901234567890.12345678000000000000
#> [2] 0.10000000000000000001
```
