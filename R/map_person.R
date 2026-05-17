# =============================================================================
# R/map_person.R
# Purpose : Map source demographics to OMOP person table.
# Inputs  : data/staged/staged.rds; config list
# Outputs : Rows inserted into config$cdm_schema.person
# OMOP ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#PERSON
# TODO [MAPPING]: Assign concept IDs for gender, race, ethnicity
# =============================================================================

library(DatabaseConnector)
library(SqlRender)
library(dplyr)
source("R/connection.R")

map_person <- function(staged, config, connection_details) {

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: Select and rename the source columns that carry demographics.
  # Required OMOP person fields:
  #   person_id, gender_concept_id, year_of_birth, race_concept_id,
  #   ethnicity_concept_id, person_source_value, gender_source_value
  # ---------------------------------------------------------------------------
  person <- staged |>
    mutate(
      person_id = as.integer(row_number()) + config$person_id_offset,

      # TODO [MAPPING]: Map source sex field to OMOP gender concept IDs
      # 8507 = [vocab query] OMOP: Male   |   8532 = [vocab query] OMOP: Female
      # 0   = [vocab query] OMOP: No matching concept (unknown/other)
      gender_concept_id = case_when(
        YOUR_SEX_FIELD == "YOUR_MALE_VALUE"   ~ 8507L,   # TODO: replace field/value
        YOUR_SEX_FIELD == "YOUR_FEMALE_VALUE" ~ 8532L,   # TODO: replace field/value
        .default = 0L
      ),

      # TODO [MAPPING]: Derive year_of_birth from age or DOB field
      year_of_birth = NA_integer_,

      # TODO [MAPPING]: Map source race/ethnicity to OMOP concept IDs
      race_concept_id        = 0L,
      ethnicity_concept_id   = 0L,

      person_source_value    = YOUR_PATIENT_ID_FIELD,  # TODO: replace
      gender_source_value    = YOUR_SEX_FIELD,          # TODO: replace
      race_source_value      = NA_character_,
      ethnicity_source_value = NA_character_
    ) |>
    select(person_id, gender_concept_id, year_of_birth, month_of_birth,
           day_of_birth, race_concept_id, ethnicity_concept_id,
           person_source_value, gender_source_value,
           race_source_value, ethnicity_source_value)

  message("map_person: inserting ", nrow(person), " rows")

  with_connection(connection_details, function(conn) {
    DatabaseConnector::insertTable(
      connection   = conn,
      databaseSchema = config$cdm_schema,
      tableName    = "person",
      data         = person,
      dropTableIfExists = FALSE,
      createTable  = FALSE
    )
  })

  invisible(person)
}
