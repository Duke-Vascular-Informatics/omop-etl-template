# =============================================================================
# R/map_observation_period.R
# Purpose : Build OMOP observation_period rows for all persons loaded by this
#           ETL run. One row per person; spans from the earliest visit start
#           date to the latest visit end date in the CDM schema.
# Inputs  : data/staged/staged.rds; person_map; config list
# Outputs : Rows inserted into config$cdm_schema.observation_period
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#OBSERVATION_PERIOD
# Notes   : For registry ETLs with a single index visit per person, the
#           observation period typically spans the index visit. If follow-up
#           data are loaded (LTF), re-run this module after LTF mapping to
#           extend the period to cover follow-up dates.
# TODO [MAPPING]: Confirm observation period date logic for this registry
# =============================================================================

library(DatabaseConnector)
library(dplyr)
source("R/connection.R")

map_observation_period <- function(staged, person_map, config, connection_details) {

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: Replace YOUR_PROC_DATE_FIELD and YOUR_DISCHARGE_DATE_FIELD
  # with the actual date fields from the staged data frame. Use visit_start_date
  # and visit_end_date if those are already computed by map_visit.R.
  # ---------------------------------------------------------------------------
  observation_period <- staged |>
    inner_join(person_map, by = "YOUR_PATIENT_ID_FIELD") |>  # TODO: replace key
    mutate(
      obs_start = as.Date(YOUR_PROC_DATE_FIELD),      # TODO: replace with actual start date
      obs_end   = as.Date(YOUR_DISCHARGE_DATE_FIELD)  # TODO: replace with actual end date
    ) |>
    group_by(person_id) |>
    summarise(
      observation_period_start_date = min(obs_start, na.rm = TRUE),
      observation_period_end_date   = max(obs_end,   na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      observation_period_id          = as.integer(row_number()),
      period_type_concept_id         = 44814724L  # [vocab query] OMOP: Period covering healthcare encounters
    ) |>
    select(observation_period_id, person_id,
           observation_period_start_date, observation_period_end_date,
           period_type_concept_id)

  message("map_observation_period: inserting ", nrow(observation_period), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "observation_period",
      data              = observation_period,
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  invisible(observation_period)
}
