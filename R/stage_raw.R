# =============================================================================
# R/stage_raw.R
# Purpose : Read the source CSV, enforce column types, rename to snake_case,
#           validate required fields, and write a clean staged file to
#           data/staged/ for use by all map_*.R modules.
# Inputs  : config$source_dir / config$source_file (raw CSV)
# Outputs : data/staged/staged.rds  (typed, cleaned data frame)
# TODO [MAPPING]: Replace col_types spec with actual source schema
# =============================================================================

library(readr)
library(dplyr)
library(stringr)

stage_raw <- function(config) {

  raw_path <- file.path(config$source_dir, config$source_file)
  if (!file.exists(raw_path)) stop("Source file not found: ", raw_path)

  message("Staging raw source: ", raw_path)

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: Define col_types based on the source data dictionary.
  # Use readr::cols() with explicit types — never rely on auto-detection for
  # clinical registry data (date formats and coded fields routinely mis-parse).
  # ---------------------------------------------------------------------------
  raw <- readr::read_csv(
    raw_path,
    col_types = cols(.default = col_character()),  # TODO: replace with explicit spec
    na        = c("", "NA", "NULL", "N/A", "Unknown", ".")
  )

  # Standardise column names to snake_case
  names(raw) <- names(raw) |> stringr::str_to_lower() |> stringr::str_replace_all("[^a-z0-9]+", "_")

  # ---------------------------------------------------------------------------
  # TODO [MAPPING]: Add type coercions, derived fields, and row-level validation
  # here before writing to staged. For example:
  #   raw <- raw |> mutate(proc_date = as.Date(proc_date, "%m/%d/%Y"))
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Stamp flat-file provenance on every row.
  # source_file carries config$source_file_tag (e.g. "REGISTRY_INDEX_20231201")
  # so that map_visit.R can write it into visit_occurrence.visit_source_value
  # and every downstream domain row inherits traceable provenance via
  # visit_occurrence_id. Never hardcode a file name in map_*.R — always read
  # from base$source_file (which comes from this column).
  # ---------------------------------------------------------------------------
  raw <- raw |> dplyr::mutate(source_file = config$source_file_tag)

  message("Staged rows: ", nrow(raw), "  columns: ", ncol(raw),
          "  source_file: ", config$source_file_tag)

  staged_path <- file.path(config$staged_dir, "staged.rds")
  if (!dir.exists(config$staged_dir)) dir.create(config$staged_dir, recursive = TRUE)
  saveRDS(raw, staged_path)

  message("Staged data written to: ", staged_path)
  invisible(raw)
}
