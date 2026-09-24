# Methods, provenance, and interpretation

## Research questions

The original course project investigated observed win rates and their relationship with individual and team performance in Dota 2 Captain's Mode (`game_mode == 2`). Participation cohorts are based on **matches observed in the supplied dataset**. The labels “inexperienced” and “experienced” used in the original slides do not measure lifetime experience or skill.

## Models

### Hierarchical beta-binomial

For each unique eligible account, `y_i` is the number of wins out of `n_i` recorded matches. Separate models are fitted to 3–10 and >10 observed games:

```text
y_i | theta_i ~ Binomial(n_i, theta_i)
theta_i | omega, kappa ~ Beta(omega*kappa + 1, (1-omega)*kappa + 1)
population mean = (omega*kappa + 1) / (kappa + 2)
```

The Stan implementation marginalizes out `theta_i`, giving the equivalent beta-binomial likelihood. `omega` is the interior mode of the population beta distribution, not its mean; `kappa` here is the excess concentration above two. The generated `population_mean` avoids ambiguous labels and hand-built posterior arrays.

Baseline priors are `omega ~ Beta(1,1)` and `kappa ~ Gamma(0.1,0.1)` (shape, rate). The alternative uses `Beta(3,1)` and `Gamma(0.1,1.1)`, as intended in the notebook's sensitivity block. The same compiled model receives different hyperparameters for each run.

### Bayesian logistic regression

Player predictors: kills, deaths, assists, gold, summed teamfight damage, summed teamfight `xp_end`, and duration. Team predictors: Radiant–Dire differences in kills, gold, teamfight damage, and teamfight `xp_end`, plus duration. Each team model has one record per complete match. Each predictor is centered and scaled by its sample standard deviation, including duration.

```text
y_i ~ Bernoulli(inv_logit(intercept + X_i * beta))
intercept ~ Normal(0, intercept_scale)
beta_j ~ Normal(0, coefficient_scale)
```

| Model / prior | Intercept SD | Coefficient SD |
| --- | ---: | ---: |
| Player baseline | 2.5 | 2.5 |
| Player alternative | 1 | 1 |
| Team baseline | 1 | 0.5 |
| Team alternative | 2 | 2 |

The player baseline now has a proper weakly regularizing prior; the original baseline omitted explicit priors. This is an intentional modeling change. The alternative completes the notebook's malformed `normal(0, )` expression. Team prior scales follow the original model blocks.

## Historical findings

These values and interpretations are transcribed from [the original presentation](project-presentation.pdf), **not recomputed here**:

| Source | Reported finding |
| --- | --- |
| Slide 11 | 3–10 observed matches: posterior population mean 0.382, reported 95% credible interval (0.37, 0.39) |
| Slide 11 | >10 observed matches: posterior population mean 0.401, reported 95% credible interval (0.39, 0.41) |
| Slide 17 | Gold was the only individual coefficient whose reported 95% interval excluded zero |
| Slide 18 | Team-difference coefficients except duration had reported 95% intervals excluding zero |

The source's concluding claim of potential matchmaking unfairness should be treated cautiously. The notebook defects below may change the estimates and their uncertainty, and the historical raw data were not provided. Slide sample sizes are not asserted to be unique players because the original code retained one row per player-match while repeating each account's counts.

## Corrections in this repository

| Original issue | Organized implementation |
| --- | --- |
| Scalar `intToBits(...)[1]` did not decode each row's team bit | Vectorized bit mask 128 with valid-slot checks |
| Each account's binomial counts repeated across its match rows | One summary row per unique account |
| Joins could multiply records or rely on implicit keys | Explicit keys and uniqueness validation |
| Undefined `kappa_samples2` and inconsistent posterior variables | Population mean generated directly by Stan |
| Sensitivity fitting reused the baseline model string | Shared model receives the requested prior hyperparameters |
| Prior plots used a gamma distribution inconsistent with the model | No hand-generated prior plot presented as model evidence |
| Malformed prior and parameter-name mismatches | Valid prior parameters and feature-to-coefficient mapping |
| Team subtraction relied on row ordering and could use incomplete rosters | Explicit Radiant–Dire pairing after requiring ten identifiable, complete player records |
| Hard-coded coefficient tables mixed with computed output | Summaries written from each fitted model only |

The [original notebook](../archive/original-analysis.Rmd) is unchanged as a provenance artifact. Use the scripts, not the archive, as the runnable entry point. The archive retains the original errors and historical hard-coded values.

## What the models can and cannot establish

- End-of-match gold, kills, and other metrics are **associations with the same match's result**. They are unavailable before that match and do not constitute a pre-match prediction system.
- Player observations share matches, teams, and repeated accounts. The simple logistic likelihood does not model this dependence; coefficient uncertainty may be optimistic. The beta-binomial likelihood also treats accounts as conditionally independent despite shared matches.
- Filtering anonymous players and requiring complete identifiable teams changes the analyzed population and can introduce selection bias. Audit counts document the selection but do not remove that bias.
- Opposing players have complementary outcomes. An overall win rate, an account-weighted mean, and a selected-cohort mean answer different questions; departure from 0.5 alone is not a fairness test.
- Correlation among predictors complicates individual coefficient interpretation. A nonzero credible interval does not demonstrate causation or isolate the effect of teamwork.
- Dataset identity, version, sampling frame, and original results need verification with the actual input files before empirical claims are updated.

## Validation performed

R scripts were parsed, both Stan files passed `rstan::stanc`, and the independent synthetic preprocessing suite passed. The suite covers team decoding, unique-account counts, cohort boundaries, exclusions, pairing, duplicate rejection, missing inputs, and standardization. These checks validate program logic on controlled fixtures; no posterior estimates from the original data have been reproduced and no full research MCMC run is claimed.
