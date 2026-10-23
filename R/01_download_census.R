suppressPackageStartupMessages({
  library(here)
  library(data.table)
  library(tidycensus)
  library(dplyr)
})

# Source configuration file
source(here::here("R", "00_config.R"))

# Define ACS 5-Year demographic variable mapping
census_vars <- c(
  total_pop     = "B01003_001",
  white_nh      = "B03002_003",
  black         = "B02001_003",
  hispanic      = "B03002_012",
  poverty_total = "B17001_001",
  poverty_below = "B17001_002",
  med_hh_income = "B19013_001"
)

#Fetch 2024 5-Year ACS county-level data for North Carolina (2020 to 2024 data)
message("Pulling 2024 (2020-2024) 5-Year ACS county data for NC...")

nc_raw <- get_acs(
  geography = "county",
  state     = "NC",
  variables = census_vars,
  year      = 2024,
  output    = "wide",
  survey    = "acs5"
)

# Convert to data.table for in-place modifications
nc_dt <- as.data.table(nc_raw)

# Compute demographic rates and identify Duke Energy host counties
nc_dt[, `:=`(
  fips         = GEOID,
  county_name  = gsub(" County, North Carolina", "", NAME),
  pct_minority = ((total_popE - white_nhE) / total_popE) * 100,
  pct_black    = (blackE / total_popE) * 100,
  pct_hispanic = (hispanicE / total_popE) * 100,
  pct_poverty  = (poverty_belowE / poverty_totalE) * 100,
  med_income   = med_hh_incomeE
)]

# Tag host counties (Person, Davie, Catawba, Rowan, Richmond, Stokes)
nc_dt[, is_duke_host := fips %chin% nc_host_fips]

#Select final columns and renames them, sort alphabetically,from imported nc_dt table
clean_census <- nc_dt[, .(
  fips,
  county_name,
  is_duke_host,
  total_pop     = total_popE,
  poverty_below = poverty_belowE,
  pct_poverty   = pct_poverty,
  pct_minority  = pct_minority,
  pct_black     = pct_black,
  pct_hispanic  = pct_hispanic,
  med_income    = med_income
)]

setorder(clean_census, county_name)

# Ensure intermediate directory exists and write CSV
dir.create(path_int, showWarnings = FALSE, recursive = TRUE)
output_path <- here::here(path_int, "nc_county_demographics.csv")
fwrite(clean_census, output_path)

message("Demographics saved successfully to: ", output_path)