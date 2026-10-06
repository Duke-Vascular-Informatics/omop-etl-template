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
    #      e.g. "REGISTRY_INDEX_20231201:12345678"
    #
    # Because all OMOP domain rows carry visit_occurrence_id, any row in any
    # OMOP table can be traced back to its source flat file AND data release
    # by joining to visit_occurrence and reading visit_source_value.
    #
    # Format: {REGISTRY}_{FILETYPE}_{YYYYMMDD}
    #   REGISTRY  — short identifier for the source registry
    #   FILETYPE  — INDEX (index file), FOLLOWUP (longitudinal follow-up), etc.
    #   YYYYMMDD  — data release date as it appears in the source file name
    #
    # Examples:
    #   REGISTRY_INDEX_20231201     — index file, December 2023 release
    #   REGISTRY_FOLLOWUP_20231201  — follow-up file, December 2023 release
    #
    # Follow-up files should create their own visit_occurrence rows (follow-up
    # visits) so that follow-up observations/measurements carry
    # "REGISTRY_FOLLOWUP_YYYYMMDD:ID" rather than "REGISTRY_INDEX_YYYYMMDD:ID",
    # keeping provenance unambiguous.
    #
    # Set via environment variable so the same config works for all files:
    #   ETL_SOURCE_FILE_TAG=REGISTRY_INDEX_20231201 Rscript run_etl.R
    source_file_tag = Sys.getenv("ETL_SOURCE_FILE_TAG", unset = "REGISTRY_INDEX_YYYYMMDD"),

    # -------------------------------------------------------------------------
    # Person / visit ID offsets — reserved ranges
    # -------------------------------------------------------------------------
    # Assign non-overlapping integer ranges when multiple registries or file
    # types load into the same CDM schema. Ranges are partitioned by source and
    # file type. Index files produce both new person records and index-visit
    # records (1:1); follow-up files, if you load them, produce only new visit
    # records, and person_ids must be resolved from already-loaded index visits
    # (write a resolver for your registry's patient-ID key).
    #
    # Example partition table (10 million rows each):
    #
    #   Range                    File type         person_id   visit_occurrence_id
    #   ─────────────────────────────────────────────────────────────────────────
    #   10,000,000 – 19,999,999  REGISTRY_INDEX    YES         YES (1:1 with person)
    #   110,000,000–114,999,999  REGISTRY_FOLLOWUP NO (reuse)  YES (offset + source ID)
    #
    # Leave clear separation between blocks and room for future sources.

    # Offset added to source patient IDs to avoid collisions with other sources.
    # Must be unique per ETL source if multiple sources load into one CDM instance.
    person_id_offset = 10000000L,
    visit_id_offset  = 10000000L,

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
