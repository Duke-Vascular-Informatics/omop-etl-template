# =============================================================================
# R/map_drug.R
# Purpose : Map source medication/drug fields to the OMOP drug_exposure table.
# Inputs  : data/staged/staged.rds; person_map; visit_map; config list
# Outputs : Rows inserted into config$cdm_schema.drug_exposure
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#DRUG_EXPOSURE
# Notes   : Registry medication fields are typically binary flags (pre- or
#           post-operative medication use). Each Yes flag becomes one
#           drug_exposure row anchored to the visit start date.
# TODO [MAPPING]: Identify source medication columns and add to value_map.csv
# =============================================================================

library(DatabaseConnector)
library(dplyr)
library(tidyr)
source("R/connection.R")

map_drug <- function(staged, person_map, visit_map, value_map, config, connection_details) {

  drug_map <- value_map |> filter(domain == "Drug")

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: List the medication flag columns to pivot. Each column name
  # must have a corresponding row in value_map.csv with domain = "Drug" and a
  # [vocab query]-confirmed RxNorm concept_id.
  # ---------------------------------------------------------------------------
  drug_cols <- c(
    # "YOUR_ASPIRIN_FIELD",    # TODO: add all medication flag columns here
    # "YOUR_STATIN_FIELD",
    # "YOUR_ANTICOAG_FIELD"
  )

  drug <- staged |>
    inner_join(person_map, by = "YOUR_PATIENT_ID_FIELD") |>  # TODO: replace key
    inner_join(visit_map,  by = "YOUR_PATIENT_ID_FIELD") |>  # TODO: replace key
    select(person_id, visit_occurrence_id, visit_start_date, all_of(drug_cols)) |>
    pivot_longer(
      cols      = all_of(drug_cols),
      names_to  = "source_field",
      values_to = "flag_value"
    ) |>
    filter(flag_value %in% c("Yes", "1", "TRUE", "yes")) |>  # TODO: confirm source coding
    left_join(drug_map, by = c("source_field" = "source_field")) |>
    mutate(
      drug_exposure_id          = as.integer(row_number()),
      drug_exposure_start_date  = visit_start_date,
      drug_exposure_end_date    = visit_start_date,  # single-day for registry flags
      drug_type_concept_id      = 32817L,  # [vocab query] OMOP: EHR order
      drug_source_value         = source_field,
      quantity                  = NA_real_
    ) |>
    select(drug_exposure_id, person_id, drug_concept_id,
           drug_exposure_start_date, drug_exposure_end_date,
           drug_type_concept_id, visit_occurrence_id,
           drug_source_value, drug_source_concept_id, quantity)

  message("map_drug: inserting ", nrow(drug), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "drug_exposure",
      data              = drug,
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  invisible(drug)
}
