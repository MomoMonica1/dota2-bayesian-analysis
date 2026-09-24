data {
  int<lower=1> N;
  int<lower=1> K;
  matrix[N, K] X;
  array[N] int<lower=0, upper=1> y;
  real<lower=0> coefficient_scale;
  real<lower=0> intercept_scale;
}
parameters {
  real intercept;
  vector[K] beta;
}
model {
  intercept ~ normal(0, intercept_scale);
  beta ~ normal(0, coefficient_scale);
  y ~ bernoulli_logit(intercept + X * beta);
}
generated quantities {
  real mean_fitted_probability = mean(inv_logit(intercept + X * beta));
}
