# =============================================================================
# R/map_measurement.R
# Purpose : Map source numeric and semi-quantitative fields (labs, ABI,
#           physiologic scores) to OMOP measurement table.
# Inputs  : data/staged/staged.rds; person_map; visit_map; config list
# Outputs : Rows inserted into config$cdm_schema.measurement
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#MEASUREMENT
# TODO [MAPPING]: Add rows to value_map.csv for each measurement field
# =============================================================================

library(DatabaseConnector)
library(dplyr)
library(tidyr)
source("R/connection.R")

map_measurement <- function(staged, person_map, visit_map, value_map, config, connection_details) {

  meas_map <- value_map |> filter(domain == "Measurement")

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: List the source numeric/semi-quantitative fields.
  # Each field name must appear in value_map.csv with domain = "Measurement"
  # and a non-zero measurement_concept_id.
  # Common unit concept IDs:
  #   8554  = [vocab query] UCUM: %
  #   8840  = [vocab query] UCUM: mg/dL
  #   8876  = [vocab query] UCUM: mmHg
  # ---------------------------------------------------------------------------
  measurement_cols <- c(
    # "YOUR_ABI_FIELD",        # TODO
    # "YOUR_CREATININE_FIELD"  # TODO
  )

  measurement <- staged |>
    inner_join(person_map, by = "YOUR_PATIENT_ID_FIELD") |>  # TODO
    inner_join(visit_map,  by = "YOUR_PATIENT_ID_FIELD") |>  # TODO
    select(person_id, visit_occurrence_id, visit_start_date, all_of(measurement_cols)) |>
    pivot_longer(
      cols      = all_of(measurement_cols),
      names_to  = "source_field",
      values_to = "raw_value"
    ) |>
    filter(!is.na(raw_value)) |>
    left_join(meas_map, by = c("source_field" = "source_field")) |>
    mutate(
      measurement_id             = as.integer(row_number()),
      measurement_date           = visit_start_date,
      measurement_type_concept_id = 32817L,  # [vocab query] OMOP: EHR order
      value_as_number            = suppressWarnings(as.numeric(raw_value)),
      measurement_source_value   = paste0(source_field, "=", raw_value)
    ) |>
    select(measurement_id, person_id, measurement_concept_id,
           measurement_date, measurement_datetime,
           measurement_type_concept_id, operator_concept_id,
           value_as_number, value_as_concept_id, unit_concept_id,
           range_low, range_high, visit_occurrence_id,
           measurement_source_value, measurement_source_concept_id,
           unit_source_value, value_source_value)

  message("map_measurement: inserting ", nrow(measurement), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "measurement",
      data              = measurement,
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  invisible(measurement)
}
