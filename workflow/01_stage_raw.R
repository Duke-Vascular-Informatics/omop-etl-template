# =============================================================================
# workflow/01_stage_raw.R
# Purpose : Read source CSV, enforce column types, write staged.rds.
# Run     : Rscript workflow/01_stage_raw.R
# =============================================================================
if (!exists("config")) { source("config.R"); config <- get_etl_config() }
source("R/stage_raw.R")
staged <- stage_raw(config)
