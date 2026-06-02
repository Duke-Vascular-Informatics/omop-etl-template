# =============================================================================
# run_etl.R — YOUR_ETL_NAME ETL bundle entry point
#
# Runs the complete YOUR_ETL_NAME → OMOP CDM v5.4 ETL pipeline in dependency order.
# Called by run_etl.sh after Kerberos authentication and environment setup.
#
# Prerequisites:
#   - .env configured (ETL_SOURCE_DIR, ETL_SOURCE_FILE_TAG, ETL_SOURCE_FILE,
#     INST_OMOP_RESULTS_SCHEMA, MSSQL_* connection settings)
#   - Kerberos ticket valid (kinit via setup_env.sh)
#   - R packages installed (install_r_packages.sh)
#   - source flat-file CSV(s) present in data/raw/
#
# Run order:
#   stage_raw        — read CSV, stamp source_file provenance, write staged.rds
#   map_person       — person table
#   map_visit        — visit_occurrence table
#   map_condition    — condition_occurrence table
#   map_procedure    — procedure_occurrence table
#   map_observation  — observation table
#   map_measurement  — measurement table
#   map_drug         — drug_exposure table
#   map_death        — death table
#   map_care_site    — care_site table (if applicable)
#   map_observation_period — observation_period table
#   map_payer_plan_period  — payer_plan_period table (stub)
# =============================================================================

# Load .env into environment (Kerberos HPC environment)
if (file.exists(".env")) {
  readRenviron(".env")
}

options(repos = c(CRAN = Sys.getenv("CRAN_MIRROR",
                                    unset = "https://archive.linux.duke.edu/cran/")))

source("R/connection.R")
source("R/utils.R")
source("R/stage_raw.R")
source("R/map_person.R")
source("R/map_visit.R")
source("R/map_condition.R")
source("R/map_procedure.R")
source("R/map_observation.R")
source("R/map_measurement.R")
source("R/map_drug.R")
source("R/map_death.R")
source("R/map_care_site.R")
source("R/map_observation_period.R")
source("R/map_payer_plan_period.R")
source("config.R")

config             <- get_etl_config()
connection_details <- get_connection_details(config)

message("=== YOUR_ETL_NAME ETL ===")
message("Source file tag : ", config$source_file_tag)
message("Source file     : ", file.path(config$source_dir, config$source_file))
message("Target schema   : ", config$cdm_schema)
message("Started         : ", Sys.time())
message("")

# ---------------------------------------------------------------------------
# Stage raw source data
# ---------------------------------------------------------------------------
message("[1/11] Staging raw source ...")
staged <- stage_raw(config)

# ---------------------------------------------------------------------------
# Write OMOP tables in dependency order
# ---------------------------------------------------------------------------
message("[2/11] Mapping persons ...")
map_person(staged, config, connection_details)

message("[3/11] Mapping visits ...")
map_visit(staged, config, connection_details)

message("[4/11] Mapping conditions ...")
map_condition(staged, config, connection_details)

message("[5/11] Mapping procedures ...")
map_procedure(staged, config, connection_details)

message("[6/11] Mapping observations ...")
map_observation(staged, config, connection_details)

message("[7/11] Mapping measurements ...")
map_measurement(staged, config, connection_details)

message("[8/11] Mapping drug exposures ...")
map_drug(staged, config, connection_details)

message("[9/11] Mapping deaths ...")
map_death(staged, config, connection_details)

message("[10/11] Mapping care sites ...")
map_care_site(staged, config, connection_details)

message("[11/11] Mapping observation periods ...")
map_observation_period(staged, config, connection_details)

message("")
message("=== ETL complete ===")
message("Finished: ", Sys.time())
message("Rows written to schema: ", config$cdm_schema)
message("")
message("Next steps:")
message("  1. Review any QC warnings above.")
message("  2. Run DataQualityDashboard against the loaded schema.")
message("  3. Check gap variables in mappings/vocab_gaps.csv for open items.")
