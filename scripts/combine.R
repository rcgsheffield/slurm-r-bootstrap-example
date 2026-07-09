# Combines every chunk's .rds output into one summary data.frame of
# pointwise bootstrap mean/SE/CI per method, and writes it to disk.
#
# Usage:
#   Rscript scripts/combine.R [output_dir=output] [out_prefix=results/combined_results]

args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "output"
out_prefix <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "results/combined_results"

source("R/combine_results.R")

dir.create(dirname(out_prefix), recursive = TRUE, showWarnings = FALSE)

summary_df <- combine_results(output_dir)

saveRDS(summary_df, paste0(out_prefix, ".rds"))
write.csv(summary_df, paste0(out_prefix, ".csv"), row.names = FALSE)

cat(sprintf("Wrote %s.rds and %s.csv (%d rows)\n", out_prefix, out_prefix, nrow(summary_df)))
