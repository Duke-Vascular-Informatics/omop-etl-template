# =============================================================================
# run_etl.R
# Purpose : One-shot ETL orchestrator. Calls workflow/01–04 in order.
#           Run workflow steps individually during development and testing.
# Usage   : source("run_etl.R")
# =============================================================================

source("config.R")
config  <- get_etl_config()
if (!dir.exists(config$output_folder)) dir.create(config$output_folder, recursive = TRUE)

message("=== OMOP ETL — ", config$source_description, " ===")
message("Target schema : ", config$cdm_schema)
message("Source file   : ", file.path(config$source_dir, config$source_file))
message("Started       : ", Sys.time())

source("workflow/01_stage_raw.R")
source("workflow/02_validate_staged.R")
source("workflow/03_run_etl.R")
source("workflow/04_qc_omop.R")

message("ETL complete  : ", Sys.time())
