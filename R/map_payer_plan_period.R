# =============================================================================
# R/map_payer_plan_period.R
# Purpose : Map source insurance/payer fields to the OMOP payer_plan_period
#           table. Typically a stub for registry ETLs — most registries do not
#           capture payer information at a level that maps to OMOP payer tables.
# Inputs  : data/staged/staged.rds; person_map; config list
# Outputs : Rows inserted into config$cdm_schema.payer_plan_period (if applicable)
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#PAYER_PLAN_PERIOD
# Notes   : Leave this function as a no-op stub if payer data are unavailable.
#           Delete the stub and call from run_etl.R only when payer fields exist.
# TODO [MAPPING]: Determine whether payer data are available in this registry
# =============================================================================

library(DatabaseConnector)
library(dplyr)
source("R/connection.R")

map_payer_plan_period <- function(staged, person_map, config, connection_details) {

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: If payer/insurance data are available in the source,
  # implement the mapping here. Common registry fields that may indicate payer:
  #   - Insurance type (Medicare, Medicaid, Commercial, etc.)
  #   - Primary payer flag
  #
  # If no payer data are available, leave this function as a no-op stub.
  # Remove the call from run_etl.R if payer data are not present.
  # ---------------------------------------------------------------------------

  message("map_payer_plan_period: no payer data available — stub only, no rows inserted")
  invisible(NULL)
}
