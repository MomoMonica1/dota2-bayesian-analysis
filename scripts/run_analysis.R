#!/usr/bin/env Rscript
# Run from the repository root; see docs/setup.md for all options.
args <- commandArgs(trailingOnly = TRUE)
config <- list(data_dir = "data", output_dir = "results", model = "all", prior = "both",
               chains = 4L, iter = 4000L, warmup = 2000L, seed = 451L,
               prepare_only = FALSE)
i <- 1L
while (i <= length(args)) {
  key <- gsub("-", "_", sub("^--", "", args[i]))
  if (!startsWith(args[i], "--") || !key %in% names(config)) stop("Unknown option: ", args[i])
  if (key == "prepare_only") {
    config[[key]] <- TRUE
    i <- i + 1L
  } else {
    if (i == length(args)) stop("Missing value for ", args[i])
    config[[key]] <- args[i + 1L]
    i <- i + 2L
  }
}
for (key in c("chains", "iter", "warmup", "seed")) {
  value <- suppressWarnings(as.numeric(config[[key]]))
  if (length(value) != 1 || !is.finite(value) || value < 0 || value != floor(value) || value > .Machine$integer.max) {
    stop("--", key, " must be a nonnegative integer")
  }
  config[[key]] <- as.integer(value)
}
if (config$chains < 1 || config$iter <= config$warmup) stop("Require chains >= 1 and iter > warmup")
if (!config$model %in% c("all", "binomial", "player", "team")) stop("--model: all, binomial, player, or team")
if (!config$prior %in% c("both", "baseline", "alternative")) stop("--prior: both, baseline, or alternative")
if (!file.exists("R/prepare_data.R")) stop("Run this script from the repository root")
source("R/prepare_data.R")
prepared <- prepare_data(config$data_dir)
dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(prepared$audit, file.path(config$output_dir, "data-audit.csv"), row.names = FALSE)
saveRDS(prepared, file.path(config$output_dir, "prepared-data.rds"))
print(prepared$audit, row.names = FALSE)
if (config$prepare_only) quit(status = 0)
if (!requireNamespace("rstan", quietly = TRUE)) stop("Install rstan: Rscript scripts/install_dependencies.R")
options(mc.cores = min(config$chains, parallel::detectCores()))
rstan::rstan_options(auto_write = FALSE)
capture.output(config, file = file.path(config$output_dir, "run-config.txt"))
capture.output(sessionInfo(), file = file.path(config$output_dir, "session-info.txt"))
priors <- if (config$prior == "both") c("baseline", "alternative") else config$prior
models <- if (config$model == "all") c("binomial", "player", "team") else config$model

save_fit <- function(model, data, label, parameters, labels = parameters) {
  message("Sampling ", label)
  fit <- rstan::sampling(model, data = data, chains = config$chains, iter = config$iter,
                          warmup = config$warmup, seed = config$seed,
                          control = list(adapt_delta = 0.95, max_treedepth = 12))
  prefix <- file.path(config$output_dir, label)
  saveRDS(fit, paste0(prefix, "-fit.rds"))
  tab <- as.data.frame(summary(fit, pars = parameters, probs = c(0.025, 0.5, 0.975))$summary)
  tab <- data.frame(parameter = labels[match(rownames(tab), parameters)],
                    stan_parameter = rownames(tab), tab, row.names = NULL, check.names = FALSE)
  utils::write.csv(tab, paste0(prefix, "-summary.csv"), row.names = FALSE)
  sampler <- rstan::get_sampler_params(fit, inc_warmup = FALSE)
  diagnostic <- do.call(rbind, lapply(seq_along(sampler), function(chain) {
    s <- sampler[[chain]]
    data.frame(chain = chain, divergences = sum(s[, "divergent__"]),
               max_treedepth_hits = sum(s[, "treedepth__"] >= 12),
               ebfmi = mean(diff(s[, "energy__"])^2) / stats::var(s[, "energy__"]))
  }))
  utils::write.csv(diagnostic, paste0(prefix, "-diagnostics.csv"), row.names = FALSE)
  grDevices::pdf(paste0(prefix, "-trace.pdf"), width = 10, height = 8)
  print(rstan::traceplot(fit, pars = parameters))
  grDevices::dev.off()
  invisible(fit)
}

if ("binomial" %in% models) {
  model <- rstan::stan_model(file = "stan/beta_binomial.stan")
  for (prior in priors) {
    hyper <- if (prior == "baseline") c(1, 1, 0.1, 0.1) else c(3, 1, 0.1, 1.1)
    for (cohort in c("3_to_10", "over_10")) {
      data <- make_binomial_data(prepared$player_counts, cohort,
                                 hyper[1], hyper[2], hyper[3], hyper[4])
      save_fit(model, data, paste("binomial", cohort, prior, sep = "-"),
                c("omega", "kappa", "population_mean"))
    }
  }
}
if (any(c("player", "team") %in% models)) {
  model <- rstan::stan_model(file = "stan/logistic.stan")
  for (level in intersect(c("player", "team"), models)) {
    features <- if (level == "player") {
      c("kills", "deaths", "assists", "gold", "teamfight_damage", "teamfight_xp_end", "duration")
    } else {
      c("diff_kills", "diff_gold", "diff_teamfight_damage", "diff_teamfight_xp", "duration")
    }
    rows <- prepared[[paste0(level, "_matches")]]
    for (prior in priors) {
      scales <- if (level == "player") {
        if (prior == "baseline") c(2.5, 2.5) else c(1, 1)
      } else {
        if (prior == "baseline") c(0.5, 1) else c(2, 2)
      }
      input <- make_logistic_data(rows, features, scales[1], scales[2])
      label <- paste(level, prior, sep = "-")
      utils::write.csv(input$scaling, file.path(config$output_dir, paste0(label, "-scaling.csv")), row.names = FALSE)
      parameters <- c("intercept", paste0("beta[", seq_along(features), "]"), "mean_fitted_probability")
      save_fit(model, input$stan, label, parameters, c("intercept", features, "mean_fitted_probability"))
    }
  }
}
message("Finished. Review diagnostics and trace plots before interpreting estimates.")
