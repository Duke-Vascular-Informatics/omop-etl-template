# =============================================================================
# scripts/check_setup.R
# Purpose : Pre-flight checker. Validates config.R, mappings, and module stubs
#           without a database connection.
# Usage   : Rscript scripts/check_setup.R
# Exit    : 0 = all checks passed; 1 = one or more FAIL items
# =============================================================================

source("config.R")
config <- get_etl_config()

ok   <- function(msg) message("[OK]   ", msg)
warn <- function(msg) message("[WARN] ", msg)
fail <- function(msg) { message("[FAIL] ", msg); assign("has_fail", TRUE, envir = .GlobalEnv) }

has_fail <- FALSE

# ---- config.R placeholders --------------------------------------------------
message("\n=== config.R ===")
placeholders <- c("YOUR_SOURCE_FILE.csv", "YOUR_CDM_SCHEMA", "YOUR_RESULTS_SCHEMA",
                  "YOUR_DATABASE", "YOUR_SOURCE_DESCRIPTION", "YOUR_INSTITUTION",
                  "YYYY-MM-DD")
cfg_str <- paste(unlist(config), collapse = "|")
if (any(sapply(placeholders, function(p) grepl(p, cfg_str, fixed = TRUE)))) {
  fail("config.R still contains YOUR_* or placeholder values")
} else {
  ok("config.R — no placeholder values found")
}
if (file.exists(file.path(config$source_dir, config$source_file))) {
  ok(paste0("Source file found: ", file.path(config$source_dir, config$source_file)))
} else {
  warn(paste0("Source file not found: ", file.path(config$source_dir, config$source_file),
              " (expected at runtime — OK if staged data already exists)"))
}

# ---- mappings ---------------------------------------------------------------
message("\n=== mappings/ ===")
field_map <- tryCatch(read.csv("mappings/field_map.csv", stringsAsFactors = FALSE),
                      error = function(e) { fail("mappings/field_map.csv unreadable"); NULL })
if (!is.null(field_map)) {
  zero_ids <- sum(field_map$concept_id == 0 | field_map$concept_id == "", na.rm = TRUE)
  if (zero_ids > 0) fail(paste0(zero_ids, " rows in field_map.csv have concept_id = 0 or blank"))
  else ok("field_map.csv — no zero or blank concept IDs")
  placeholder_rows <- sum(grepl("YOUR_", field_map$source_field))
  if (placeholder_rows > 0) fail(paste0(placeholder_rows, " placeholder rows remain in field_map.csv"))
  else ok("field_map.csv — no YOUR_* placeholder field names")
}

value_map <- tryCatch(read.csv("mappings/value_map.csv", stringsAsFactors = FALSE),
                      error = function(e) { fail("mappings/value_map.csv unreadable"); NULL })
if (!is.null(value_map)) {
  unverified <- sum(value_map$concept_source == "[pretraining]", na.rm = TRUE)
  if (unverified > 0) warn(paste0(unverified, " rows in value_map.csv still tagged [pretraining] — run vocab queries"))
  else ok("value_map.csv — all concept IDs tagged [vocab query]")
}

# ---- R modules --------------------------------------------------------------
message("\n=== R/ modules ===")
modules <- c("R/stage_raw.R", "R/map_person.R", "R/map_visit.R",
             "R/map_procedure.R", "R/map_condition.R",
             "R/map_observation.R", "R/map_measurement.R")
for (m in modules) {
  if (!file.exists(m)) { fail(paste0(m, " missing")); next }
  content <- paste(readLines(m), collapse = "\n")
  todo_count <- length(gregexpr("YOUR_", content)[[1]])
  if (todo_count > 0) warn(paste0(m, " — ", todo_count, " YOUR_* placeholder(s) remaining"))
  else ok(paste0(m, " — no YOUR_* placeholders"))
}

# ---- docs -------------------------------------------------------------------
message("\n=== docs/ ===")
for (f in c("docs/etl_spec.md", "docs/mapping_decisions.md")) {
  if (file.exists(f)) ok(paste0(f, " present"))
  else warn(paste0(f, " missing — create before first ETL run"))
}

# ---- result -----------------------------------------------------------------
message("")
if (has_fail) {
  message("Result: FAIL — address items above before running workflow/03_run_etl.R")
  quit(status = 1)
} else {
  message("Result: PASS — ready to run workflow/03_run_etl.R")
  quit(status = 0)
}
