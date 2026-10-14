suppressPackageStartupMessages({
  library(here)
  library(data.table)
})

# Define paths
emissions_path  <- here("data", "raw", "cems_annual_emissions_2024.csv")
attributes_path <- here("data", "raw", "cems_facility_attributes_2024.csv")
out_path        <- here("data", "intermediate", "cems_benchmarks.rds")

# Ensure files exist before running
stopifnot(
  "Missing annual emissions CSV"    = file.exists(emissions_path),
  "Missing facility attributes CSV" = file.exists(attributes_path)
)

## read in the files 
emiss <- fread(emissions_path)
attrs <- fread(attributes_path)

# convert column names to lowercase
setnames(emiss, tolower(names(emiss)))
setnames(attrs, tolower(names(attrs)))

## define function to extract the capacity from plants
parse_cap <- function(text) {
  # deal with empty rows
  if (is.na(text) || text == "") {
    return(NA_real_)
  }
  
  # Split on commas so each generator is its own chunk
  generators <- unlist(strsplit(text, split = ",", fixed = TRUE))
  total_mw <- 0
  found_any <- FALSE
  
  # Process each generator one by one
  for (gen in generators) {
    pos_open  <- regexpr("(", gen, fixed = TRUE)[1]
    pos_close <- regexpr(")", gen, fixed = TRUE)[1]
    
    if (pos_open > 0 && pos_close > pos_open) {
      num_str <- substr(gen, start = pos_open + 1, stop = pos_close - 1)
      value <- suppressWarnings(as.numeric(trimws(num_str)))
      if (!is.na(value)) {
        total_mw <- total_mw + value
        found_any <- TRUE
      }
    }
  }
  
  if (!found_any) {
    return(NA_real_)
  }
  
  return(total_mw)
}

# Locate attribute column names dynamically
fac_attr_col  <- grep("facility id", names(attrs), value = TRUE)[1]
unit_attr_col <- grep("^unit id", names(attrs), value = TRUE)[1]
cap_attr_col  <- grep("associated generators", names(attrs), value = TRUE)[1]

# Apply row-by-row across raw attributes
attrs[, capacity_mw := sapply(get(cap_attr_col), parse_cap, USE.NAMES = FALSE)]

# Retain distinct facility-unit identifier pairs with parsed capacity
attrs_clean <- unique(attrs[, .(
  facility_id = as.character(get(fac_attr_col)),
  unit_id     = as.character(get(unit_attr_col)),
  capacity_mw
)])

## merge with emmisions table 
fac_emiss_col  <- grep("facility id", names(emiss), value = TRUE)[1]
unit_emiss_col <- grep("^unit id", names(emiss), value = TRUE)[1]
gen_col        <- grep("gross load", names(emiss), value = TRUE)[1]
nox_col        <- grep("nox mass", names(emiss), value = TRUE)[1]
so2_col        <- grep("so2 mass", names(emiss), value = TRUE)[1]
fuel_col       <- grep("primary fuel", names(emiss), value = TRUE)[1]
tech_col       <- grep("unit type", names(emiss), value = TRUE)[1]

# rename columns to standard lowercase identifiers
setnames(emiss, 
  c(fac_emiss_col, unit_emiss_col, gen_col, nox_col, so2_col, fuel_col, tech_col),
  c("facility_id", "unit_id", "gen_mwh", "nox_tons", "so2_tons", "fuel", "unit_type")
)

# Ensure ID columns are character for a clean join
emiss[, facility_id := as.character(facility_id)]
emiss[, unit_id     := as.character(unit_id)]

# merge emissions with capacity lookup table
fleet <- merge(emiss, attrs_clean, by = c("facility_id", "unit_id"), all.x = TRUE)

# clean numeric columns (remove commas like "1,000" and convert to double)
num_cols <- c("gen_mwh", "nox_tons", "so2_tons", "capacity_mw")
fleet[, (num_cols) := lapply(.SD, function(col) as.numeric(gsub(",", "", col))),
      .SDcols = num_cols]

## filter for gas plants over 25 mw that actually ran
gas_fleet <- fleet[
  grepl("gas", fuel, ignore.case = TRUE) &
  capacity_mw > 25 &
  gen_mwh > 0
]

## tag ccgt vs ct
gas_fleet[, tech := fifelse(grepl("combined", unit_type, ignore.case = TRUE), "ccgt", "ct")]

## calculate emission rates at the unit level
gas_fleet[, nox_lb_mwh := (nox_tons * 2000) / gen_mwh]
gas_fleet[, so2_lb_mwh := (so2_tons * 2000) / gen_mwh]

## calculate ct capacity factors at the unit level
ct_units <- gas_fleet[tech == "ct"]
ct_units[, cf := gen_mwh / (capacity_mw * 8760)]
ct_units <- ct_units[cf > 0 & cf <= 1]

## calculate ccgt capacity factors at the facility level to avoid split steam turbine denominators
ccgt_facility <- gas_fleet[tech == "ccgt", .(
  tot_gen_mwh = sum(gen_mwh, na.rm = TRUE),
  # Take unique unit capacity to avoid double counting
  tot_cap_mw  = max(capacity_mw, na.rm = TRUE)
), by = .(facility_id)]

ccgt_facility[, cf := tot_gen_mwh / (tot_cap_mw * 8760)]
ccgt_facility <- ccgt_facility[cf > 0 & cf <= 1]

## Grab quartiles and get percentage benchmarks for default attributes
# Median CF (50th percentile) and modern efficient emissions (10th percentile)
benchmarks <- list(
  ct = list(
    cf         = round(as.numeric(quantile(ct_units$cf, 0.50, na.rm = TRUE)), 4),
    nox_lb_mwh = round(as.numeric(quantile(ct_units$nox_lb_mwh, 0.10, na.rm = TRUE)), 4),
    so2_lb_mwh = round(as.numeric(quantile(ct_units$so2_lb_mwh, 0.10, na.rm = TRUE)), 5)
  ),
  ccgt = list(
    cf         = round(as.numeric(quantile(ccgt_facility$cf, 0.50, na.rm = TRUE)), 4),
    nox_lb_mwh = round(as.numeric(quantile(gas_fleet[tech == "ccgt", nox_lb_mwh], 0.10, na.rm = TRUE)), 4),
    so2_lb_mwh = round(as.numeric(quantile(gas_fleet[tech == "ccgt", so2_lb_mwh], 0.10, na.rm = TRUE)), 5)
  )
)

# Ensure output directory exists and save RDS
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
saveRDS(benchmarks, out_path)

message("CEMS benchmarks successfully written to: ", out_path)
print(benchmarks)