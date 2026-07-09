# Toy data-generating process for the bootstrap example.
#
# Everything here is a stand-in for Rowan's real estimator: a single
# predictor `x`, a nonlinear `true_function`, and Gaussian noise. Swap in
# your own simulation (or real dataset) but keep the same interface -
# `simulate_data()` returning a data.frame(x, y), and `make_grid()`
# returning the data.frame of points at which the estimated function is
# evaluated in every bootstrap replication.

# Nonlinear on purpose: a straight line would make boosting/RF/SVM
# approximate it near-identically, which defeats the point of a demo that
# compares three different ML methods.
true_function <- function(x) {
  sin(x) + 0.5 * x * cos(2 * x)
}

# Simulate one toy dataset. This is called ONCE (see scripts/generate_data.R)
# and the resulting data.frame is saved to disk - every bootstrap chunk then
# resamples rows from that SAME saved dataset. If each chunk instead called
# simulate_data() itself, chunks would be bootstrapping different underlying
# datasets, which is not what a bootstrap standard error is supposed to
# measure.
simulate_data <- function(n = 200, x_range = c(-3, 3), noise_sd = 0.3, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  x <- runif(n, x_range[1], x_range[2])
  y <- true_function(x) + rnorm(n, sd = noise_sd)
  data.frame(x = x, y = y)
}

# Fixed grid of x-values at which every method's fitted function is
# evaluated in every replication. Kept small (default 50 points) so the
# per-replication cost of prediction is negligible next to model fitting.
#
# Returned as a data.frame (not a bare numeric vector) because ranger,
# xgboost, and e1071::svm all expect newdata with a matching column name
# ("x") at predict time.
#
# Extending to more than one predictor: hold all but one predictor fixed
# (e.g. at its mean/median) and vary only the predictor of interest across
# the grid, or evaluate the grid over a 2D mesh if you need a full surface.
make_grid <- function(x_range = c(-3, 3), n_grid = 50) {
  data.frame(x = seq(x_range[1], x_range[2], length.out = n_grid))
}
