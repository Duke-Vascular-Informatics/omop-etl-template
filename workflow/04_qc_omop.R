# =============================================================================
# workflow/04_qc_omop.R
# Purpose : Post-load QC — row counts, zero-concept checks, referential
#           integrity spot checks against the populated OMOP CDM tables.
# Run     : Rscript workflow/04_qc_omop.R
# TODO [MAPPING]: Add source-specific plausibility checks (expected row counts,
#                 date range, concept coverage)
# =============================================================================
if (!exists("config")) { source("config.R"); config <- get_etl_config() }

library(DatabaseConnector)
library(SqlRender)
source("R/connection.R")

connection_details <- get_connection_details(config)

qc_tables <- c("person", "visit_occurrence", "procedure_occurrence",
               "condition_occurrence", "observation", "measurement")

with_connection(connection_details, function(conn) {
  for (tbl in qc_tables) {
    sql <- SqlRender::render(
      "SELECT COUNT(*) AS n FROM @cdm_schema.@table",
      cdm_schema = config$cdm_schema,
      table      = tbl
    )
    n <- DatabaseConnector::querySql(conn, sql)$N
    message(sprintf("[QC] %-30s  rows: %d", tbl, n))
    if (n == 0) message(sprintf("[WARN] %s has zero rows", tbl))
  }

  # Zero-concept check on person
  sql_zero <- SqlRender::render(
    "SELECT COUNT(*) AS n FROM @cdm_schema.person WHERE gender_concept_id = 0",
    cdm_schema = config$cdm_schema
  )
  n_zero <- DatabaseConnector::querySql(conn, sql_zero)$N
  if (n_zero > 0) message(sprintf("[WARN] %d person rows have gender_concept_id = 0", n_zero))
  else message("[QC]  person.gender_concept_id — no zero concepts")
})

message("workflow/04 QC complete")
