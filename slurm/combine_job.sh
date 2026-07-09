#!/bin/bash
# Combines all chunk outputs after the array job finishes. Submit it with a
# dependency on the array job so it only runs once every chunk has
# completed (successfully):
#
#   jid=$(sbatch --parsable slurm/array_job.sh)
#   sbatch --dependency=afterok:${jid} slurm/combine_job.sh
#
# afterok means this job will NOT run if any array task fails - check
# `sacct` and resubmit failed/incomplete chunks (see README) before
# re-running this.

#SBATCH --job-name=boot_combine
#SBATCH --time=00:30:00                # CHANGE: combining is cheap; bump only if you have very many chunks/reps
## SBATCH --partition=YOUR_PARTITION    # UNCOMMENT + CHANGE: same as array_job.sh
#SBATCH --account=YOUR_PROJECT_CODE    # CHANGE: same as array_job.sh
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G                       # CHANGE: increase if combining thousands of replications gets memory-heavy
#SBATCH --output=slurm_logs/combine_%j.out
#SBATCH --error=slurm_logs/combine_%j.err

module load R/4.4.1-foss-2022b          # same as array_job.sh (verified latest available on Stanage)

set -euo pipefail

mkdir -p slurm_logs

Rscript scripts/combine.R output results/combined_results
