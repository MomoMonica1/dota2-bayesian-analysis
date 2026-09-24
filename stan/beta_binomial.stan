data {
  int<lower=1> N;
  array[N] int<lower=0> y;
  array[N] int<lower=0> n;
  real<lower=0> omega_a;
  real<lower=0> omega_b;
  real<lower=0> kappa_shape;
  real<lower=0> kappa_rate;
}
parameters {
  real<lower=0, upper=1> omega;
  real<lower=0> kappa;
}
transformed parameters {
  real<lower=0> alpha = omega * kappa + 1;
  real<lower=0> beta_shape = (1 - omega) * kappa + 1;
}
model {
  omega ~ beta(omega_a, omega_b);
  kappa ~ gamma(kappa_shape, kappa_rate);
  // Integrate out each player's theta instead of sampling N extra parameters.
  y ~ beta_binomial(n, alpha, beta_shape);
}
generated quantities {
  real population_mean = alpha / (alpha + beta_shape);
}
