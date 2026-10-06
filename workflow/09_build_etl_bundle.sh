#!/usr/bin/env bash
# =============================================================================
# workflow/09_build_etl_bundle.sh
#
# Builds and publishes the YOUR_ETL_NAME → OMOP ETL transportable bundle for
# execution in the protected research environment.
#
# PREREQUISITES — set in <workspace>/.env before running:
#
#   ETL_GITLAB_REMOTE    Full SSH URL of the target GitLab repo.
#                        e.g. git@gitlab.example.org:your-group/YOUR_ETL_NAME.git
#                        Set to CHANGE_ME until the GitLab repo is created.
#
#   BUNDLE_GIT_USER_NAME   Your name for bundle git commits.
#   BUNDLE_GIT_USER_EMAIL  Your institutional email for bundle git commits.
#
#   INST_OMOP_RESULTS_SCHEMA  Dedicated ETL write schema in the protected
#                              environment (set when your institution provides it).
#                              Format: schema_name  (e.g. my_source_etl)
#
#   CRAN_MIRROR          CRAN mirror reachable from the protected environment
#                        (already in .env; defaults to cloud.r-project.org).
#
# WHAT THIS SCRIPT DOES:
#   1. Copies all ETL source files into portable/YOUR_ETL_NAME/
#   2. Copies the MSSQL JDBC JAR into portable/YOUR_ETL_NAME/drivers/
#   3. Seeds one-time setup files from setup/etl_bundle_templates/ (never
#      overwritten on subsequent runs)
#   4. Generates .env from .env.example with protected-environment values
#      injected from the workspace .env
#   5. Commits the bundle and pushes to GitLab (main branch)
#   6. Creates a dated zip in dist/ as an offline fallback
#
# SEEDED FILES (from setup/etl_bundle_templates/, never overwritten):
#   setup_env.sh          Java + Kerberos setup (run once per session)
#   install_r_packages.sh R package installer wrapper
#   install_packages.R    R package installer
#   run_etl.sh            ETL launcher
#   run_etl.R             Ordered ETL entry point
#
# DEPLOYMENT ON PROTECTED RESEARCH ENVIRONMENT (after this script runs):
#   git clone --branch main <ETL_GITLAB_REMOTE> YOUR_ETL_NAME
#   cd YOUR_ETL_NAME
#   cp .env.example .env      # fill in schema, source paths, connection details
#   bash setup_env.sh         # Step 1: Java + Kerberos
#   bash install_r_packages.sh # Step 2: R packages (first time only)
#   # Place source flat-file CSV in data/raw/
#   conda activate openjdk
#   bash run_etl.sh --file-tag REGISTRY_INDEX_20231201 --csv registry_index_20231201.csv
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

BUNDLE_NAME="YOUR_ETL_NAME"
BUNDLE_DIR="$REPO_ROOT/portable/$BUNDLE_NAME"
BUNDLE_BRANCH="main"

# ---------------------------------------------------------------------------
# Load workspace .env for GitLab remote and institutional settings
# ---------------------------------------------------------------------------
WORKSPACE_ENV="$WORKSPACE_ROOT/.env"
if [[ -f "$WORKSPACE_ENV" ]]; then
  set -o allexport
  # shellcheck disable=SC1090
  source "$WORKSPACE_ENV"
  set +o allexport
fi

ETL_GITLAB_REMOTE="${ETL_GITLAB_REMOTE:-CHANGE_ME}"
BUNDLE_GIT_USER_NAME="${BUNDLE_GIT_USER_NAME:-${GIT_AUTHOR_NAME:-}}"
BUNDLE_GIT_USER_EMAIL="${BUNDLE_GIT_USER_EMAIL:-${GIT_AUTHOR_EMAIL:-}}"
CRAN_MIRROR="${CRAN_MIRROR:-https://cloud.r-project.org}"

echo ""
echo "======================================================================"
echo "  YOUR_ETL_NAME ETL — Build Transportable Bundle (Step 9)"
echo "  Repo root : $REPO_ROOT"
echo "  Bundle    : $BUNDLE_DIR"
echo "  GitLab    : $ETL_GITLAB_REMOTE"
echo "======================================================================"
echo ""

# ---------------------------------------------------------------------------
# Guard: abort if placeholder values are still set
# ---------------------------------------------------------------------------
if [[ "$ETL_GITLAB_REMOTE" == "CHANGE_ME" || -z "$ETL_GITLAB_REMOTE" ]]; then
  echo "[Step 9] WAITING: ETL_GITLAB_REMOTE is not set."
  echo ""
  echo "  This is expected until your GitLab repository is created."
  echo "  When ready:"
  echo "    1. Create the repo on GitLab."
  echo "    2. Add to <workspace>/.env:"
  echo "         ETL_GITLAB_REMOTE=git@gitlab.example.com:<username>/YOUR_ETL_NAME.git"
  echo "    3. Re-run this script."
  echo ""
  echo "  Continuing with dry-run (bundle directory populated but not pushed)."
  DRY_RUN=true
else
  DRY_RUN=false
fi

# ---------------------------------------------------------------------------
# Step 1 — Sync ETL source files into bundle directory
# ---------------------------------------------------------------------------
echo "[Step 9/1] Syncing ETL source files ..."

mkdir -p "$BUNDLE_DIR/R"
mkdir -p "$BUNDLE_DIR/mappings"
mkdir -p "$BUNDLE_DIR/data/raw"
mkdir -p "$BUNDLE_DIR/data/staged"
mkdir -p "$BUNDLE_DIR/drivers"
mkdir -p "$BUNDLE_DIR/output"

# Core ETL modules
rsync -a --delete "$REPO_ROOT/R/"        "$BUNDLE_DIR/R/"
rsync -a           "$REPO_ROOT/config.R"  "$BUNDLE_DIR/"

# Mapping reference files
rsync -a "$REPO_ROOT/mappings/field_map.csv"  "$BUNDLE_DIR/mappings/"
rsync -a "$REPO_ROOT/mappings/vocab_gaps.csv" "$BUNDLE_DIR/mappings/"

# renv lockfile (from workspace root — ETL uses workspace packages)
if [[ -f "$WORKSPACE_ROOT/renv.lock" ]]; then
  cp -f "$WORKSPACE_ROOT/renv.lock" "$BUNDLE_DIR/"
  echo "  renv.lock -> bundle/"
fi

echo "  R/ modules  : $(ls "$BUNDLE_DIR/R/" | wc -l | tr -d ' ') files"
echo "  mappings/   : $(ls "$BUNDLE_DIR/mappings/" | wc -l | tr -d ' ') files"

# ---------------------------------------------------------------------------
# Step 2 — JDBC JAR
# ---------------------------------------------------------------------------
echo "[Step 9/2] Syncing MSSQL JDBC JAR ..."

JDBC_JAR=$(find "$WORKSPACE_ROOT/synthea-omop-template/drivers/jdbc-runtime" \
           -name "mssql-jdbc-*.jre11.jar" 2>/dev/null | head -1)

if [[ -z "$JDBC_JAR" ]]; then
  echo "  [WARN] JDBC JAR not found — skipping. Add manually to bundle/drivers/ before deployment."
else
  cp -f "$JDBC_JAR" "$BUNDLE_DIR/drivers/"
  echo "  $(basename "$JDBC_JAR") -> bundle/drivers/"
fi

# ---------------------------------------------------------------------------
# Step 3 — Seed one-time files (never overwrite if already present)
# ---------------------------------------------------------------------------
echo "[Step 9/3] Seeding setup templates (first run only) ..."

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
# Secrets
.env

# Source data (stays in protected environment)
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
# Step 4 — Generate .env.example for the protected environment
# ---------------------------------------------------------------------------
echo "[Step 9/4] Generating .env.example ..."

cat > "$BUNDLE_DIR/.env.example" << ENVTEMPLATE
# =============================================================================
# .env — YOUR_ETL_NAME ETL — Protected Research Environment
#
# Copy to .env and fill in your values before running the ETL.
# NEVER commit .env to the repository.
# =============================================================================

# -----------------------------------------------------------------------------
# CRAN mirror (accessible from the protected research environment)
# -----------------------------------------------------------------------------
CRAN_MIRROR=${CRAN_MIRROR}

# -----------------------------------------------------------------------------
# Source data
# -----------------------------------------------------------------------------
# Directory containing the source flat-file CSV(s) (absolute path on HPC cluster)
ETL_SOURCE_DIR=/path/to/source/data/raw

# Flat-file provenance tag — identifies the specific file and data release.
# Format: {REGISTRY}_{FILETYPE}_{YYYYMMDD}
# Examples: REGISTRY_INDEX_20231201  REGISTRY_FOLLOWUP_20231201
ETL_SOURCE_FILE_TAG=REGISTRY_INDEX_CHANGE_ME

# Exact CSV filename to load (must be present in ETL_SOURCE_DIR)
ETL_SOURCE_FILE=source_proc_CHANGE_ME.csv

# Data release date (written into cdm_source table)
SOURCE_RELEASE_DATE=YYYY-MM-DD

# -----------------------------------------------------------------------------
# Target OMOP CDM schema (dedicated ETL write schema)
# Set to the schema provided by your institution when it becomes available.
# -----------------------------------------------------------------------------
INST_OMOP_RESULTS_SCHEMA=CHANGE_ME

# Vocabulary schema (shared; read-only)
OMOP_VOCAB_SCHEMA=omop_vocab

# -----------------------------------------------------------------------------
# SQL Server connection (Kerberos JDBC in the protected environment)
# -----------------------------------------------------------------------------
MSSQL_SERVER=your.protected.sqlserver.example.edu
MSSQL_DATABASE=your_database
MSSQL_PORT=1433
MSSQL_USER=DOMAIN\\your_username

# HPC JDBC wrapper JAR path (provided by HPC support team)
# Place one level above the bundle: ../drivers/hpc-jdbc-wrapper.jar
OMOP_HPC_JAR=../drivers/hpc-jdbc-wrapper.jar
ENVTEMPLATE

echo "  .env.example written"

# ---------------------------------------------------------------------------
# Step 5 — Git commit and push (or dry-run)
# ---------------------------------------------------------------------------
echo "[Step 9/5] Committing bundle ..."

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
  echo "  [DRY RUN] Bundle populated but NOT pushed to GitLab."
  echo "  Set ETL_GITLAB_REMOTE in <workspace>/.env and re-run to push."
else
  # Verify SSH connectivity to GitLab host
  GITLAB_HOST=$(echo "$ETL_GITLAB_REMOTE" | sed 's|git@\([^:]*\):.*|\1|')
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -T "git@$GITLAB_HOST" 2>&1 \
       | grep -qiE "welcome|authenticated|successfully"; then
    echo "  [WARN] SSH key check inconclusive for $GITLAB_HOST — attempting push anyway."
  fi

  if git remote get-url origin &>/dev/null; then
    git remote set-url origin "$ETL_GITLAB_REMOTE"
  else
    git remote add origin "$ETL_GITLAB_REMOTE"
  fi

  git push --set-upstream origin "$BUNDLE_BRANCH"
  echo "  [OK] Pushed to $ETL_GITLAB_REMOTE ($BUNDLE_BRANCH)"
fi

# ---------------------------------------------------------------------------
# Step 6 — Dated zip fallback
# ---------------------------------------------------------------------------
echo "[Step 9/6] Building dated zip fallback ..."

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
echo "  1. Create the GitLab repo at your institution."
echo "  2. Add ETL_GITLAB_REMOTE to <workspace>/.env."
echo "  3. Re-run this script to push."
else
echo "  1. On the protected research environment:"
echo "       git clone --branch main $ETL_GITLAB_REMOTE YOUR_ETL_NAME"
echo "       cd YOUR_ETL_NAME"
echo "       cp .env.example .env   # fill in schema and paths"
echo "       bash setup_env.sh"
echo "       bash install_r_packages.sh"
fi
echo "  2. When your institution provides your schema, update INST_OMOP_RESULTS_SCHEMA"
echo "     in .env (protected environment) AND in <workspace>/.env (local)."
echo "======================================================================"
