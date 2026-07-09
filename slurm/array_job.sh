#!/bin/bash
# SLURM job array: one task per chunk of bootstrap replications.
#
# Default here is 1000 total replications split into 50 chunks of 20 -
# keep TOTAL_REPS = (number of array tasks) * REPS_PER_CHUNK in sync if you
# change either. See the README for the reasoning behind this split and how
# to resubmit only chunks that are missing/incomplete.

#SBATCH --job-name=boot_chunk
#SBATCH --array=1-50                   # CHANGE: one task per chunk; must match TOTAL_REPS/REPS_PER_CHUNK below
#SBATCH --time=04:00:00                # CHANGE: per-task walltime. Sized for the toy example; scale to your
                                        #   real fitting cost * reps_per_chunk, with margin. Stanage's overall
                                        #   per-job ceiling is 96:00:00 - this is what chunking keeps you under.
#SBATCH --partition=general            # CHANGE: run `sinfo` on Stanage to see available partitions
#SBATCH --account=YOUR_PROJECT_CODE    # CHANGE: your Stanage project/account code (`sacctmgr show account`)
#SBATCH --cpus-per-task=1              # matches nthread=1 / num.threads=1 set in R/fit_models.R
#SBATCH --mem=4G                       # CHANGE: toy example is tiny; increase for a real dataset/estimator
#SBATCH --output=slurm_logs/chunk_%A_%a.out
#SBATCH --error=slurm_logs/chunk_%A_%a.err

module load R/4.1.2                    # CHANGE: run `module spider R` on Stanage for the exact available version

set -euo pipefail

REPS_PER_CHUNK=20
BASE_SEED=1000000
OUTPUT_DIR=output

mkdir -p "${OUTPUT_DIR}" slurm_logs

# $SLURM_ARRAY_TASK_ID supplies the chunk index; see scripts/run_chunk.R for
# how it's turned into a range of global replication indices and seeds.
Rscript scripts/run_chunk.R "${SLURM_ARRAY_TASK_ID}" "${REPS_PER_CHUNK}" "${BASE_SEED}" "${OUTPUT_DIR}"
