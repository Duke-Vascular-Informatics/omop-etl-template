#!/usr/bin/env bash
# =============================================================================
# run_etl.sh — ETL launcher for the bundled ETL
#
# Run after setup_env.sh and install_r_packages.sh.
#
# USAGE:
#   bash run_etl.sh [--file-tag REGISTRY_INDEX_20231201] [--csv source_file_20231201.csv]
#
# OPTIONS:
#   --file-tag   Override ETL_SOURCE_FILE_TAG (default: value in .env)
#   --csv        Override ETL_SOURCE_FILE (default: value in .env)
#
# These can also be set permanently in .env — command-line flags take precedence.
# The optional site_env.sh hook (see setup_env.sh) is sourced first.
# =============================================================================

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BUNDLE_DIR"

FILE_TAG_OVERRIDE=""
CSV_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-tag) FILE_TAG_OVERRIDE="$2"; shift 2 ;;
    --csv)      CSV_OVERRIDE="$2";      shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -f "site_env.sh" ]]; then
  # shellcheck disable=SC1091
  source site_env.sh
fi

if [[ ! -f ".env" ]]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill in your values."
  exit 1
fi
set -o allexport; source .env; set +o allexport

[[ -n "$FILE_TAG_OVERRIDE" ]] && export ETL_SOURCE_FILE_TAG="$FILE_TAG_OVERRIDE"
[[ -n "$CSV_OVERRIDE" ]]      && export ETL_SOURCE_FILE="$CSV_OVERRIDE"

echo ""
echo "======================================================================"
echo "  ETL run"
echo "  Bundle    : $BUNDLE_DIR"
echo "  File tag  : ${ETL_SOURCE_FILE_TAG:-<not set>}"
echo "  CSV file  : ${ETL_SOURCE_FILE:-<not set>}"
echo "  CDM schema: ${OMOP_CDM_SCHEMA:-<not set>}"
echo "  Started   : $(date)"
echo "======================================================================"
echo ""

# Validate required settings (the variables config.R reads).
errors=0
for var in ETL_SOURCE_DIR ETL_SOURCE_FILE_TAG ETL_SOURCE_FILE \
           OMOP_CDM_SCHEMA MSSQL_SERVER MSSQL_DATABASE MSSQL_USER; do
  if [[ -z "${!var:-}" || "${!var}" == *"CHANGE_ME"* ]]; then
    echo "  [ERROR] $var is not set or still contains CHANGE_ME in .env"
    errors=$((errors + 1))
  fi
done
if [[ $errors -gt 0 ]]; then
  echo ""
  echo "Fix the above settings in .env before running."
  exit 1
fi

CSV_PATH="${ETL_SOURCE_DIR}/${ETL_SOURCE_FILE}"
if [[ ! -f "$CSV_PATH" ]]; then
  echo "ERROR: Source CSV not found: $CSV_PATH"
  echo "       Place the source flat-file CSV in: ${ETL_SOURCE_DIR}/"
  exit 1
fi

# rJava needs libjvm on the loader path on many Linux systems.
JVM_LIB=$(find "${JAVA_HOME:-/usr}" -name "libjvm.so" 2>/dev/null | head -1 || true)
JVM_LIB_DIR="${JVM_LIB:+$(dirname "$JVM_LIB")}"
export LD_LIBRARY_PATH="${JVM_LIB_DIR:+${JVM_LIB_DIR}:}${LD_LIBRARY_PATH:-}"

# Same user library that install_r_packages.sh populated.
R_VERSION=$(Rscript -e "cat(paste(R.version\$major, R.version\$minor, sep='.'))" 2>/dev/null | tr -d ' ')
R_PLATFORM=$(Rscript -e "cat(R.version\$platform)" 2>/dev/null | tr -d ' ')
export R_LIBS_USER="${HOME}/R/${R_PLATFORM}-library/${R_VERSION%.*}"

echo "Running ETL ..."
echo ""

Rscript run_etl.R

echo ""
echo "======================================================================"
echo "  ETL complete: $(date)"
echo "======================================================================"
