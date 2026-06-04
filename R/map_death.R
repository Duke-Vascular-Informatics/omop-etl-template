# =============================================================================
# R/map_death.R
# Purpose : Map source in-hospital or post-discharge death fields to the OMOP
#           death table.
# Inputs  : data/staged/staged.rds; person_map; config list
# Outputs : Rows inserted into config$cdm_schema.death
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#DEATH
# Notes   : Registry mortality is typically captured as a flag (in-hospital
#           death) and/or a date field. Only one death row per person is
#           permitted in OMOP CDM v5.4.
# TODO [MAPPING]: Identify the source mortality flag and date fields
# =============================================================================

library(DatabaseConnector)
library(dplyr)
source("R/connection.R")

map_death <- function(staged, person_map, config, connection_details) {

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: Replace YOUR_DEATH_FLAG_FIELD with the source variable that
  # indicates in-hospital or 30-day death (e.g. a binary flag or coded field).
  # Replace YOUR_DEATH_DATE_FIELD with the death date variable if available;
  # use visit_end_date as a fallback when exact date is not recorded.
  # ---------------------------------------------------------------------------
  death <- staged |>
    inner_join(person_map, by = "YOUR_PATIENT_ID_FIELD") |>  # TODO: replace key
    filter(!is.na(YOUR_DEATH_FLAG_FIELD) &
             YOUR_DEATH_FLAG_FIELD %in% c("Yes", "1", "TRUE")) |>  # TODO: adjust coding
    mutate(
      death_date           = as.Date(YOUR_DEATH_DATE_FIELD),  # TODO; fallback: visit_end_date
      death_type_concept_id = 32817L,  # [vocab query] OMOP: EHR order (registry-reported death)
      cause_concept_id      = 0L,      # TODO [MAPPING]: map primary cause if available
      cause_source_value    = NA_character_  # TODO: populate from source cause field
    ) |>
    select(person_id, death_date, death_type_concept_id,
           cause_concept_id, cause_source_value)

  message("map_death: inserting ", nrow(death), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "death",
      data              = death,
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  invisible(death)
}
