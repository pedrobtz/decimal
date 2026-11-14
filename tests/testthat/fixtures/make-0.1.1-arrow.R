# Builds the Arrow files that test-arrow.R reads to check that data written
# by the released decimal 0.1.1, whose `r.decimal` extension type carries
# empty extension metadata, still reads back exactly.
#
# Run from the package root with the released 0.1.1 installed into a library
# of its own, so the files come from that release rather than the source tree:
#
#   lib <- tempfile("lib")
#   dir.create(lib)
#   install.packages("decimal", lib = lib, repos = "https://cloud.r-project.org")
#   Sys.setenv(DECIMAL_FIXTURE_LIB = lib)
#   Rscript tests/testthat/fixtures/make-0.1.1-arrow.R
#
# The fixtures in this directory were made with decimal 0.1.1 and arrow 26.0.0.

lib <- Sys.getenv("DECIMAL_FIXTURE_LIB")
stopifnot(nzchar(lib))
library(decimal, lib.loc = lib)
stopifnot(packageVersion("decimal", lib.loc = lib) == "0.1.1")

df <- data.frame(id = 1:3)
df$amount <- decimal(c("100.05", NA, "-99999999999999999999.99"))
df$rate <- decimal(c("0.0350", "1.2500", NA))
df$wide <- decimal(c(paste0(strrep("9", 45), ".5"), "-0.1", NA))

dir <- file.path("tests", "testthat", "fixtures")
arrow::write_parquet(df, file.path(dir, "decimal-0.1.1.parquet"))
arrow::write_ipc_file(df, file.path(dir, "decimal-0.1.1.arrow"))
