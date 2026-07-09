# R Bootstrap Estimation HPC example

A small example R project demonstrating a good-practice pattern for running a computationally expensive bootstrap simulation on an HPC cluster with a 4-day (96-hour) per-job walltime limit.

This is a **template**, not a finished analysis. The toy statistical setup — an estimator whose function is refit via gradient boosting, random forest, and SVM on each bootstrap replication — is a stand-in. Adapt it to your own estimator by editing `R/fit_models.R` (what gets fitted) and `R/simulate_data.R` (what data it's fitted to); the chunking/SLURM/resume machinery around them should not need to change.

## Quick start

1. **Clone the repo onto Stanage** (or wherever you're running this) and `cd` into it.

2. **Install R packages into your personal library** — one-time, from an interactive session:

   ```bash
   srun --pty bash -i
   module load R/4.4.1-foss-2022b
   R
   ```

   then inside R:

   ```r
   install.packages(c("ranger", "xgboost", "e1071", "dplyr", "jsonlite"))
   ```

   Accept the prompt to create a personal library on first use, then exit R and the interactive shell.

3. **Test the pipeline locally** before scaling up — it runs in seconds:

   ```r
   Rscript scripts/generate_data.R output
   Rscript scripts/run_chunk.R 1 5 1000000 output
   Rscript scripts/combine.R output results/combined_results
   ```

   Confirm `results/combined_results.csv` looks sane.

4. **Adapt the template to your own estimator** (skip this step if you're just trying the toy example): edit `R/fit_models.R` (what gets fitted) and `R/simulate_data.R` (what data it's fitted to). Leave the chunking/SLURM/resume machinery alone.

5. **Fill in the placeholder `#SBATCH` directives** in `slurm/array_job.sh` and `slurm/combine_job.sh`:
   - `--partition` and `--account` — see `sinfo` and `sacctmgr show account`
   - `module load R/...` — confirm the version with `module spider R`
   - `--time`, `--mem`, `--cpus-per-task` — scale to your real per-replication cost, not the toy example's

6. **Submit the array job, then the combine job dependent on it:**

   ```bash
   jid=$(sbatch --parsable slurm/array_job.sh)
   sbatch --dependency=afterok:${jid} slurm/combine_job.sh
   ```

7. **If any array tasks fail or time out**, use `sacct` plus the missing-chunk check further down in this README to find which ones, and resubmit only those (`sbatch --array=3,17,42 slurm/array_job.sh`) before the combine job's `afterok` dependency will let it run.

See the sections below for the reasoning behind the chunking strategy, resume behaviour, and known gotchas.

## Repo structure

| File | Role |
|---|---|
| `R/simulate_data.R` | Toy nonlinear regression data generator + evaluation grid |
| `R/fit_models.R` | Fits xgboost, ranger, and e1071::svm; evaluates each at the grid — **replace with your own estimator(s)** |
| `R/bootstrap_rep.R` | One bootstrap replication: resample, fit, return results |
| `R/combine_results.R` | Combines chunk outputs into pointwise mean/SE/CI |
| `scripts/generate_data.R` | Generates the dataset + grid once, shared by every chunk |
| `scripts/run_chunk.R` | Runs one chunk of replications; called by each SLURM array task |
| `scripts/combine.R` | Runs the combine step; called by the combine SLURM job |
| `slurm/array_job.sh` | SLURM array job, one task per chunk |
| `slurm/combine_job.sh` | SLURM job that combines results after the array job finishes |

## The toy example

A single predictor `x`, a nonlinear `true_function(x) = sin(x) + 0.5*x*cos(2*x)`, and Gaussian noise (`R/simulate_data.R`). Nonlinear on purpose — a straight line would make all three ML methods approximate it near-identically, which defeats the point of comparing them. Each bootstrap replication resamples rows with replacement from one fixed dataset, refits all three methods, and evaluates each fitted function at a shared grid of 50 `x` values.

Sizes are kept small (n=200, grid of 50, `nrounds=50`/`num.trees=200`) so the whole pipeline runs in seconds locally — test end-to-end before scaling up on the cluster.

## Dependencies

`DESCRIPTION` is a manifest, not a buildable package — install what it lists with:

```r
install.packages(c("ranger", "xgboost", "e1071", "dplyr", "jsonlite"))
```

For stricter reproducibility (pinned versions across cluster nodes), run `renv::init()` followed by `renv::snapshot()` once dependencies are installed — this is an optional upgrade, not required to use the template.

On Stanage, install into your personal library from an **interactive** session before submitting any batch jobs — `module load R/...` won't have these packages until you do:

```bash
srun --pty bash -i
module load R/4.4.1-foss-2022b   # same version as in slurm/array_job.sh and slurm/combine_job.sh
R
```

then run the `install.packages(...)` call above inside that R session (you'll be prompted to create a personal library on first use). CPU and GPU nodes have different architectures, and different R major/minor versions need separate installs, so re-run this if you change `module load R/...` or switch node types — see the [Stanage R docs](https://docs.hpc.shef.ac.uk/en/latest/stanage/software/apps/r.html) for details.

## Running the toy example locally

```r
Rscript scripts/generate_data.R output
Rscript scripts/run_chunk.R 1 5 1000000 output   # chunk 1, 5 reps
Rscript scripts/run_chunk.R 2 5 1000000 output   # chunk 2, 5 reps
Rscript scripts/combine.R output results/combined_results
```

This produces `results/combined_results.csv` with pointwise `mean`, `se`, `ci_lo`, `ci_hi`, and `n_reps` per grid point per method.

## Chunking strategy

The real config (`slurm/array_job.sh`) is 1000 total replications split into 50 chunks of 20. Chunking rather than one long serial loop matters for three reasons:

1. **Walltime safety margin.** One job running all 1000 replications serially risks approaching or exceeding the 96-hour ceiling; a job that dies at hour 90 loses everything. A 4-hour chunk that dies loses at most a few replications' progress — and even those are recoverable (see below).
2. **Parallelism.** SLURM array tasks run concurrently across nodes, so 50 chunks of 20 replications finish in roughly the time of one chunk, not 50 times that.
3. **Resubmission granularity.** Only chunks that failed or timed out need rerunning — not the whole simulation.

Each bootstrap replication is independent of the others, which is what makes this split possible: replication `i`'s seed is `base_seed + i` regardless of which chunk it falls into, so changing the number of chunks or replications-per-chunk never changes any individual replication's result.

To change the total number of replications or how they're chunked, edit `REPS_PER_CHUNK` and `--array=1-N` together in `slurm/array_job.sh`, keeping `TOTAL_REPS = N * REPS_PER_CHUNK`, and pass the same `REPS_PER_CHUNK` value as the second argument to `run_chunk.R`.

## Incremental saving and resuming a killed chunk

`scripts/run_chunk.R` calls `saveRDS()` after **every single replication**, overwriting `output/chunk_NNN.rds` with the full list of replications completed so far. `.rds` has no native append mode — this "rewrite the whole growing list each time" pattern is what makes a killed or timed-out task leave usable partial results on disk, rather than losing the entire chunk.

On start, `run_chunk.R` loads any existing output file for that chunk index and skips replications already present, so re-running a partially-completed chunk resumes rather than redoing finished work.

(This overwrite-per-iteration approach is O(reps_per_chunk²) in bytes written, which is negligible at `reps_per_chunk = 20`. If you scale that up into the hundreds, switch to saving one small file per replication instead and have `combine_results.R` glob those.)

## Detecting and resubmitting missing/incomplete chunks

After the array job finishes, check which chunks are missing or short of their expected replication count:

```r
n_chunks <- 50
reps_per_chunk <- 20
status <- sapply(1:n_chunks, function(i) {
  f <- sprintf("output/chunk_%03d.rds", i)
  if (!file.exists(f)) return(0L)
  length(readRDS(f))
})
missing <- which(status < reps_per_chunk)
cat(paste(missing, collapse = ","))
```

`sbatch --array=` accepts a comma-separated list, not just ranges, so you can resubmit only the incomplete chunks:

```bash
sbatch --array=3,17,42 slurm/array_job.sh
```

The resume logic in `run_chunk.R` means even a chunk that's already partially filled in won't redo its completed replications.

## Submitting on Stanage

```bash
jid=$(sbatch --parsable slurm/array_job.sh)
sbatch --dependency=afterok:${jid} slurm/combine_job.sh
```

`--dependency=afterok` means the combine job only runs if every array task in the job it depends on succeeded — check `sacct` and resubmit any failed/incomplete chunks first if not.

Before submitting for real, edit the placeholder `#SBATCH` directives in `slurm/array_job.sh` and `slurm/combine_job.sh`:

- `--partition` and `--account`: Stanage-specific values (`sinfo`, `sacctmgr show account`)
- `module load R/...`: run `module spider R` on Stanage to find the exact available version string
- `--time`, `--mem`, `--cpus-per-task`: sized for the toy example here; scale to your real per-replication fitting cost

See the [Stanage R docs](https://docs.hpc.shef.ac.uk/en/latest/stanage/software/apps/r.html) for the full list of available `module load R/...` versions and package installation notes.

## Sampling variability vs. algorithmic variability

The bootstrap seed in `R/bootstrap_rep.R` (`set.seed(seed)` before resampling rows) captures **sampling variability** — the uncertainty in the estimator due to which rows happened to be drawn in a given bootstrap sample. That's the quantity this whole pipeline is built to estimate.

`ranger` and `xgboost` also have their own **internal** randomness — random feature/row subsampling per tree — independent of which bootstrap sample was drawn. Refitting the *same* bootstrap sample twice, with different RNG state, produces two different fitted curves purely from this algorithmic noise.

By default, this template does **not** separate the two: `fit_models()` inherits whatever RNG state exists after the resampling draw, so the reported confidence interval blends sampling variability with algorithm-internal variability. That's standard and defensible for an overall predictive-uncertainty band.

If you want to isolate pure sampling variability, fix a second seed for the algorithms themselves inside `R/fit_models.R`, e.g.:

```r
fit_ranger <- function(train_data, grid) {
  fit <- ranger::ranger(y ~ x, data = train_data, num.trees = 200, num.threads = 1, seed = 12345)
  predict(fit, data = grid)$predictions
}

fit_xgboost <- function(train_data, grid) {
  set.seed(12345)
  # ... rest unchanged (nthread = 1 already set, since multi-threaded
  # xgboost is not exactly reproducible even with a fixed seed)
}
```

Holding the algorithm's internal randomness constant across all replications means any variation in the resulting curves is then attributable only to which rows were resampled.

## Known gotchas (see comments in `R/fit_models.R`)

- xgboost's predict expects the same matrix column layout as training (`as.matrix(grid["x"])`, not a bare vector).
- `predict.ranger()` returns a list — pull `$predictions`.
- `predict.svm()` carries over row names from `newdata` — `unname()` before combining with other methods' predictions.
- `nthread = 1` / `num.threads = 1` are set for reproducibility, matching `--cpus-per-task=1`, not for local performance.
