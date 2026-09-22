# Arrow Decimal Types

Apache Arrow has exact decimal types — `decimal128(precision, scale)`
and `decimal256(precision, scale)` — and so does this package. They
agree on what a number *is*, so values can pass between them without
losing a digit. What they don’t share is a memory layout: Arrow packs a
decimal into a fixed-width integer, while a `decimal` vector stores text
and a shared scale
([`vignette("decimal-values")`](https://pedrobtz.github.io/decimal/articles/decimal-values.md)).

The bridge between them is the **decimal string**. Both sides can write
one and read one exactly, which makes it a lossless interchange format.
This vignette shows how to cross in both directions, and where the two
type systems don’t quite line up.

``` r

library(decimal)
```

## A name collision to know about

`arrow` exports a
[`decimal()`](https://pedrobtz.github.io/decimal/reference/decimal.md)
function of its own — it builds an Arrow *type*, not a vector — and
attaching `arrow` masks this package’s
[`decimal()`](https://pedrobtz.github.io/decimal/reference/decimal.md):

``` r

library(arrow)
decimal(c("1.20", "2.30"))
#> Error: `precision` must be an integer
```

The masking runs whichever way you attach the two packages, so the
reliable fix is to qualify. This vignette never attaches `arrow`: every
Arrow function below is written `arrow::`, and decimal vectors are built
with
[`decimal::decimal()`](https://pedrobtz.github.io/decimal/reference/decimal.md).
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

Cast to
[`arrow::string()`](https://arrow.apache.org/docs/r/reference/data-type.html)
first, then build the decimal vector:

``` r

decimal::decimal(as.vector(a$cast(arrow::string())))
#> <decimal[3]>
#> [1] 100.05                  99999999999999999999.99 0.01
```

Every digit survives. The cast to string happens inside Arrow, in exact
arithmetic, and
[`decimal::decimal()`](https://pedrobtz.github.io/decimal/reference/decimal.md)
parses the text exactly — so `double` never enters the picture.

### Scale comes along for free

An Arrow decimal type carries its own scale, and the string cast pads
every value to it. That means the resulting vector’s scale already
matches the source column, with nothing for you to specify:

``` r

a$type$scale()
#> [1] 2
attr(decimal::decimal(as.vector(a$cast(arrow::string()))), "scale")
#> [1] 2
```

If you’d rather be explicit — or you want to pin the scale even when a
chunk happens to contain only whole numbers — read it off the type and
pass it along:

``` r

decimal::decimal(
  as.vector(a$cast(arrow::string())),
  scale = a$type$scale()
)
#> <decimal[3]>
#> [1] 100.05                  99999999999999999999.99 0.01
```

### Nulls become `NA`

Arrow’s nulls survive the string cast as `NA`, and land as missing
decimals:

``` r

b <- arrow::Array$create(c("1.50", NA, "2.25"))$cast(arrow::decimal128(9, 2))
decimal::decimal(as.vector(b$cast(arrow::string())))
#> <decimal[3]>
#> [1] 1.50 <NA> 2.25
```

### Chunked arrays work the same way

A column read from Parquet or a dataset is usually a `ChunkedArray`
rather than an `Array`. It casts the same way, and
[`as.vector()`](https://rdrr.io/r/base/vector.html) flattens the chunks
into one character vector, so no per-chunk bookkeeping is needed:

``` r

cs <- arrow::ChunkedArray$create(
  arrow::Array$create(c("1.25", "2.50"))$cast(arrow::decimal128(9, 2)),
  arrow::Array$create("3.75")$cast(arrow::decimal128(9, 2))
)
cs$num_chunks
#> [1] 2
decimal::decimal(as.vector(cs$cast(arrow::string())))
#> <decimal[3]>
#> [1] 1.25 2.50 3.75
```

## From decimal to Arrow

Going the other way, write the vector out with
[`as.character()`](https://rdrr.io/r/base/character.html) and let Arrow
parse the strings into the decimal type you want:

``` r

x <- decimal::decimal(c("1.25", "2.50", "-3.75"))
arrow::Array$create(as.character(x))$cast(arrow::decimal128(12, 2))
#> Array
#> <decimal128(12, 2)>
#> [
#>   1.25,
#>   2.50,
#>   -3.75
#> ]
```

The scale to ask for is the vector’s own, `attr(x, "scale")`. Precision
is the decision you have to make: it’s the total number of digits,
integer part included, and Arrow refuses a cast that wouldn’t fit rather
than rounding silently:

``` r

arrow::Array$create("12345.67")$cast(arrow::decimal128(4, 2))
#> Error:
#> ! Invalid: Decimal value does not fit in precision 4
```

Counting the digits actually present gives you the tightest type that
works:

``` r

decimal_precision <- function(x) {
  s <- as.character(x)
  s <- s[!is.na(s)]
  if (!length(s)) {
    return(1L)
  }
  s <- sub("^-", "", s)
  s <- gsub("[.]", "", s)
  max(nchar(s), 1L)
}

y <- decimal::decimal(c("1.25", "-12345.50"))
decimal_precision(y)
#> [1] 7
```

A fixed, generous precision is often the better choice for a column
you’ll append to later — a tight one derived from today’s data may not
fit tomorrow’s.

## A reusable pair

Putting both directions together:

``` r

from_arrow_decimal <- function(x) {
  decimal::decimal(
    as.vector(x$cast(arrow::string())),
    scale = x$type$scale()
  )
}

to_arrow_decimal <- function(x, precision = decimal_precision(x)) {
  arrow::Array$create(as.character(x))$cast(
    arrow::decimal128(precision, attr(x, "scale"))
  )
}
```

They round-trip, missing values and all:

``` r

z <- decimal::decimal(c("0.01", "999.99", NA))
identical(as.character(from_arrow_decimal(to_arrow_decimal(z))), as.character(z))
#> [1] TRUE
```

## Whole tables and Parquet files

The same rule governs tables:
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) on an
Arrow table converts decimal columns to `double`, so pull the decimal
columns across yourself.

``` r

tab <- arrow::arrow_table(
  id = arrow::Array$create(1:3),
  amount = arrow::Array$create(
    c("100.05", "0.01", "12.30")
  )$cast(arrow::decimal128(25, 2))
)

out <- tibble::tibble(
  id = as.vector(tab$id),
  amount = from_arrow_decimal(tab$amount)
)
out
#> # A tibble: 3 × 2
#>      id amount
#>   <int>  <dec>
#> 1     1 100.05
#> 2     2   0.01
#> 3     3  12.30
```

A base `data.frame` works too; a tibble is used here because pillar
prints the column’s type, which makes it easy to confirm the decimal
survived the crossing.

Parquet preserves the Arrow type, so a file written with a decimal
column reads back as one and crosses over the same way:

``` r

path <- tempfile(fileext = ".parquet")
arrow::write_parquet(tab, path)

t2 <- arrow::read_parquet(path, as_data_frame = FALSE)
t2$schema$GetFieldByName("amount")$type$ToString()
#> [1] "decimal128(25, 2)"
from_arrow_decimal(t2$amount)
#> <decimal[3]>
#> [1] 100.05 0.01   12.30
```

To find the decimal columns in a schema you didn’t write, check the
field types:

``` r

types <- vapply(tab$schema$fields, function(f) f$type$ToString(), character(1))
names(tab)[grepl("^decimal", types)]
#> [1] "amount"
```

## Where the two type systems differ

Arrow’s decimals are fixed-width integers with a scale, which makes them
narrower than a `decimal` vector in two ways worth planning around.

**Infinity and NaN have no Arrow decimal.** A `decimal` vector holds
them happily, but the cast fails rather than inventing a value:

``` r

arrow::Array$create(
  as.character(decimal::decimal(c("1.50", "NaN")))
)$cast(arrow::decimal128(9, 2))
#> Error:
#> ! Invalid: The string 'NaN' is not a valid decimal128 number
```

If a column can contain them, either keep it as a string in Arrow or map
them to nulls before casting.

**Precision is capped.**
[`arrow::decimal128()`](https://arrow.apache.org/docs/r/reference/data-type.html)
allows at most 38 digits and
[`arrow::decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html)
at most 76; a `decimal` vector has no such limit. Use
[`decimal256()`](https://arrow.apache.org/docs/r/reference/data-type.html)
for very wide values:

``` r

big <- arrow::Array$create(
  c("12345678901234567890.12345678", "0.10000000000000000001")
)$cast(arrow::decimal256(50, 20))
from_arrow_decimal(big)
#> <decimal[2]>
#> [1] 12345678901234567890.12345678000000000000
#> [2] 0.10000000000000000001
```

Read back through `double`, those two values would have been
`12345678901234567168` and `0.10000000000000000555` — the first wrong
from its seventeenth digit, the second not 0.1 at all. Through the
string, they’re exact.
