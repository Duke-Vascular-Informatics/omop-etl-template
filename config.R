# =============================================================================
# config.R
# Purpose : Single source of truth for all ETL runtime settings.
#           Replace every YOUR_* placeholder before running any module.
# Inputs  : Environment variables (set in .env or shell before sourcing)
# Outputs : get_etl_config() — named list consumed by all R/map_*.R modules
# =============================================================================

get_etl_config <- function() {

  list(

    # -------------------------------------------------------------------------
    # Source data paths (CSV exports — gitignored, local only)
    # -------------------------------------------------------------------------
    source_dir   = Sys.getenv("ETL_SOURCE_DIR",  unset = "data/raw"),
    source_file  = Sys.getenv("ETL_SOURCE_FILE", unset = "YOUR_SOURCE_FILE.csv"),
    staged_dir   = Sys.getenv("ETL_STAGED_DIR",  unset = "data/staged"),

    # -------------------------------------------------------------------------
    # Target OMOP CDM schema (SQL Server)
    # -------------------------------------------------------------------------
    cdm_schema     = Sys.getenv("OMOP_CDM_SCHEMA",     unset = "YOUR_CDM_SCHEMA"),
    vocab_schema   = Sys.getenv("OMOP_VOCAB_SCHEMA",   unset = "omop_vocab"),
    results_schema = Sys.getenv("OMOP_RESULTS_SCHEMA", unset = "YOUR_RESULTS_SCHEMA"),

    # -------------------------------------------------------------------------
    # Database connection (SQL Server via DatabaseConnector)
    # -------------------------------------------------------------------------
    dbms     = "sql server",
    server   = Sys.getenv("MSSQL_SERVER",   unset = "localhost"),
    port     = Sys.getenv("MSSQL_PORT",     unset = "1433"),
    database = Sys.getenv("MSSQL_DATABASE", unset = "YOUR_DATABASE"),
    user     = Sys.getenv("MSSQL_USER",     unset = "sa"),
    password = Sys.getenv("MSSQL_PASSWORD", unset = ""),

    # -------------------------------------------------------------------------
    # ETL settings
    # -------------------------------------------------------------------------
    # -------------------------------------------------------------------------
    # Registry identity — used for person_source_value tagging and cdm_source
    # -------------------------------------------------------------------------
    # Prefix prepended to the source patient ID in person_source_value so the
    # originating registry is queryable from any table that joins back to person.
    # Format written to person.person_source_value: "{REGISTRY_PREFIX}-{PATIENT_ID}"
    registry_prefix = "YOUR_REGISTRY",

    # -------------------------------------------------------------------------
    # Flat-file provenance tag — MANDATORY, set per ETL run
    # -------------------------------------------------------------------------
    # Identifies the exact source flat file AND data release date being loaded.
    # This value is:
    #   1. Stamped on every row of the staged data frame as the `source_file`
    #      column (see R/stage_raw.R).
    #   2. Written into visit_occurrence.visit_source_value as the leading
    #      token: "{source_file_tag}:{PATIENT_ID}"
    #      e.g. "REGISTRY_PROC_20231201:12345678"
    #
    # Because all OMOP domain rows carry visit_occurrence_id, any row in any
    # OMOP table can be traced back to its source flat file AND data release
    # by joining to visit_occurrence and reading visit_source_value.
    #
    # Format: {REGISTRY}_{FILETYPE}_{YYYYMMDD}
    #   REGISTRY  — short identifier for the source registry
    #   FILETYPE  — PROC (index procedure), LTF (longitudinal follow-up), etc.
    #   YYYYMMDD  — data release date as it appears in the source file name
    #
    # Examples:
    #   REGISTRY_PROC_20231201  — procedure file, December 2023 release
    #   REGISTRY_LTF_20231201   — follow-up file, December 2023 release
    #
    # LTF files should create their own visit_occurrence rows (follow-up visits)
    # so that follow-up observations/measurements carry "REGISTRY_LTF_YYYYMMDD:ID"
    # rather than "REGISTRY_PROC_YYYYMMDD:ID", keeping provenance unambiguous.
    #
    # Set via environment variable so the same config works for all files:
    #   ETL_SOURCE_FILE_TAG=REGISTRY_PROC_20231201 Rscript run_etl.R
    source_file_tag = Sys.getenv("ETL_SOURCE_FILE_TAG", unset = "REGISTRY_PROC_YYYYMMDD"),

    # -------------------------------------------------------------------------
    # Person / visit ID offsets — reserved ranges
    # -------------------------------------------------------------------------
    # Assign non-overlapping integer ranges when multiple registries load into
    # the same CDM schema. Ranges are partitioned by registry and file type.
    # PROC files produce both new person records and index-visit records (1:1).
    # LTF files produce only new follow-up visit records — person_ids are
    # resolved from already-loaded PROC visits via patient ID lookup
    # (see R/resolve_ltf_ids.R).
    #
    # Example partition table (10 million rows each):
    #
    #   Range                    File type      person_id   visit_occurrence_id
    #   ─────────────────────────────────────────────────────────────────────
    #   10,000,000 – 19,999,999  REGISTRY_PROC  YES         YES (1:1 with person)
    #   110,000,000–114,999,999  REGISTRY_LTF   NO (reuse)  YES (offset + LTF_ID)
    #   115,000,000–119,999,999  REGISTRY D30   NO (reuse)  YES (offset + LTF_ID)
    #
    # LTF ranges start at 110M+ to leave clear separation from PROC blocks
    # and room for future registry additions in the 20–99M space.

    # Offset added to source patient IDs to avoid collisions with other sources.
    # Must be unique per ETL source if multiple sources load into one CDM instance.
    person_id_offset = 10000000L,
    visit_id_offset  = 10000000L,

    # LTF follow-up visit and D30 readmission visit offsets (set to 0L if not
    # applicable; see R/resolve_ltf_ids.R for how these are used).
    ltf_visit_id_offset = 110000000L,  # LTF follow-up visit_ids: 110M – 114M
    d30_visit_id_offset = 115000000L,  # D30 readmission visit_ids: 115M – 119M
    # Note: ltf_visit_id_offset + LTF_ID and d30_visit_id_offset + LTF_ID
    # are both deterministic and non-overlapping provided LTF_ID < 5,000,000.

    # OMOP CDM version loaded into this instance
    cdm_version = "5.4",

    # ETL run metadata written to cdm_source table
    source_description  = "YOUR_SOURCE_DESCRIPTION",
    cdm_holder          = Sys.getenv("CDM_HOLDER",         unset = "YOUR_INSTITUTION"),
    source_release_date = Sys.getenv("SOURCE_RELEASE_DATE", unset = "YYYY-MM-DD"),

    # Output folder for ETL logs and QC reports (gitignored)
    output_folder = Sys.getenv("ETL_OUTPUT_DIR", unset = "output")
  )
}
