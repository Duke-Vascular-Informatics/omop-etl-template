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
