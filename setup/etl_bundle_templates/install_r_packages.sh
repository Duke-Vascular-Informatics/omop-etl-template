#!/usr/bin/env bash
# =============================================================================
# install_r_packages.sh — Step 2 of 2: install R packages for this ETL bundle
#
# Run after setup_env.sh. Packages persist between sessions in a user-writable
# R library (R_LIBS_USER), so this is a first-time step.
#
# Sources the optional site_env.sh hook (see setup_env.sh) so the same
# site-specific environment is active for compilation of rJava.
# =============================================================================

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BUNDLE_DIR"

echo ""
echo "======================================================================"
echo "  ETL R package installation (Step 2 of 2)"
echo "  Bundle: $BUNDLE_DIR"
echo "======================================================================"
echo ""

if [[ -f "site_env.sh" ]]; then
  # shellcheck disable=SC1091
  source site_env.sh
fi

# Load CRAN_MIRROR (and anything else) from .env if present.
if [[ -f ".env" ]]; then
  set -o allexport; source .env; set +o allexport
fi

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript not found on PATH (provide R via site_env.sh)."
  exit 1
fi

if [[ -z "${JAVA_HOME:-}" ]]; then
  # Derive JAVA_HOME from the java on PATH so rJava can find jni.h.
  JAVA_BIN="$(readlink -f "$(command -v java)" 2>/dev/null || true)"
  [[ -n "$JAVA_BIN" ]] && export JAVA_HOME="$(dirname "$(dirname "$JAVA_BIN")")"
fi
echo "JAVA_HOME = ${JAVA_HOME:-<not set>}"

# User-writable package library, keyed by R version/platform.
R_VERSION=$(Rscript -e "cat(paste(R.version\$major, R.version\$minor, sep='.'))" 2>/dev/null | tr -d ' ')
R_PLATFORM=$(Rscript -e "cat(R.version\$platform)" 2>/dev/null | tr -d ' ')
export R_LIBS_USER="${HOME}/R/${R_PLATFORM}-library/${R_VERSION%.*}"
mkdir -p "$R_LIBS_USER"
echo "R_LIBS_USER = $R_LIBS_USER"
echo ""

Rscript install_packages.R

echo ""
echo "R package installation complete. Next: bash run_etl.sh"
