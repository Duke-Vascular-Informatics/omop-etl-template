# ETL Specification

## Source System

- **Registry name**: YOUR_REGISTRY_NAME
- **Registry version / data release**: YOUR_RELEASE_DATE
- **Source format**: CSV flat file
- **Source file**: `data/raw/YOUR_SOURCE_FILE.csv`
- **Data use agreement**: YOUR_DUA_REFERENCE

## Target System

- **CDM version**: OMOP CDM v5.4
- **DBMS**: SQL Server
- **CDM schema**: `YOUR_CDM_SCHEMA`
- **Vocabulary schema**: `omop_vocab`
- **CDM holder / institution**: YOUR_INSTITUTION

## Population

Describe the registry population here: inclusion criteria, time window, geographic scope.

## Scope

| OMOP Table | Source Fields | Notes |
|---|---|---|
| person | | |
| visit_occurrence | | |
| procedure_occurrence | | |
| condition_occurrence | | |
| observation | | |
| measurement | | |

## Out of scope

List any source fields intentionally not mapped and rationale.

## Known limitations

Document any structural gaps between the source and OMOP (e.g., no inpatient/outpatient
flag, approximate dates, missing race/ethnicity).
