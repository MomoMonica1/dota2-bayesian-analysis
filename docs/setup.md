# Running the analysis

Use R 4.4 or later with `dplyr` and `rstan`. Syntax and preprocessing checks were run with R 4.4.3, dplyr 1.1.4, and rstan 2.32.7. A working C++ toolchain is needed for sampling; the setup script installs missing R packages but does not install system compilers. Package versions are not locked.

From the repository root:

```bash
Rscript scripts/install_dependencies.R
Rscript scripts/check_syntax.R
Rscript tests/test_prepare_data.R
```

The last two commands validate R/Stan syntax and synthetic preprocessing behavior. They do not fit or reproduce the research analysis.

## Supply data and inspect selection

Add the three inputs in [the data schema](../data/README.md), then run:

```bash
Rscript scripts/run_analysis.R --data-dir data --output-dir results --prepare-only
```

Inspect `results/data-audit.csv` before sampling. `prepared-data.rds` contains the selected rows and individual identifiers and remains local under the default Git ignore rules.

## Fit models

```bash
Rscript scripts/run_analysis.R --model all --prior both
# Or fit one family first:
Rscript scripts/run_analysis.R --model team --prior baseline --chains 4 --iter 4000 --warmup 2000 --seed 451
```

| Option | Values / default |
| --- | --- |
| `--data-dir` | Input directory; `data` |
| `--output-dir` | Output directory; `results` |
| `--prepare-only` | Validate and prepare without sampling |
| `--model` | `all`, `binomial`, `player`, `team`; `all` |
| `--prior` | `both`, `baseline`, `alternative`; `both` |
| `--chains` | `4` |
| `--iter` | Total iterations per chain, including warmup; `4000` |
| `--warmup` | `2000` |
| `--seed` | `451` |

`binomial` fits both participation cohorts. `both` runs each prior setting separately using its actual hyperparameters. Models fail clearly on empty cohorts, insufficient observations, or constant predictors rather than manufacturing estimates. Use a new output directory to retain earlier runs; repeated filenames are overwritten.

## Inspect outputs

Each fitted model writes `*-fit.rds`, `*-summary.csv`, `*-diagnostics.csv`, and `*-trace.pdf`. Summaries include 95% credible intervals, effective sample sizes, and R-hat. Logistic summaries map `beta[i]` to the saved feature names and save centering/scaling values in `*-scaling.csv`. Run configuration and session information are recorded alongside them.

Inspect chain mixing, R-hat, effective sample size, divergences, maximum-tree-depth hits, and energy diagnostics before interpreting estimates. A finished sampler is not evidence of convergence. `mean_fitted_probability` is an in-sample model summary, not predictive accuracy. No train/test evaluation, cross-validation, or causal identification is implemented.

Default iterations differ from the original notebook's two chains and 10,000 iterations (1,000 warmup). To request those settings, pass `--chains 2 --iter 10000 --warmup 1000`; this does not restore the original bugs or guarantee its reported numbers.
