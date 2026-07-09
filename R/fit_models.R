# Fits the three ML methods used to estimate the function of interest, and
# evaluates each fitted model at `grid`.
#
# This is the file Rowan should replace with his own estimator(s). The
# contract the rest of the pipeline relies on: `fit_models(train_data, grid)`
# takes a data.frame with columns x/y (the resampled training data) and a
# data.frame with column x (the evaluation grid), and returns a named list
# of numeric vectors, one per method, each of length nrow(grid) and in the
# same row order as `grid`.

fit_models <- function(train_data, grid) {
  list(
    xgboost = fit_xgboost(train_data, grid),
    ranger  = fit_ranger(train_data, grid),
    svm     = fit_svm(train_data, grid)
  )
}

# xgboost wants a numeric matrix, not a data.frame - as.matrix() on a
# single-column data.frame keeps the column name, so training and
# prediction data line up consistently.
#
# nthread = 1: multi-threaded xgboost is not exactly reproducible even with
# a fixed seed (thread scheduling affects floating-point summation order),
# and this also matches --cpus-per-task=1 in the SLURM scripts.
#
# x/y, learning_rate, verbosity: xgboost >= 2.0's xgboost() interface renamed
# data/label/eta/verbose - these names avoid the deprecation warnings (which
# become errors in future xgboost releases).
fit_xgboost <- function(train_data, grid) {
  fit <- xgboost::xgboost(
    x = as.matrix(train_data["x"]),
    y = train_data$y,
    nrounds = 50,
    max_depth = 3,
    learning_rate = 0.3,
    objective = "reg:squarederror",
    nthread = 1,
    verbosity = 0
  )
  predict(fit, as.matrix(grid["x"]))
}

# predict.ranger() returns a list (it can also carry e.g. per-tree
# predictions), so the point predictions must be pulled out via $predictions.
fit_ranger <- function(train_data, grid) {
  fit <- ranger::ranger(y ~ x, data = train_data, num.trees = 200, num.threads = 1)
  predict(fit, data = grid)$predictions
}

# type = "eps-regression" is already the default e1071::svm() picks for a
# numeric response, but it's set explicitly here for clarity since the
# whole point of this function is a template someone else will read.
#
# unname(): predict.svm() carries over row names from `newdata`, which
# would otherwise attach mismatched names when the result is combined with
# other methods' predictions downstream.
fit_svm <- function(train_data, grid) {
  fit <- e1071::svm(y ~ x, data = train_data, type = "eps-regression", kernel = "radial")
  unname(predict(fit, newdata = grid))
}
