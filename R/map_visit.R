# =============================================================================
# R/map_visit.R
# Purpose : Map source procedure encounter to OMOP visit_occurrence table.
# Inputs  : data/staged/staged.rds; config list
# Outputs : Rows inserted into config$cdm_schema.visit_occurrence
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#VISIT_OCCURRENCE
# TODO [MAPPING]: Confirm visit type and encounter date fields
# =============================================================================

library(DatabaseConnector)
library(dplyr)
source("R/connection.R")

map_visit <- function(staged, person_map, config, connection_details) {

  # ---------------------------------------------------------------------------
  # visit_type_concept_id = 32827  # [vocab query] OMOP: EHR encounter
  # visit_concept_id      = 9201   # [vocab query] OMOP: Inpatient visit
  #   Adjust visit_concept_id if the source captures outpatient procedures:
  #   9202 = [vocab query] OMOP: Outpatient visit
  # ---------------------------------------------------------------------------
  visit <- staged |>
    inner_join(person_map, by = "YOUR_PATIENT_ID_FIELD") |>  # TODO: replace key
    mutate(
      visit_occurrence_id   = as.integer(row_number()) + config$visit_id_offset,

      # TODO [MAPPING]: Map visit type — registry encounters are typically inpatient
      visit_concept_id      = 9201L,  # [vocab query] OMOP: Inpatient visit

      # TODO [MAPPING]: Replace with actual date field(s) from source
      visit_start_date      = as.Date(YOUR_PROC_DATE_FIELD),  # TODO
      visit_end_date        = as.Date(YOUR_DISCHARGE_DATE_FIELD),  # TODO; NA if outpatient

      visit_type_concept_id = 32827L,  # [vocab query] OMOP: EHR encounter

      # Flat-file provenance tag + encounter/procedure ID for row-level traceability.
      # Format: "{source_file_tag}:{YOUR_PATIENT_ID_FIELD}"
      # e.g. "REGISTRY_INDEX_20231201:12345678"
      # source_file is stamped on every staged row by stage_raw.R.
      # All OMOP domain rows carry visit_occurrence_id; analysts recover the
      # source flat file by joining to visit_occurrence on visit_occurrence_id
      # and reading the leading token of visit_source_value (split on ":").
      visit_source_value    = paste0(source_file, ":", YOUR_ENCOUNTER_ID_FIELD)  # TODO: replace YOUR_ENCOUNTER_ID_FIELD
    ) |>
    select(visit_occurrence_id, person_id, visit_concept_id,
           visit_start_date, visit_start_datetime,
           visit_end_date, visit_end_datetime,
           visit_type_concept_id, visit_source_value)

  message("map_visit: inserting ", nrow(visit), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "visit_occurrence",
      data              = visit,
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  invisible(visit)
}
