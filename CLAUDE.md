# omop-etl-template — AI Coding Assistant Instructions

This is a **GitHub Template Repository** for building transportable ETL pipelines from
tabular source registries (CSV flat files) to **OMOP CDM v5.4** on SQL Server.

When a user creates a new ETL repo from this template, help them:
1. Populate `config.R` with source-specific paths and schema names.
2. Build `mappings/field_map.csv` by working through the source data dictionary.
3. Implement each `R/map_*.R` module using the stubs as a starting point.
4. Document non-obvious decisions in `docs/mapping_decisions.md`.

---

## Language and Runtime

- All code is **R 4.5.x**. No Python, Julia, or shell-only logic.
- Java 17 (Eclipse Adoptium) required for `DatabaseConnector` / `rJava`.
- Package management via `renv`. Install with `renv::install()`, snapshot with `renv::snapshot()`.

## Package Priority

1. **HADES first**: `DatabaseConnector`, `SqlRender` for all DB I/O and SQL.
2. **tidyverse second**: `dplyr`, `tidyr`, `readr`, `purrr`, `stringr` for wrangling.
3. Never use `dbplyr`, `odbc`, or `DBI` directly.

## Project Layout

- `config.R` — single source of truth. **Always read this first** before suggesting paths or schema names.
- `mappings/field_map.csv` — machine-readable field-level mapping table. Keep ETL logic here, not scattered in R code.
- `mappings/value_map.csv` — value set mapping (source codes → OMOP concept IDs).
- `R/map_*.R` — one module per OMOP domain. Each reads from `data/staged/` and writes to the target CDM schema.
- `docs/mapping_decisions.md` — append an entry for every non-obvious mapping choice.

## File Placement (MANDATORY)

**Every new R script created during ETL work must be written to this project's `scripts/`
directory.** Always use the full absolute host path:

```
<repo-root>/scripts/<name>.R
```

Inside the dev container the same directory is mounted at a path matching the repo name. Always supply the full absolute path — never a relative path — when creating or editing any file in this project.

**Never create ETL scripts in the workspace root or any other location.** The Write
tool resolves paths against the host filesystem independently of the shell's
working directory, so always supply the full absolute path.

## Flat-File Provenance Convention

When a source registry provides multiple flat files (e.g. procedure file + longitudinal
follow-up file), every ETL run must declare which file it is loading via the
`ETL_SOURCE_FILE_TAG` environment variable (see `config.R`). Adapt these tag patterns
to your registry:

| Tag pattern | Flat file | Example |
|-------------|-----------|---------|
| `REGISTRY_PROC_{YYYYMMDD}` | Index procedure file | `REGISTRY_PROC_20231201` |
| `REGISTRY_LTF_{YYYYMMDD}`  | Longitudinal follow-up file | `REGISTRY_LTF_20231201` |

The `YYYYMMDD` date matches the release date embedded in the source file name.

**How provenance flows through the ETL:**

1. `stage_raw.R` stamps `source_file = config$source_file_tag` on every row of
   the staged data frame.
2. `map_visit.R` writes `visit_source_value = "{source_file_tag}:{PATIENT_ID}"`
   — e.g. `"REGISTRY_PROC_20231201:12345678"`.
3. Every other OMOP domain row already carries `visit_occurrence_id`. Analysts
   recover provenance by joining to `visit_occurrence` and reading
   `visit_source_value`.

**LTF files must create their own `visit_occurrence` rows** (follow-up visits)
rather than linking follow-up observations to the index PROC visit. This ensures
that `"REGISTRY_LTF:{ID}"` rows are never confused with `"REGISTRY_PROC:{ID}"`
rows in temporal or provenance queries.

**Never hardcode a flat-file name** in any `map_*.R` file. Always read it from
`base$source_file` (which comes from `config$source_file_tag` via `stage_raw.R`).

## Concept ID Rules (three-tier lookup — mandatory)

**Tier 1**: OHDSI Phenotype Library — check before deriving any concept set.
**Tier 2**: Workspace catalog at `../phenotype_library/catalog.yaml` (if this repo is in the OMOP dev workspace).
**Tier 3**: Live vocabulary query via `Rscript scripts/concept_lookup.R "<term>" [domain]`.

Tag every concept ID:
- **[vocab query]** — confirmed by a live query. Safe to use.
- **[pretraining]** — from AI training data only. Must accompany a warning; do not write into code or CSV.

Never write a concept ID into code or CSV without the tag and a trailing comment naming the concept.

## Commenting Style (OHDSI GitHub conventions)

- File header block on every R script (purpose, inputs, outputs, prerequisites).
- Section banners (`# ====`) for major steps.
- Inline comment on every concept ID: `concept_id = 12345  # [vocab query] SNOMED: ...`
- `# TODO [LABEL]:` for open items (findable with grep).

## Mapping Decisions Log

For every non-obvious field mapping, append to `docs/mapping_decisions.md`:
- VQI/source field name and allowed values
- OMOP target table and column
- Concept ID(s) with source tag
- Rationale (why this mapping; alternatives considered)

## Data Safety

- Source CSVs → `data/raw/` (gitignored, never committed).
- Staged/intermediate files → `data/staged/` (gitignored, never committed).
- Never log individual patient records — aggregate output only.
- Credentials come from environment variables via `get_etl_config()` in `config.R`.

## Version Control (for repos derived from this template)

- Work on `adam-mdmph` branch; merge to `main` via PR only.
- Never push directly to `main`.
