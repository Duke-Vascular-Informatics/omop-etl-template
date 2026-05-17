# =============================================================================
# workflow/03_run_etl.R
# Purpose : Execute all domain mapping modules in dependency order.
# Run     : Rscript workflow/03_run_etl.R  (or source("run_etl.R"))
# Prereqs : workflow/01 and 02 must pass; OMOP CDM schema must exist and be empty
# =============================================================================
if (!exists("config")) { source("config.R"); config <- get_etl_config() }

library(readr)
source("R/connection.R")
source("R/map_person.R")
source("R/map_visit.R")
source("R/map_procedure.R")
source("R/map_condition.R")
source("R/map_observation.R")
source("R/map_measurement.R")

staged            <- readRDS(file.path(config$staged_dir, "staged.rds"))
value_map         <- read_csv("mappings/value_map.csv", col_types = cols(.default = col_character()))
connection_details <- get_connection_details(config)

# Run in dependency order — person and visit must precede clinical domains
person_map <- map_person(staged, config, connection_details)
visit_map  <- map_visit(staged, person_map, config, connection_details)

map_procedure(staged, person_map, visit_map, value_map, config, connection_details)
map_condition(staged, person_map, visit_map, value_map, config, connection_details)
map_observation(staged, person_map, visit_map, value_map, config, connection_details)
map_measurement(staged, person_map, visit_map, value_map, config, connection_details)

message("workflow/03 complete")
