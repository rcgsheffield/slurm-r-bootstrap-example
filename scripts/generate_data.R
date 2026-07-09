# Generates the toy dataset and evaluation grid ONCE, before submitting the
# array job. Every chunk (array task) reads these same two files and
# resamples rows from `original_data.rds` - so run this exactly once per
# experiment, not once per chunk.
#
# Usage:
#   Rscript scripts/generate_data.R [output_dir=output]

args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "output"

source("R/simulate_data.R")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

data <- simulate_data(seed = 42)
grid <- make_grid()

saveRDS(data, file.path(output_dir, "original_data.rds"))
saveRDS(grid, file.path(output_dir, "grid.rds"))

cat(sprintf(
  "Wrote %s/original_data.rds (%d rows) and %s/grid.rds (%d points)\n",
  output_dir, nrow(data), output_dir, nrow(grid)
))
