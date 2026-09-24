#!/usr/bin/env Rscript
packages <- c("dplyr", "rstan")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
message("R packages available. Compiling Stan additionally requires a working C++ toolchain.")
