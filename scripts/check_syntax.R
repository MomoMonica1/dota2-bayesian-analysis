#!/usr/bin/env Rscript
if (!file.exists("R/prepare_data.R")) stop("Run from the repository root")
for (path in list.files(c("R", "scripts", "tests"), pattern = "\\.R$", full.names = TRUE)) {
  parse(file = path)
  message("R syntax OK: ", path)
}
if (!requireNamespace("rstan", quietly = TRUE)) stop("Install rstan to validate Stan syntax")
for (path in list.files("stan", pattern = "\\.stan$", full.names = TRUE)) {
  result <- rstan::stanc(file = path)
  stopifnot(isTRUE(result$status))
  message("Stan syntax OK: ", path)
}
