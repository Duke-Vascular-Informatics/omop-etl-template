# =============================================================================
# R/connection.R
# Purpose : DatabaseConnector helper — builds connection details from config
#           and provides open/close wrappers used by all map_*.R modules.
# Inputs  : config list from get_etl_config()
# Outputs : DatabaseConnector connectionDetails object; connect/disconnect fns
# Requires: DatabaseConnector (HADES), Java 17
# =============================================================================

library(DatabaseConnector)

# Build a ConnectionDetails object from the ETL config list.
# Call once at the top of run_etl.R; pass the result to each module.
get_connection_details <- function(config) {
  DatabaseConnector::createConnectionDetails(
    dbms     = config$dbms,
    server   = paste0(config$server, "/", config$database),
    port     = as.integer(config$port),
    user     = config$user,
    password = config$password
  )
}

# Open a connection, execute expr(conn), close the connection.
# Ensures connections are never left open across function calls.
with_connection <- function(connection_details, expr) {
  conn <- DatabaseConnector::connect(connection_details)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)
  expr(conn)
}
