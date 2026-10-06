#!/usr/bin/env bash
# =============================================================================
# workflow/05_build_etl_bundle.sh
#
# Builds a self-contained, transportable bundle of this ETL for execution in a
# secure analytic environment that cannot reach this development workspace
# (no workspace, no internet, no source data here).
#
# This script is intentionally environment-agnostic. Anything specific to one
# institution's secure environment (module systems, Kerberos/conda wrappers,
# proprietary JDBC wrapper JARs, site GitLab routing) belongs in your own
# site-deploy repo or in the optional `site_env.sh` hook described below.
#
# CONFIGURATION — environment variables (set in your shell, or in
# <workspace>/.env, which is loaded automatically if present):
#
#   ETL_BUNDLE_NAME        Name of the bundle directory/zip. Default: this
#                          repo's folder name.
#   ETL_BUNDLE_REMOTE      Git remote URL to push the bundle to (optional).
#                          Unset or CHANGE_ME => dry run: the bundle is built
#                          and committed locally but not pushed.
#   BUNDLE_GIT_USER_NAME   git user.name for bundle commits (optional).
#   BUNDLE_GIT_USER_EMAIL  git user.email for bundle commits (optional).
#   CRAN_MIRROR            CRAN mirror baked into the bundle's .env.example.
#                          Default: https://cloud.r-project.org
#   JDBC_JAR_DIR           Directory searched for mssql-jdbc-*.jre11.jar.
#                          Default: the workspace's synthea-omop-template
#                          driver cache (see R/drivers.R there).
#
# WHAT THIS SCRIPT DOES:
#   1. Copies the ETL source (R/, config.R, mappings/) into portable/<name>/
#   2. Copies the MSSQL JDBC JAR into portable/<name>/drivers/
#   3. Seeds one-time setup files from setup/etl_bundle_templates/ (never
#      overwritten on later runs, so site edits survive a rebuild)
#   4. Generates .env.example with the variables config.R reads
#   5. Commits the bundle (and pushes it, if ETL_BUNDLE_REMOTE is set)
#   6. Writes a dated zip into dist/ as an offline fallback
#
# ON THE TARGET ENVIRONMENT (after the bundle is delivered):
#   cd <name>
#   cp .env.example .env      # fill in connection, schema and source paths
#   bash setup_env.sh         # verify Java (+ run optional site_env.sh)
#   bash install_r_packages.sh # first time only
#   # place the source flat-file CSV in data/raw/
#   bash run_etl.sh --file-tag REGISTRY_INDEX_20231201 --csv registry_index_20231201.csv
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

BUNDLE_BRANCH="main"

# ---------------------------------------------------------------------------
# Load the workspace .env (if any) for remote / identity / mirror settings.
# Values already exported in the calling shell are overridden by the file, so
# keep per-run overrides out of .env.
# ---------------------------------------------------------------------------
WORKSPACE_ENV="$WORKSPACE_ROOT/.env"
if [[ -f "$WORKSPACE_ENV" ]]; then
  set -o allexport
  # shellcheck disable=SC1090
  source "$WORKSPACE_ENV"
  set +o allexport
fi

BUNDLE_NAME="${ETL_BUNDLE_NAME:-$(basename "$REPO_ROOT")}"
BUNDLE_DIR="$REPO_ROOT/portable/$BUNDLE_NAME"
ETL_BUNDLE_REMOTE="${ETL_BUNDLE_REMOTE:-CHANGE_ME}"
BUNDLE_GIT_USER_NAME="${BUNDLE_GIT_USER_NAME:-${GIT_AUTHOR_NAME:-}}"
BUNDLE_GIT_USER_EMAIL="${BUNDLE_GIT_USER_EMAIL:-${GIT_AUTHOR_EMAIL:-}}"
CRAN_MIRROR="${CRAN_MIRROR:-https://cloud.r-project.org}"
JDBC_JAR_DIR="${JDBC_JAR_DIR:-$WORKSPACE_ROOT/synthea-omop-template/drivers/jdbc-runtime}"

echo ""
echo "======================================================================"
echo "  $BUNDLE_NAME ETL — Build Transportable Bundle"
echo "  Repo root : $REPO_ROOT"
echo "  Bundle    : $BUNDLE_DIR"
echo "  Remote    : $ETL_BUNDLE_REMOTE"
echo "======================================================================"
echo ""

# ---------------------------------------------------------------------------
# Decide dry-run vs push
# ---------------------------------------------------------------------------
if [[ "$ETL_BUNDLE_REMOTE" == "CHANGE_ME" || -z "$ETL_BUNDLE_REMOTE" ]]; then
  echo "[note] ETL_BUNDLE_REMOTE is not set — dry run (bundle built and"
  echo "       committed locally, not pushed). Create the remote repository,"
  echo "       set ETL_BUNDLE_REMOTE, and re-run to push."
  echo ""
  DRY_RUN=true
else
  DRY_RUN=false
fi

# ---------------------------------------------------------------------------
# Step 1 — Sync ETL source files into the bundle directory
# ---------------------------------------------------------------------------
echo "[Step 5/1] Syncing ETL source files ..."

mkdir -p "$BUNDLE_DIR/R" "$BUNDLE_DIR/mappings" "$BUNDLE_DIR/data/raw" \
         "$BUNDLE_DIR/data/staged" "$BUNDLE_DIR/drivers" "$BUNDLE_DIR/output"

# --delete keeps the bundle's R/ an exact mirror of the source modules.
rsync -a --delete "$REPO_ROOT/R/"       "$BUNDLE_DIR/R/"
rsync -a          "$REPO_ROOT/config.R" "$BUNDLE_DIR/"

# Mapping reference files (small, no source data).
for f in field_map.csv value_map.csv vocab_gaps.csv; do
  [[ -f "$REPO_ROOT/mappings/$f" ]] && rsync -a "$REPO_ROOT/mappings/$f" "$BUNDLE_DIR/mappings/"
done

# renv lockfile, if the workspace pins one.
if [[ -f "$WORKSPACE_ROOT/renv.lock" ]]; then
  cp -f "$WORKSPACE_ROOT/renv.lock" "$BUNDLE_DIR/"
  echo "  renv.lock -> bundle/"
fi

echo "  R/ modules  : $(ls "$BUNDLE_DIR/R/" | wc -l | tr -d ' ') files"
echo "  mappings/   : $(ls "$BUNDLE_DIR/mappings/" | wc -l | tr -d ' ') files"

# ---------------------------------------------------------------------------
# Step 2 — JDBC JAR
# ---------------------------------------------------------------------------
echo "[Step 5/2] Syncing MSSQL JDBC JAR ..."

JDBC_JAR=$(find "$JDBC_JAR_DIR" -name "mssql-jdbc-*.jre11.jar" 2>/dev/null | head -1 || true)

if [[ -z "$JDBC_JAR" ]]; then
  echo "  [WARN] JDBC JAR not found under $JDBC_JAR_DIR — skipping."
  echo "         Set JDBC_JAR_DIR, or add the jar to bundle/drivers/ manually."
else
  cp -f "$JDBC_JAR" "$BUNDLE_DIR/drivers/"
  echo "  $(basename "$JDBC_JAR") -> bundle/drivers/"
fi

# ---------------------------------------------------------------------------
# Step 3 — Seed one-time files (never overwrite if already present)
# ---------------------------------------------------------------------------
echo "[Step 5/3] Seeding setup templates (first run only) ..."

TEMPLATES="$REPO_ROOT/setup/etl_bundle_templates"

seed_file() {
  local src="$TEMPLATES/$1"
  local dest="$BUNDLE_DIR/$1"
  if [[ ! -f "$dest" ]]; then
    cp "$src" "$dest"
    chmod +x "$dest" 2>/dev/null || true
    echo "  Seeded: $1"
  else
    echo "  Kept  : $1 (already exists)"
  fi
}

seed_file "setup_env.sh"
seed_file "install_r_packages.sh"
seed_file "install_packages.R"
seed_file "run_etl.sh"
seed_file "run_etl.R"

# .gitignore — data and secrets never committed
if [[ ! -f "$BUNDLE_DIR/.gitignore" ]]; then
  cat > "$BUNDLE_DIR/.gitignore" << 'GITIGNORE'
# Secrets and site-specific hooks
.env
site_env.sh

# Source data (stays in the secure environment)
data/raw/
data/staged/

# ETL outputs
output/

# R session files
.Rhistory
.RData
*.Rproj
GITIGNORE
  echo "  Seeded: .gitignore"
fi

# ---------------------------------------------------------------------------
# Step 4 — Generate .env.example (variables read by config.R)
# ---------------------------------------------------------------------------
echo "[Step 5/4] Generating .env.example ..."

cat > "$BUNDLE_DIR/.env.example" << ENVTEMPLATE
# =============================================================================
# .env — $BUNDLE_NAME ETL
#
# Copy to .env and fill in your values before running the ETL.
# NEVER commit .env to the repository.
# =============================================================================

# CRAN mirror reachable from this environment
CRAN_MIRROR=${CRAN_MIRROR}

# -----------------------------------------------------------------------------
# Source data
# -----------------------------------------------------------------------------
# Directory containing the source flat-file CSV(s) (absolute path)
ETL_SOURCE_DIR=/path/to/source/data/raw

# Flat-file provenance tag — identifies the specific file and data release.
# Format: {REGISTRY}_{FILETYPE}_{YYYYMMDD}
# Examples: REGISTRY_INDEX_20231201  REGISTRY_FOLLOWUP_20231201
ETL_SOURCE_FILE_TAG=REGISTRY_INDEX_CHANGE_ME

# Exact CSV filename to load (must be present in ETL_SOURCE_DIR)
ETL_SOURCE_FILE=source_file_CHANGE_ME.csv

# Data release date (written into cdm_source table) and CDM holder
SOURCE_RELEASE_DATE=YYYY-MM-DD
CDM_HOLDER=YOUR_INSTITUTION

# -----------------------------------------------------------------------------
# Target OMOP CDM (the schema this ETL writes to) and shared vocabulary
# -----------------------------------------------------------------------------
OMOP_CDM_SCHEMA=CHANGE_ME
OMOP_RESULTS_SCHEMA=CHANGE_ME
OMOP_VOCAB_SCHEMA=omop_vocab

# -----------------------------------------------------------------------------
# SQL Server connection (read by config.R / R/connection.R)
# Default is SQL authentication. If your environment uses integrated or
# Kerberos authentication, adapt R/connection.R and use site_env.sh (see
# setup_env.sh) to obtain tickets before running.
# -----------------------------------------------------------------------------
MSSQL_SERVER=your.sqlserver.example.org
MSSQL_DATABASE=your_database
MSSQL_PORT=1433
MSSQL_USER=your_username
MSSQL_PASSWORD=
ENVTEMPLATE

echo "  .env.example written"

# ---------------------------------------------------------------------------
# Step 5 — Git commit and push (or dry run)
# ---------------------------------------------------------------------------
echo "[Step 5/5] Committing bundle ..."

cd "$BUNDLE_DIR"

if [[ ! -d ".git" ]]; then
  git init -b "$BUNDLE_BRANCH"
  [[ -n "$BUNDLE_GIT_USER_NAME" ]]  && git config user.name  "$BUNDLE_GIT_USER_NAME"
  [[ -n "$BUNDLE_GIT_USER_EMAIL" ]] && git config user.email "$BUNDLE_GIT_USER_EMAIL"
  echo "  Initialized new git repo"
fi

git add -A

if git diff --cached --quiet; then
  echo "  No changes to commit."
else
  COMMIT_MSG="chore: update ETL bundle $(date +%Y-%m-%d)"
  git commit -m "$COMMIT_MSG"
  echo "  Committed: $COMMIT_MSG"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "  [DRY RUN] Bundle built but NOT pushed."
else
  if git remote get-url origin &>/dev/null; then
    git remote set-url origin "$ETL_BUNDLE_REMOTE"
  else
    git remote add origin "$ETL_BUNDLE_REMOTE"
  fi

  git push --set-upstream origin "$BUNDLE_BRANCH"
  echo "  [OK] Pushed to $ETL_BUNDLE_REMOTE ($BUNDLE_BRANCH)"
fi

# ---------------------------------------------------------------------------
# Step 6 — Dated zip fallback
# ---------------------------------------------------------------------------
echo "[Step 5/6] Building dated zip fallback ..."

DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$DIST_DIR"
ZIP_NAME="${BUNDLE_NAME}-bundle-$(date +%Y%m%d).zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

cd "$REPO_ROOT/portable"
zip -qr "$ZIP_PATH" "$BUNDLE_NAME/" --exclude "$BUNDLE_NAME/.git/*"
echo "  Zip: $ZIP_PATH"

cd "$REPO_ROOT"

echo ""
echo "======================================================================"
echo "  Bundle build complete: $(date)"
echo ""
echo "  NEXT STEPS:"
if [[ "$DRY_RUN" == "true" ]]; then
echo "  1. Create a remote repository for the bundle (optional)."
echo "  2. Set ETL_BUNDLE_REMOTE and re-run to push, or deliver the zip above."
else
echo "  1. In the target environment: git clone --branch $BUNDLE_BRANCH $ETL_BUNDLE_REMOTE $BUNDLE_NAME"
fi
echo "  Then: cp .env.example .env && bash setup_env.sh && bash install_r_packages.sh"
echo "======================================================================"
