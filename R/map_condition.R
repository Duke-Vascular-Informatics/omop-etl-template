# =============================================================================
# R/map_condition.R
# Purpose : Map source comorbidity flags to OMOP condition_occurrence table.
# Inputs  : data/staged/staged.rds; person_map; visit_map; config list
# Outputs : Rows inserted into config$cdm_schema.condition_occurrence
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#CONDITION_OCCURRENCE
# Notes   : Registry comorbidities are typically binary flags — each Yes flag
#           becomes one condition_occurrence row at the visit start date.
# TODO [MAPPING]: Add a row to value_map.csv for each comorbidity field
# =============================================================================

library(DatabaseConnector)
library(dplyr)
library(tidyr)
source("R/connection.R")

map_condition <- function(staged, person_map, visit_map, value_map, config, connection_details) {

  cond_map <- value_map |> filter(domain == "Condition")

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: List the comorbidity flag columns to pivot. Each column name
  # must have a corresponding row in value_map.csv with domain = "Condition".
  # ---------------------------------------------------------------------------
  comorbidity_cols <- c(
    # "YOUR_HYPERTENSION_FIELD",   # TODO: add all flag columns here
    # "YOUR_DIABETES_FIELD",
    # "YOUR_CHF_FIELD"
  )

  condition <- staged |>
    inner_join(person_map, by = "YOUR_PATIENT_ID_FIELD") |>  # TODO
    inner_join(visit_map,  by = "YOUR_PATIENT_ID_FIELD") |>  # TODO
    select(person_id, visit_occurrence_id, visit_start_date, all_of(comorbidity_cols)) |>
    pivot_longer(
      cols      = all_of(comorbidity_cols),
      names_to  = "source_field",
      values_to = "flag_value"
    ) |>
    # Keep only positive flags (value = "Yes", 1, TRUE — adjust to source coding)
    filter(flag_value %in% c("Yes", "1", "TRUE", "yes")) |>  # TODO: confirm source coding
    left_join(cond_map, by = c("source_field" = "source_field")) |>
    mutate(
      condition_occurrence_id      = as.integer(row_number()),
      condition_start_date         = visit_start_date,
      condition_type_concept_id    = 32817L,  # [vocab query] OMOP: EHR order
      condition_status_concept_id  = 32901L,  # [vocab query] OMOP: Primary condition
      condition_source_value        = source_field
    ) |>
    select(condition_occurrence_id, person_id, condition_concept_id,
           condition_start_date, condition_start_datetime,
           condition_end_date, condition_end_datetime,
           condition_type_concept_id, condition_status_concept_id,
           visit_occurrence_id, condition_source_value,
           condition_source_concept_id)

  message("map_condition: inserting ", nrow(condition), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "condition_occurrence",
      data              = condition,
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  invisible(condition)
}
