# =============================================================================
# R/resolve_ltf_ids.R
# Purpose : Resolve person_id for each INFRA_LTF staged row by joining to the
#           already-loaded PROC visit_occurrence records, and assign a unique
#           deterministic visit_occurrence_id to each LTF row.
#
#           This function MUST run before any LTF map_*.R module because all
#           domain mappers expect person_id and visit_occurrence_id to be
#           present in the base data frame.
#
# Inputs  : staged          — staged INFRA_LTF data frame (from stage_raw.R),
#                             must contain PRIMPROCID and LTF_ID columns
#           config          — ETL config list (get_etl_config())
#           connection_details — DatabaseConnector connection details
#
# Outputs : staged data frame with eight columns added:
#             person_id          — resolved from visit_occurrence via PRIMPROCID
#             proc_date          — visit_start_date of the index PROC visit
#                                  (needed by all LTF map_*.R to compute dates)
#             proc_side          — "R" or "L" — operated side from the PROC
#                                  bypass procedure row (modifier_concept_id
#                                  4080761=Right / 4300877=Left). NA when the
#                                  GRAFTORIG procedure row is missing. Used by
#                                  map_ltf_measurement.R to select lateralised
#                                  measurement_concept_id for ipsilateral
#                                  variables (ABI, TBI, toe pressure).
#             visit_occurrence_id — config$ltf_visit_id_offset + LTF_ID
#                                   (deterministic: same record always gets the
#                                   same ID across ETL runs; preferred over
#                                   row_number() which depends on sort order)
#             visit_source_value — "{source_file_tag}:{LTF_ID}" — provenance tag
#                                   for map_ltf_visit.R; mirrors PROC convention
#             ltf_date           — proc_date + LTF_DAYS; the follow-up contact
#                                  date used as visit_start_date in map_ltf_visit.R
#             d30_readmit_visit_id — config$d30_visit_id_offset + LTF_ID when
#                                  D30_ADMIT_SINCE_DISC > 0; NA otherwise.
#                                  Deterministic inpatient visit ID for the
#                                  30-day readmission event.
#             d30_date           — proc_date + D30_DAYS; visit_start_date of
#                                  the readmission visit. NA when D30_DAYS is
#                                  missing or D30_ADMIT_SINCE_DISC = 0.
#
# Side effects:
#   - Warns on PRIMPROCID values with no matching PROC visit (records that
#     appear in the LTF file but whose index procedure was not loaded, e.g.
#     from a different registry arm or a data release mismatch).
#   - These unmatched rows are DROPPED and do not proceed to map_*.R.
#     An unmatched LTF row has no valid person_id and cannot be written to
#     any OMOP table; attempting to insert it would violate FK constraints.
#
# Design note — why sequential IDs rather than offset + PRIMPROCID?
#   Multiple LTF records share the same PRIMPROCID (multiple follow-up time
#   points per procedure). A single offset + PRIMPROCID would collide.
#   Sequential row_number() within a stable sort order (PRIMPROCID, then a
#   follow-up date column when available) produces unique, deterministic IDs
#   for a given data release.
# =============================================================================

library(DatabaseConnector)
library(dplyr)
library(SqlRender)
source("R/connection.R")

resolve_ltf_ids <- function(staged, config, connection_details) {

  stopifnot("PRIMPROCID" %in% names(staged))
  stopifnot("LTF_ID"     %in% names(staged))

  # ---------------------------------------------------------------------------
  # Collection-start gate
  # All INFRA_LTF variables (except PRIMPROCID which is a join key from INFRA_PROC)
  # began collection on 2009-08-31. LTF records with ltf_date before this date
  # are unexpected and likely reflect data quality issues.
  # Note: ltf_date is not yet computed at this point; we gate on proc_date as a
  # conservative proxy. The ltf_date gate is re-applied after ltf_date is derived.
  # ---------------------------------------------------------------------------
  ltf_collection_start <- as.Date("2009-08-31")

  # ---------------------------------------------------------------------------
  # Step 1: Fetch PRIMPROCID → person_id mapping from visit_occurrence.
  # PROC visits have visit_source_value = "{source_file_tag}:{PRIMPROCID}",
  # e.g. "INFRA_PROC_20231201:12345678". We extract the PRIMPROCID token by
  # splitting on ":" and matching the right-hand side.
  # Only rows whose leading tag starts with "INFRA_PROC" are considered
  # (ignores any SUPRA_PROC rows that may be in the same schema).
  # ---------------------------------------------------------------------------
  message("resolve_ltf_ids: fetching PRIMPROCID → person_id and laterality mapping")

  proc_id_map <- with_connection(connection_details, function(conn) {
    # Join visit_occurrence to procedure_occurrence to resolve person_id,
    # proc_date, and the operated side (SIDE variable from PROC, stored as
    # modifier_concept_id = 4080761 Right or 4300877 Left on the main bypass
    # procedure row identified by procedure_source_value LIKE 'GRAFTORIG=%').
    sql <- SqlRender::render(
      "SELECT vo.person_id,
              vo.visit_start_date AS proc_date,
              CAST(SUBSTRING(vo.visit_source_value,
                             CHARINDEX(':', vo.visit_source_value) + 1,
                             LEN(vo.visit_source_value)) AS BIGINT) AS PRIMPROCID,
              -- Laterality from the main bypass procedure row
              po.modifier_concept_id AS side_concept_id
       FROM @cdm_schema.visit_occurrence vo
       LEFT JOIN @cdm_schema.procedure_occurrence po
         ON po.visit_occurrence_id = vo.visit_occurrence_id
        AND po.procedure_source_value LIKE 'GRAFTORIG=%'
       WHERE vo.visit_source_value LIKE 'INFRA_PROC_%:%'",
      cdm_schema = config$cdm_schema
    )
    sql <- SqlRender::translate(sql, targetDialect = config$dbms)
    DatabaseConnector::querySql(conn, sql, snakeCaseToCamelCase = FALSE)
  })

  n_proc_visits <- nrow(proc_id_map)
  message("resolve_ltf_ids: found ", n_proc_visits,
          " INFRA_PROC visits in visit_occurrence")

  # Normalise column names returned by querySql (SQL Server returns uppercase)
  names(proc_id_map) <- tolower(names(proc_id_map))
  # Ensure proc_date is a Date (DatabaseConnector may return POSIXct)
  proc_id_map$proc_date <- as.Date(proc_id_map$proc_date)

  # Derive proc_side ("R" or "L") from side_concept_id.
  # modifier_concept_id 4080761 = Right [vocab query] SNOMED
  #                     4300877 = Left  [vocab query] SNOMED
  # NA when procedure_occurrence row not found or modifier not set.
  proc_id_map <- proc_id_map |>
    dplyr::mutate(
      proc_side = dplyr::case_when(
        side_concept_id == 4080761L ~ "R",  # [vocab query] SNOMED: Right
        side_concept_id == 4300877L ~ "L",  # [vocab query] SNOMED: Left
        .default = NA_character_
      )
    ) |>
    dplyr::select(-side_concept_id)

  # Warn on records where laterality could not be resolved
  n_no_side <- sum(is.na(proc_id_map$proc_side))
  if (n_no_side > 0) {
    warning("resolve_ltf_ids: ", n_no_side,
            " PROC visit(s) have no laterality resolved — ",
            "GRAFTORIG procedure row missing or modifier_concept_id unset; ",
            "LTF ipsilateral measurements for these records will use ",
            "non-lateralised concept IDs as fallback")
  }

  # ---------------------------------------------------------------------------
  # Step 2: Join staged LTF data to the mapping.
  # ---------------------------------------------------------------------------
  staged_joined <- staged |>
    dplyr::mutate(PRIMPROCID_key = as.numeric(PRIMPROCID)) |>
    dplyr::left_join(
      proc_id_map |> dplyr::rename(PRIMPROCID_key = primprocid),
      by = "PRIMPROCID_key"
    ) |>
    dplyr::select(-PRIMPROCID_key)

  # ---------------------------------------------------------------------------
  # Step 3: Warn and drop unmatched rows (no person_id resolved).
  # ---------------------------------------------------------------------------
  n_unmatched <- sum(is.na(staged_joined$person_id))
  if (n_unmatched > 0) {
    unmatched_ids <- staged_joined |>
      dplyr::filter(is.na(person_id)) |>
      dplyr::pull(PRIMPROCID) |>
      unique()
    warning("resolve_ltf_ids: ", n_unmatched, " LTF row(s) have no matching ",
            "PROC visit_occurrence record and will be DROPPED. ",
            "Unmatched PRIMPROCID count: ", length(unmatched_ids), ". ",
            "This typically means the index procedure was not loaded (different ",
            "data release or registry arm). Check that INFRA_PROC was loaded ",
            "before INFRA_LTF for the same release date.")
    staged_joined <- staged_joined |> dplyr::filter(!is.na(person_id))
  }

  message("resolve_ltf_ids: ", nrow(staged_joined),
          " LTF rows matched to a person_id (",
          n_unmatched, " dropped)")

  # ---------------------------------------------------------------------------
  # Step 4: Assign sequential visit_occurrence_id.
  # Sort by PRIMPROCID first so that follow-up records for the same procedure
  # receive consecutive IDs. A secondary sort key (e.g. follow-up date) will
  # be added here once that variable is known from the LTF data dictionary.
  # ---------------------------------------------------------------------------
  # QC: LTF_DAYS range checks (applied to matched rows only)
  if ("LTF_DAYS" %in% names(staged_joined)) {
    ltf_days_num <- as.numeric(staged_joined$LTF_DAYS)

    n_ltf_neg <- sum(!is.na(ltf_days_num) & ltf_days_num < 0, na.rm = TRUE)
    if (n_ltf_neg > 0) {
      warning("resolve_ltf_ids: ", n_ltf_neg,
              " LTF row(s) have LTF_DAYS < 0 (follow-up date before procedure) — ",
              "rows retained; review source data for date entry errors")
    }

    n_ltf_zero <- sum(!is.na(ltf_days_num) & ltf_days_num == 0, na.rm = TRUE)
    if (n_ltf_zero > 0) {
      warning("resolve_ltf_ids: ", n_ltf_zero,
              " LTF row(s) have LTF_DAYS = 0 (same-day follow-up) — ",
              "unusual for longitudinal follow-up; review for sentinel value usage")
    }

    n_ltf_long <- sum(!is.na(ltf_days_num) & ltf_days_num > 3650, na.rm = TRUE)
    if (n_ltf_long > 0) {
      warning("resolve_ltf_ids: ", n_ltf_long,
              " LTF row(s) have LTF_DAYS > 3650 (> 10 years post-procedure) — ",
              "rows retained; confirm this is plausible for the data release")
    }
  }

  # QC: LTF_ID must be unique within the file
  n_dup_ltf_id <- sum(duplicated(as.numeric(staged_joined$LTF_ID)), na.rm = TRUE)
  if (n_dup_ltf_id > 0) {
    stop("resolve_ltf_ids: ", n_dup_ltf_id,
         " duplicate LTF_ID value(s) found in staged data. ",
         "LTF_ID must be unique per record — cannot safely derive visit_occurrence_id.")
  }
  n_na_ltf_id <- sum(is.na(staged_joined$LTF_ID))
  if (n_na_ltf_id > 0) {
    stop("resolve_ltf_ids: ", n_na_ltf_id,
         " NA LTF_ID value(s) found. All LTF rows must have a valid LTF_ID.")
  }

  staged_joined <- staged_joined |>
    dplyr::mutate(
      # Deterministic ID: same LTF record always gets the same visit_occurrence_id
      # across ETL runs, regardless of row order in the file.
      visit_occurrence_id = as.integer(config$ltf_visit_id_offset + as.integer(LTF_ID)),

      # Provenance tag: mirrors PROC pattern "{source_file_tag}:{PRIMPROCID}"
      # but uses LTF_ID (the unique LTF record identifier) rather than PRIMPROCID
      # (which is not unique within the LTF file). PRIMPROCID linkage is preserved
      # through person_id (resolved above).
      visit_source_value = paste0(source_file, ":", LTF_ID),

      # Compute follow-up contact date; NA when LTF_DAYS is missing.
      # map_ltf_visit.R will handle the fallback — proc_date alone is used.
      ltf_date = if ("LTF_DAYS" %in% names(staged_joined))
                   proc_date + as.integer(LTF_DAYS)
                 else
                   as.Date(NA)
    )

  # ---------------------------------------------------------------------------
  # Derive D30 readmission visit ID and date.
  # Only populated when D30_ADMIT_SINCE_DISC > 0 (readmission occurred).
  # d30_readmit_visit_id = config$d30_visit_id_offset + LTF_ID (deterministic;
  #   non-overlapping with ltf_visit_id_offset + LTF_ID range).
  # d30_date = proc_date + D30_DAYS (actual readmission date; NA when D30_DAYS
  #   is missing — map_ltf_visit.R will use ltf_date as fallback).
  # ---------------------------------------------------------------------------
  if ("D30_ADMIT_SINCE_DISC" %in% names(staged_joined) &&
      "D30_DAYS" %in% names(staged_joined)) {

    staged_joined <- staged_joined |>
      dplyr::mutate(
        d30_readmit_visit_id = dplyr::if_else(
          !is.na(D30_ADMIT_SINCE_DISC) & as.integer(D30_ADMIT_SINCE_DISC) > 0L,
          as.integer(config$d30_visit_id_offset + as.integer(LTF_ID)),
          NA_integer_
        ),
        d30_date = dplyr::if_else(
          !is.na(D30_ADMIT_SINCE_DISC) & as.integer(D30_ADMIT_SINCE_DISC) > 0L &
            !is.na(D30_DAYS),
          proc_date + as.integer(D30_DAYS),
          as.Date(NA)
        )
      )

    # Sanity check: D30 visit IDs must be within the reserved range
    valid_d30_ids <- staged_joined$d30_readmit_visit_id[
      !is.na(staged_joined$d30_readmit_visit_id)
    ]
    if (length(valid_d30_ids) > 0 &&
        max(valid_d30_ids) >= config$d30_visit_id_offset + 5000000L) {
      stop("resolve_ltf_ids: d30_readmit_visit_id exceeds reserved D30 range ",
           "(", config$d30_visit_id_offset, " – ",
           config$d30_visit_id_offset + 4999999L, "). LTF_ID values exceed 5M.")
    }

    n_d30 <- sum(!is.na(staged_joined$d30_readmit_visit_id))
    message("resolve_ltf_ids: ", n_d30,
            " D30 readmission visit IDs assigned (D30_ADMIT_SINCE_DISC > 0)")

  } else {
    # D30 variables not present in this LTF file — add NA columns
    staged_joined <- staged_joined |>
      dplyr::mutate(
        d30_readmit_visit_id = NA_integer_,
        d30_date             = as.Date(NA)
      )
  }

  # QC: collection-start gate — ltf_date before 2009-08-31 is unexpected
  # (all LTF variables except PRIMPROCID started collection on this date)
  n_ltf_before_start <- sum(
    !is.na(staged_joined$ltf_date) &
      staged_joined$ltf_date < ltf_collection_start,
    na.rm = TRUE
  )
  if (n_ltf_before_start > 0) {
    warning("resolve_ltf_ids: ", n_ltf_before_start,
            " LTF row(s) have ltf_date (proc_date + LTF_DAYS) before ",
            "2009-08-31 (INFRA_LTF collection start) — ",
            "rows retained; review source data for unexpected early records")
  }

  # Sanity check: IDs must be within the reserved LTF range
  max_ltf_visit_id <- config$ltf_visit_id_offset + 9999999L
  if (max(staged_joined$visit_occurrence_id, na.rm = TRUE) > max_ltf_visit_id) {
    stop("resolve_ltf_ids: visit_occurrence_id exceeds reserved INFRA_LTF range ",
         "(", config$ltf_visit_id_offset, " – ", max_ltf_visit_id, "). ",
         "LTF_ID values are larger than the reserved block allows.")
  }

  message("resolve_ltf_ids: assigned visit_occurrence_ids from LTF_ID; ",
          "range ", min(staged_joined$visit_occurrence_id), " – ",
          max(staged_joined$visit_occurrence_id))

  invisible(staged_joined)
}
