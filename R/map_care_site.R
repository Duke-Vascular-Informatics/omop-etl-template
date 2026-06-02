# =============================================================================
# R/map_care_site.R
# Purpose : Build OMOP care_site rows from source hospital/site identifiers,
#           and return a lookup table (source site ID → care_site_id) for use
#           by map_visit.R and other domain modules.
# Inputs  : data/staged/staged.rds; config list
# Outputs : Rows inserted into config$cdm_schema.care_site
#           Returns a data frame with columns: YOUR_SITE_ID_FIELD, care_site_id
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#CARE_SITE
# Notes   : Call this module BEFORE map_visit.R so that care_site_id values
#           are available for the visit_occurrence join.
# TODO [MAPPING]: Identify the source site identifier column
# =============================================================================

library(DatabaseConnector)
library(dplyr)
source("R/connection.R")

map_care_site <- function(staged, config, connection_details) {

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: Replace YOUR_SITE_ID_FIELD with the source column that
  # identifies the treating hospital or centre (e.g. CENTERID, FACILITYID).
  # Replace YOUR_SITE_NAME_FIELD with a human-readable site name, if available.
  # ---------------------------------------------------------------------------
  care_site <- staged |>
    distinct(YOUR_SITE_ID_FIELD) |>  # TODO: replace with actual site ID column
    arrange(YOUR_SITE_ID_FIELD) |>
    mutate(
      care_site_id          = as.integer(row_number()),
      care_site_name        = as.character(YOUR_SITE_ID_FIELD),  # TODO: replace with name field if available
      place_of_service_concept_id = 8717L,  # [vocab query] CMS Place of Service: Inpatient Hospital
      care_site_source_value       = as.character(YOUR_SITE_ID_FIELD)
    ) |>
    select(care_site_id, care_site_name,
           place_of_service_concept_id, care_site_source_value,
           YOUR_SITE_ID_FIELD)  # keep for lookup join by map_visit.R

  message("map_care_site: inserting ", nrow(care_site), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection        = conn,
      databaseSchema    = config$cdm_schema,
      tableName         = "care_site",
      data              = care_site |>
        select(care_site_id, care_site_name,
               place_of_service_concept_id, care_site_source_value),
      dropTableIfExists = FALSE,
      createTable       = FALSE
    )
  })

  # Return lookup table for map_visit.R
  invisible(care_site |> select(YOUR_SITE_ID_FIELD, care_site_id))
}
