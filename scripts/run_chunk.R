# Runs one CHUNK of bootstrap replications and is the script each SLURM
# array task calls. A chunk is a contiguous block of global replication
# indices; splitting 1000 total replications into e.g. 50 chunks of 20 is
# what keeps any single job's runtime well under the 96h walltime limit
# (see slurm/array_job.sh and the README).
#
# Usage:
#   Rscript scripts/run_chunk.R <chunk_index> [reps_per_chunk=20] [base_seed=1000000] [output_dir=output] [data_dir=output]
#
# <chunk_index> is 1-based and normally comes from $SLURM_ARRAY_TASK_ID.
#
# Crash/timeout safety: this script saves its results after EVERY single
# replication, not just at the end. If the job is killed partway through
# (e.g. it hits the walltime limit), everything completed up to that point
# is already on disk. Re-running the same chunk_index afterwards picks up
# where it left off instead of redoing finished work - see the "resume"
# block below.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(i, default) if (length(args) >= i && nzchar(args[i])) args[i] else default

if (length(args) < 1) stop("Usage: Rscript run_chunk.R <chunk_index> [reps_per_chunk] [base_seed] [output_dir] [data_dir]")

chunk_index    <- as.integer(get_arg(1, NA))
reps_per_chunk <- as.integer(get_arg(2, 20))
base_seed      <- as.integer(get_arg(3, 1000000))
output_dir     <- get_arg(4, "output")
data_dir       <- get_arg(5, output_dir)

source("R/simulate_data.R")
source("R/fit_models.R")
source("R/bootstrap_rep.R")

data <- readRDS(file.path(data_dir, "original_data.rds"))
grid <- readRDS(file.path(data_dir, "grid.rds"))

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# global_rep_index = (chunk - 1) * reps_per_chunk + local position within
# the chunk. Combined with base_seed, this means every replication's seed
# depends only on its global index, not on how the total was split into
# chunks - so changing reps_per_chunk / the number of chunks never changes
# the seed used for a given replication, keeping results reproducible.
first_rep <- (chunk_index - 1L) * reps_per_chunk + 1L
last_rep  <- chunk_index * reps_per_chunk
rep_ids   <- first_rep:last_rep

out_file  <- file.path(output_dir, sprintf("chunk_%03d.rds", chunk_index))
meta_file <- file.path(output_dir, sprintf("chunk_%03d_meta.json", chunk_index))

# Resume support: if this chunk already has a (possibly partial) output
# file from an earlier run, load it and skip any rep_ids already present.
results <- if (file.exists(out_file)) readRDS(out_file) else list()
done_reps <- if (length(results) > 0) vapply(results, function(r) r$rep, integer(1)) else integer(0)

for (rep_index in rep_ids) {
  if (rep_index %in% done_reps) next

  seed <- base_seed + rep_index
  results[[length(results) + 1]] <- bootstrap_rep(rep_index, seed, data, grid)

  # .rds has no append primitive, so "overwrite with the full growing list"
  # is what makes partial progress survive a kill/timeout: on every
  # iteration the file on disk reflects everything completed so far. This
  # is O(reps_per_chunk^2) in total bytes written, which is fine at
  # reps_per_chunk ~= 20; if you scale that up into the hundreds, switch to
  # saving one small file per replication instead (e.g.
  # chunk_003_rep_0047.rds) and have combine_results.R glob those.
  saveRDS(results, out_file)

  jsonlite::write_json(
    list(
      chunk = chunk_index,
      reps_per_chunk = reps_per_chunk,
      base_seed = base_seed,
      n_completed = length(results),
      n_expected = reps_per_chunk,
      timestamp = as.character(Sys.time())
    ),
    meta_file,
    auto_unbox = TRUE
  )
}

cat(sprintf("Chunk %d: %d/%d replications complete -> %s\n", chunk_index, length(results), reps_per_chunk, out_file))
