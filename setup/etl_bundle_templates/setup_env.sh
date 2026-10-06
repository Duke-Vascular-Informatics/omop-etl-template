#!/usr/bin/env bash
# =============================================================================
# setup_env.sh — Step 1 of 2: verify the Java environment for this ETL bundle
#
# Run once per session, before installing R packages or running the ETL.
#
# This template is environment-agnostic: it only checks that a suitable Java is
# available. Anything specific to your secure environment (loading a module
# system, activating a conda env, obtaining a Kerberos ticket, ...) belongs in
# an optional `site_env.sh` placed next to this script. If present it is
# sourced first by setup_env.sh, install_r_packages.sh and run_etl.sh, so put
# only idempotent environment setup there. It is gitignored by the bundle
# builder because it is site-specific.
#
# Example site_env.sh:
#   module load R java
#   export JAVA_HOME=/path/to/jdk-17
#
# SEQUENCE (first time):
#   bash setup_env.sh           # Step 1 — Java
#   bash install_r_packages.sh  # Step 2 — R packages (first time only)
#   bash run_etl.sh
# =============================================================================

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BUNDLE_DIR"

echo ""
echo "======================================================================"
echo "  ETL environment check (Step 1 of 2)"
echo "  Bundle: $BUNDLE_DIR"
echo "======================================================================"
echo ""

# Optional site-specific hook (module loads, conda, Kerberos, ...).
if [[ -f "site_env.sh" ]]; then
  echo "Sourcing site_env.sh ..."
  # shellcheck disable=SC1091
  source site_env.sh
fi

if ! command -v java >/dev/null 2>&1; then
  echo "ERROR: java not found on PATH. Install Java 17 (or provide it via"
  echo "       site_env.sh) and re-run."
  exit 1
fi

echo "JAVA_HOME     = ${JAVA_HOME:-<not set>}"
echo "java -version : $(java -version 2>&1 | head -1)"
if ! command -v Rscript >/dev/null 2>&1; then
  echo "WARNING: Rscript not found on PATH — provide R via site_env.sh."
else
  echo "Rscript       : $(command -v Rscript)"
fi

cat <<SUMMARY

======================================================================
  Environment check complete.

  NEXT STEPS:
    First time:   bash install_r_packages.sh
    Then:         cp .env.example .env   # if not done; fill in values
                  bash run_etl.sh
======================================================================
SUMMARY
