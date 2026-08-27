# omop-etl-template

**GitHub Template Repository** — Scaffold for building a transportable ETL pipeline from
any tabular source registry (CSV / flat files) to **OMOP Common Data Model v5.4** on SQL Server.

## How to use this template

1. Click **Use this template → Create a new repository** on GitHub.
2. Name the new repo `omop-etl-<source>` (e.g., `omop-etl-vqi-infra`).
3. Clone locally alongside other workspace repos.
4. Edit `config.R` — replace every `YOUR_*` placeholder with real values.
5. Populate `mappings/field_map.csv` and `mappings/value_map.csv` from the source data dictionary.
6. Implement each `R/map_*.R` module (stubs provided).
7. Run `Rscript scripts/check_setup.R` — all items should be [OK] before running Step 3.

## Repository layout

```
omop-etl-template/
├── R/                     # ETL modules — one file per OMOP domain
│   ├── connection.R       # DatabaseConnector helpers
│   ├── stage_raw.R        # Read, clean, and type-cast source CSV
│   ├── map_person.R       # person table
│   ├── map_visit.R        # visit_occurrence
│   ├── map_procedure.R    # procedure_occurrence
│   ├── map_condition.R    # condition_occurrence
│   ├── map_observation.R  # observation
│   └── map_measurement.R  # measurement
├── mappings/
│   ├── field_map.csv      # Source field → OMOP table/column/concept
│   └── value_map.csv      # Source value set → OMOP concept ID
├── sql/
│   ├── ddl/               # OMOP CDM table DDL (SQL Server)
│   └── qc/                # Row-count and plausibility QC queries
├── docs/
│   ├── etl_spec.md        # ETL specification (fill in per project)
│   └── mapping_decisions.md  # Log of non-obvious mapping choices
├── scripts/
│   └── check_setup.R      # Pre-flight checker — run before workflow/03
├── workflow/
│   ├── 01_stage_raw.R     # Stage source CSV → data/staged/
│   ├── 02_validate_staged.R # Row counts, nulls, value-set checks
│   ├── 03_run_etl.R       # Execute all map_*.R modules
│   └── 04_qc_omop.R       # Post-load QC against OMOP CDM
├── config.R               # All settings — edit this first
├── run_etl.R              # One-shot orchestrator (calls workflow/01–04)
└── CHECKLIST.md           # Go/no-go checklist before first ETL run
```

## Requirements

- R 4.5.x
- Java 17 (Eclipse Adoptium) — required for `DatabaseConnector` / `rJava`
- SQL Server target instance with a pre-created OMOP CDM v5.4 schema

## Data governance

Source data files are governed by the originating registry's Data Use Agreement.
Raw and staged files must stay in the protected analysis environment and must **never**
be committed to this repository (`data/` is gitignored).

## Concept ID policy

Every concept ID must be verified with a live vocabulary query before use.
See `CLAUDE.md` for the three-tier lookup workflow.

---

## Funding

Research reported in this publication was supported by the National Center For Advancing Translational Sciences of the National Institutes of Health under Award Number K12TR005435. The content is solely the responsibility of the authors and does not necessarily represent the official views of the National Institutes of Health.

---

## License

Copyright 2026 Duke University. All Rights Reserved. The software is hereby licensed under the GNU GPL License v2 (see [LICENSE](LICENSE)).
