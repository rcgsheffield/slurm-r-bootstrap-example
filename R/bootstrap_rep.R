# Runs ONE bootstrap replication and returns its result. This is the unit
# of work that scripts/run_chunk.R loops over and saves incrementally.
#
# `seed` fully determines the replication (which rows get resampled): given
# the same seed and the same `data`, this function is deterministic. See
# scripts/run_chunk.R for how `seed` is derived from a replication's global
# index, and the README for the distinction between this resampling seed
# (sampling variability) and the internal randomness of ranger/xgboost
# (algorithmic variability), which this function does NOT separately fix.
bootstrap_rep <- function(rep_index, seed, data, grid) {
  set.seed(seed)
  idx <- sample.int(nrow(data), size = nrow(data), replace = TRUE)
  boot_data <- data[idx, , drop = FALSE]

  preds <- fit_models(boot_data, grid)

  list(rep = rep_index, seed = seed, preds = preds)
}
