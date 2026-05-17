# =============================================================================
# R/map_observation.R
# Purpose : Map source registry-specific fields (risk factors, functional
#           status, coded multi-choice fields) to OMOP observation table.
# Inputs  : data/staged/staged.rds; person_map; visit_map; config list
# Outputs : Rows inserted into config$cdm_schema.observation
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#OBSERVATION
# Notes   : Use observation for fields that don't fit condition, procedure,
#           or measurement — e.g. smoking status, ambulation class, ASA class.
# TODO [MAPPING]: Add rows to value_map.csv for each observation field
# =============================================================================

library(DatabaseConnector)
library(dplyr)
library(tidyr)
source("R/connection.R")

map_observation <- function(staged, person_map, visit_map, value_map, config, connection_details) {

  obs_map <- value_map |> filter(domain == "Observation")

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: List the source fields to map as observations. Separate
  # handling may be needed for:
  #   - Binary flags (similar to condition, but Observation domain)
  #   - Ordinal/coded fields (map each source value to an OMOP value_as_concept_id)
  #   - Free-text fields (use value_as_string)
  # ---------------------------------------------------------------------------
  observation_cols <- c(
    # "YOUR_SMOKING_FIELD",    # TODO
    # "YOUR_ASA_CLASS_FIELD"   # TODO
  )

  observation <- staged |>
    inner_join(person_map, by = "YOUR_PATIENT_ID_FIELD") |>  # TODO
    inner_join(visit_map,  by = "YOUR_PATIENT_ID_FIELD") |>  # TODO
    select(person_id, visit_occurrence_id, visit_start_date, all_of(observation_cols)) |>
    pivot_longer(
      cols      = all_of(observation_cols),
      names_to  = "source_field",
      values_to = "source_value"
    ) |>
    filter(!is.na(source_value)) |>
    left_join(obs_map, by = c("source_field" = "source_field", "source_value" = "source_value")) |>
    mutate(
      observation_id            = as.integer(row_number()),
      observation_date          = visit_start_date,
      observation_type_concept_id = 32817L,  # [vocab query] OMOP: EHR order
      observation_source_value  = paste0(source_field, "=", source_value)
    ) |>
    select(observation_id, person_id, observation_concept_id,
           observation_date, observation_datetime,
           observation_type_concept_id, value_as_number,
           value_as_string, value_as_concept_id,
           visit_occurrence_id, observation_source_value,
           observation_source_concept_id)

  message("map_observation: inserting ", nrow(observation), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "observation",
      data              = observation,
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  invisible(observation)
}
