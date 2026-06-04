#!/usr/bin/env Rscript
# =============================================================================
# install_packages.R — YOUR_ETL_NAME ETL bundle
#
# Installs all R packages required to run the YOUR_ETL_NAME → OMOP ETL pipeline.
# Do not run directly — use the wrapper: bash install_r_packages.sh
#
# All packages are available on CRAN. Uses the Duke CRAN mirror accessible
# from the protected research environment without external internet access.
# =============================================================================

options(repos = c(CRAN = "https://archive.linux.duke.edu/cran/"))

message("Installing R packages for YOUR_ETL_NAME ETL bundle ...")
message("CRAN mirror: ", getOption("repos")["CRAN"])

# ---------------------------------------------------------------------------
# Step 1 — Verify JAVA_HOME
# ---------------------------------------------------------------------------
java_home <- Sys.getenv("JAVA_HOME")
if (nchar(trimws(java_home)) == 0) {
  stop(
    "JAVA_HOME is not set.\n\n",
    "Do not run install_packages.R directly.\n",
    "Use the wrapper script instead:\n",
    "  bash install_r_packages.sh\n\n",
    "That script activates the openjdk conda environment."
  )
}

message("JAVA_HOME: ", java_home)

jni_header <- file.path(java_home, "include", "jni.h")
if (!file.exists(jni_header)) {
  stop("JDK header not found: ", jni_header,
       "\nVerify openjdk conda env installation.")
}
message("JDK headers found: ", jni_header)

lib_path <- .libPaths()[1]
message("Package library: ", lib_path)
if (!file.access(lib_path, mode = 2) == 0) {
  stop("R package library is not writable: ", lib_path,
       "\nUse 'bash install_r_packages.sh' which sets R_LIBS_USER.")
}

# ---------------------------------------------------------------------------
# Step 2 — Required packages (all CRAN)
# ---------------------------------------------------------------------------
etl_packages <- c(
  "DatabaseConnector",   # OMOP CDM JDBC connectivity (rJava dep auto-installed)
  "SqlRender",           # SQL parameterisation and dialect translation
  "dplyr",               # data manipulation
  "tidyr",               # pivot_longer / pivot_wider
  "readr",               # CSV I/O
  "lubridate",           # date arithmetic
  "stringr"              # string helpers
)

# ---------------------------------------------------------------------------
# Step 3 — Install missing packages
# ---------------------------------------------------------------------------
missing_packages <- etl_packages[
  !sapply(etl_packages, requireNamespace, quietly = TRUE)
]

if (length(missing_packages) == 0) {
  message("All packages already installed — nothing to do.")
} else {
  message("Installing ", length(missing_packages), " package(s): ",
          paste(missing_packages, collapse = ", "))
  install.packages(
    missing_packages,
    dependencies = c("Depends", "Imports", "LinkingTo"),
    lib          = lib_path
  )
}

# ---------------------------------------------------------------------------
# Step 4 — Verify
# ---------------------------------------------------------------------------
failed <- etl_packages[
  !sapply(etl_packages, requireNamespace, quietly = TRUE)
]

if (length(failed) > 0) {
  stop("Package(s) failed to install:\n",
       paste("  -", failed, collapse = "\n"))
}

message("")
message("All ", length(etl_packages), " ETL packages installed and verified.")
message("DatabaseConnector: ", as.character(packageVersion("DatabaseConnector")))
message("SqlRender        : ", as.character(packageVersion("SqlRender")))
message("")
message("Next steps:")
message("  1. Set ETL_SOURCE_DIR, ETL_SOURCE_FILE_TAG, ETL_SOURCE_FILE in .env")
message("  2. Set INST_OMOP_RESULTS_SCHEMA in .env (your dedicated ETL schema)")
message("  3. Place source flat-file CSV(s) in data/raw/")
message("  4. conda activate openjdk && bash run_etl.sh")
