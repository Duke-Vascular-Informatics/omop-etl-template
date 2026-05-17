# =============================================================================
# workflow/02_validate_staged.R
# Purpose : Row counts, null checks, and value-set validation on staged data.
#           All checks print [OK] / [WARN] / [FAIL]; exit 1 on any FAIL.
# Run     : Rscript workflow/02_validate_staged.R
# TODO [MAPPING]: Add source-specific required fields and value-set checks
# =============================================================================
if (!exists("config")) { source("config.R"); config <- get_etl_config() }

staged_path <- file.path(config$staged_dir, "staged.rds")
if (!file.exists(staged_path)) stop("staged.rds not found — run workflow/01 first")
staged <- readRDS(staged_path)

has_fail <- FALSE
ok   <- function(msg) message("[OK]   ", msg)
fail <- function(msg) { message("[FAIL] ", msg); has_fail <<- TRUE }

message("Staged rows: ", nrow(staged))
if (nrow(staged) == 0) fail("staged.rds has zero rows")
else ok(paste0("Row count: ", nrow(staged)))

# TODO [MAPPING]: Add required-field null checks, e.g.:
# if (anyNA(staged$YOUR_PATIENT_ID_FIELD)) fail("person ID has NAs")
# if (anyNA(staged$YOUR_PROC_DATE_FIELD))  fail("procedure date has NAs")

if (has_fail) { message("Validation FAIL"); quit(status = 1) }
message("Validation PASS")
