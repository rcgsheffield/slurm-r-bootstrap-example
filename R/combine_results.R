# Reads every chunk .rds file produced by scripts/run_chunk.R and combines
# them into pointwise bootstrap summary statistics (mean, SE, 95% percentile
# CI) per grid point and per method.

# `output_dir` is the directory containing chunk_*.rds files; each one holds
# a list of per-replication results as returned by bootstrap_rep().
combine_results <- function(output_dir, pattern = "^chunk_[0-9]+\\.rds$") {
  files <- list.files(output_dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) {
    stop("No chunk files matching '", pattern, "' found in ", output_dir)
  }

  # Flatten the list-of-chunks-of-reps into one flat list of reps.
  all_reps <- unlist(lapply(files, readRDS), recursive = FALSE)

  methods <- c("xgboost", "ranger", "svm")

  # One row per (replication, method, grid point).
  long <- do.call(rbind, lapply(all_reps, function(r) {
    do.call(rbind, lapply(methods, function(m) {
      data.frame(
        rep = r$rep,
        seed = r$seed,
        method = m,
        grid_index = seq_along(r$preds[[m]]),
        pred = r$preds[[m]]
      )
    }))
  }))

  # Bootstrap SE = sd of the per-rep predictions at each grid point; CI via
  # the percentile method. n_reps is reported per group so a chunk that's
  # missing or still partial (see README on resubmitting incomplete chunks)
  # shows up as a lower rep count rather than silently biasing the summary.
  dplyr::summarise(
    dplyr::group_by(long, method, grid_index),
    mean = mean(pred),
    se = sd(pred),
    ci_lo = quantile(pred, 0.025),
    ci_hi = quantile(pred, 0.975),
    n_reps = dplyr::n(),
    .groups = "drop"
  )
}
