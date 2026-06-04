# =============================================================================
# R/utils.R
# Purpose : Shared helper functions and lookup tables used across ETL mapping
#           modules. Sourced by R/map_*.R via source("R/utils.R").
# Inputs  : None (sourced as a library, not called directly)
# Outputs : No side effects; provides functions and module-level constants.
# TODO [MAPPING]: Add registry-specific lookup functions and concept vectors here
# =============================================================================

library(dplyr)

# -----------------------------------------------------------------------------
# lookup_indication_concept()
#
# Template for a vectorised lookup of condition_concept_id from a coded source
# field value. Replace the named vector with registry-specific concept IDs
# confirmed by a vocabulary query (Rule 1 — three-tier lookup).
#
# Parameters:
#   code — character or integer vector of source field values
#
# Returns: integer vector of condition_concept_ids (0L for unrecognised codes)
#
# TODO [MAPPING]: Replace placeholder concept IDs with [vocab query]-confirmed
# values and rename this function to match the source field being looked up.
# -----------------------------------------------------------------------------
lookup_indication_concept <- function(code) {

  # Named integer vector: source code → OMOP concept_id
  # TODO [MAPPING]: Replace 0L placeholders with verified concept IDs
  lookup <- c(
    "1" = 0L,  # TODO [REPLACE]: source code 1 → [vocab query] concept name
    "2" = 0L,  # TODO [REPLACE]: source code 2 → [vocab query] concept name
    "3" = 0L   # TODO [REPLACE]: source code 3 → [vocab query] concept name
  )

  result <- lookup[as.character(code)]
  as.integer(ifelse(is.na(result), 0L, result))
}
