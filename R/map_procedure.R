# =============================================================================
# R/map_procedure.R
# Purpose : Map source operative fields to OMOP procedure_occurrence table.
# Inputs  : data/staged/staged.rds; person_map; visit_map; config list
# Outputs : Rows inserted into config$cdm_schema.procedure_occurrence
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#PROCEDURE_OCCURRENCE
# TODO [MAPPING]: Build value_map rows for each procedure type in source
# =============================================================================

library(DatabaseConnector)
library(dplyr)
source("R/connection.R")

map_procedure <- function(staged, person_map, visit_map, value_map, config, connection_details) {

  # Load the procedure value map (source code → OMOP concept ID)
  proc_map <- value_map |> filter(domain == "Procedure")

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: Join staged data to proc_map on the source procedure field.
  # procedure_type_concept_id = 32817  # [vocab query] OMOP: EHR order
  # ---------------------------------------------------------------------------
  procedure <- staged |>
    inner_join(person_map, by = "YOUR_PATIENT_ID_FIELD") |>  # TODO
    inner_join(visit_map,  by = "YOUR_PATIENT_ID_FIELD") |>  # TODO
    left_join(proc_map,    by = c("YOUR_PROC_TYPE_FIELD" = "source_value")) |>  # TODO
    mutate(
      procedure_occurrence_id   = as.integer(row_number()),
      procedure_date            = as.Date(YOUR_PROC_DATE_FIELD),  # TODO
      procedure_type_concept_id = 32817L,  # [vocab query] OMOP: EHR order
      procedure_source_value    = YOUR_PROC_TYPE_FIELD  # TODO
    ) |>
    select(procedure_occurrence_id, person_id, procedure_concept_id,
           procedure_date, procedure_datetime,
           procedure_type_concept_id, visit_occurrence_id,
           procedure_source_value, procedure_source_concept_id)

  message("map_procedure: inserting ", nrow(procedure), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "procedure_occurrence",
      data              = procedure,
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  invisible(procedure)
}
