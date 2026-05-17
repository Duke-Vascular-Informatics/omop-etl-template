# ETL Pre-Flight Checklist

Run `Rscript scripts/check_setup.R` to evaluate this automatically.
Manual checks are listed here for reference.

## config.R

- [ ] `source_dir` points to a folder containing the source CSV
- [ ] `source_file` is the correct filename
- [ ] `cdm_schema` matches the target OMOP CDM schema on SQL Server
- [ ] `vocab_schema` matches the vocabulary schema (`omop_vocab`)
- [ ] `person_id_offset` is unique across all ETL sources in this CDM instance
- [ ] `cdm_holder`, `source_description`, `source_release_date` are filled in
- [ ] No `YOUR_*` placeholder values remain

## mappings/field_map.csv

- [ ] Every source field intended for OMOP has a row
- [ ] No `concept_id` cell is empty or `0`
- [ ] Every concept ID is tagged `[vocab query]` (not `[pretraining]`)
- [ ] `omop_table` and `omop_column` match OMOP CDM v5.4 column names exactly

## mappings/value_map.csv

- [ ] Every categorical source field has its full value set mapped
- [ ] No unmapped values that will silently drop rows

## R/map_*.R modules

- [ ] `R/stage_raw.R` — reads source CSV, enforces types, writes to `data/staged/`
- [ ] `R/map_person.R` — implemented and tested
- [ ] `R/map_visit.R` — implemented and tested
- [ ] `R/map_procedure.R` — implemented and tested
- [ ] `R/map_condition.R` — implemented and tested
- [ ] `R/map_observation.R` — implemented and tested
- [ ] `R/map_measurement.R` — implemented and tested

## Documentation

- [ ] `docs/etl_spec.md` — source system described, OMOP version confirmed
- [ ] `docs/mapping_decisions.md` — all non-obvious mapping choices logged

## QC

- [ ] `workflow/02_validate_staged.R` runs clean (no FAIL rows)
- [ ] `workflow/04_qc_omop.R` runs clean after ETL
