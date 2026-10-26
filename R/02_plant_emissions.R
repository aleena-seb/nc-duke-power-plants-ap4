## R/02_plant_emissions.R
## Purpose: turn the 11 proposed units into annual tons of NOx and SO2,
## then collapse them into the 6 host counties.

## 0. Load config --------------------------------------------------------------
# Run 00_config.R (it sits at the project root, not in R/). This loads
# libraries and creates path_raw, path_int, default_assumptions, nc_host_fips.
source(here::here("R", "00_config.R"))

## 1. Load inputs --------------------------------------------------------------
# Read the unit roster from data/raw/ into a data.table called `units`.
units <- fread(
  file.path(path_raw, "proposed_units_11.csv"),  # full path to the roster CSV
  colClasses = c(county_fips = "character") # keep FIPS as text, not numbers
)

# Stop with an error if the roster does not have exactly 11 units.
stopifnot(nrow(units) == 11)

## 2. Assign operating benchmarks by technology --------------------------------
# Create a lowercase `tech` column ("ccgt" or "ct") to match the names used
# inside default_assumptions. trimws() removes stray spaces, toupper() makes
# the match case-insensitive.
units[, tech := fifelse(
  toupper(trimws(plant_type)) %in% c("CCGT", "CC"),  # combined cycle labels
  "ccgt",                                            # -> "ccgt"
  fifelse(
    toupper(trimws(plant_type)) == "CT",             # peaker label
    "ct",                                            # -> "ct"
    NA_character_                                    # anything else -> NA
  )
)]

# If any unit got NA (unrecognized label), stop and print the bad label(s).
if (anyNA(units$tech)) {
  bad_types <- unique(units[is.na(tech), plant_type])
  stop("Unrecognized plant_type values: ", paste(bad_types, collapse = ", "))
}

# for each unit's tech, look up one parameter in default_assumptions.
# vapply() returns one number per unit and errors if a lookup is not numeric.
get_param <- function(tech, param, assumptions) {
  vapply(tech, function(t) assumptions[[t]][[param]], numeric(1))
}

# add three columns: capacity factor, NOx rate, and SO2 rate (lb/MWh).
units[, `:=`(
  cf         = get_param(tech, "cf", default_assumptions),
  nox_lb_mwh = get_param(tech, "nox_lb_mwh", default_assumptions),
  so2_lb_mwh = get_param(tech, "so2_lb_mwh", cems_b)
)]

## 3. Annual generation and pollutant mass -------------------------------------
#annual MWh = capacity (MW) x 8,760 hours x capacity factor.
units[, annual_mwh := capacity_mw * 8760 * cf]

#tons = MWh x (lb/MWh) / 2,000 lb per short ton, for each pollutant.
units[, `:=`(
  nox_tons = annual_mwh * nox_lb_mwh / 2000,  # annual NOx short tons
  so2_tons = annual_mwh * so2_lb_mwh / 2000   # annual SO2 short tons
)]

## 4. Aggregate to host county -------------------------------------------------
#collapse 11 units into one row per county (grouped by county and FIPS).
host_county <- units[, .(
  units      = paste(unit_name, collapse = "; "),  # joined unit names
  n_units    = .N,                                 # number of units in county
  total_mw   = sum(capacity_mw),                   # total capacity
  annual_mwh = sum(annual_mwh),                    # total annual generation
  nox_tons   = sum(nox_tons),                      # total NOx tons
  so2_tons   = sum(so2_tons)                       # total SO2 tons
), by = .(county, county_fips)]

## 5. Checks and export --------------------------------------------------------
#verification checklist as automatic tests; the script stops if any fails.
stopifnot(
  nrow(host_county) == 6,                                  # exactly 6 counties
  setequal(host_county$county_fips, unname(nc_host_fips)), # the right 6 FIPS
  all(unlist(host_county[, .(total_mw, annual_mwh,
                             nox_tons, so2_tons)]) > 0)    # all values positive
)

# Create data/intermediate/ if missing (does nothing if it already exists).
dir.create(path_int, showWarnings = FALSE, recursive = TRUE)

# Save the unit-level table (useful for debugging and unit breakdowns).
fwrite(units, file.path(path_int, "unit_emissions.csv"))

# Save the county table; 03_run_dispersion.R reads this file.
fwrite(host_county, file.path(path_int, "host_county_emissions.csv"))

# Show the county table in the console for a quick visual check.
print(host_county)

# Log that the script finished.
message("02_plant_emissions.R complete.")