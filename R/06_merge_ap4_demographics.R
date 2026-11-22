suppressPackageStartupMessages({
  library(here)
  library(data.table)
})

ap4_path <- here("data", "processed", "ap4_nc", "nc_demographic_regression_handoff.csv")
demographics_path <- here("data", "intermediate", "nc_county_demographics.csv")
output_dir <- here("data", "processed", "ap4_nc")
output_path <- file.path(output_dir, "nc_ap4_demographics_analysis.csv")
metadata_path <- file.path(output_dir, "nc_ap4_demographics_analysis_metadata.json")

ap4 <- fread(ap4_path, colClasses = c(receptor_fips = "character"))
demographics <- fread(demographics_path, colClasses = c(fips = "character"))

if (nrow(ap4) != 100) {
  stop("Expected 100 AP4 county rows, found ", nrow(ap4))
}
if (nrow(demographics) != 100) {
  stop("Expected 100 demographic county rows, found ", nrow(demographics))
}

ap4[, receptor_fips := sprintf("%05s", receptor_fips)]
demographics[, fips := sprintf("%05s", fips)]

if (anyDuplicated(ap4$receptor_fips)) {
  stop("Duplicate AP4 receptor FIPS values found")
}
if (anyDuplicated(demographics$fips)) {
  stop("Duplicate demographic county FIPS values found")
}

required_ap4 <- c(
  "receptor_fips", "damage_rank_nc", "delta_pm25_ug_m3",
  "baseline_pm25_ug_m3", "total_expected_deaths",
  "mortality_damage_2020_usd", "mortality_damage_2026_usd_provisional"
)
required_demographics <- c(
  "fips", "county_name", "total_pop", "pct_poverty", "pct_minority",
  "pct_black", "pct_hispanic", "med_income"
)

missing_ap4 <- setdiff(required_ap4, names(ap4))
missing_demographics <- setdiff(required_demographics, names(demographics))
if (length(missing_ap4) > 0) {
  stop("Missing AP4 columns: ", paste(missing_ap4, collapse = ", "))
}
if (length(missing_demographics) > 0) {
  stop("Missing demographic columns: ", paste(missing_demographics, collapse = ", "))
}

ap4_keys <- ap4$receptor_fips
demographic_keys <- demographics$fips
if (!setequal(ap4_keys, demographic_keys)) {
  stop("FIPS mismatch between AP4 and demographic data")
}

merged <- merge(
  ap4,
  demographics,
  by.x = "receptor_fips",
  by.y = "fips",
  all = FALSE,
  sort = FALSE
)

setnames(merged,
         old = c("total_pop", "mortality_damage_2026_usd_provisional"),
         new = c("county_population_acs", "mortality_damage_2026_usd_provisional"),
         skip_absent = TRUE)

if (any(merged$county_population_acs <= 0)) {
  stop("Nonpositive county population found")
}

merged[, `:=`(
  mortality_damage_2026_per_resident = mortality_damage_2026_usd_provisional / county_population_acs,
  mortality_damage_2026_per_100k = mortality_damage_2026_usd_provisional / county_population_acs * 100000,
  total_expected_deaths_per_100k = total_expected_deaths / county_population_acs * 100000
)]

setorder(merged, -mortality_damage_2026_usd_provisional)
merged[, damage_rank_nc_total := .I]
setorder(merged, -mortality_damage_2026_per_100k)
merged[, damage_rank_nc_per_100k := .I]
setorder(merged, -delta_pm25_ug_m3)
merged[, pm25_rank_nc := .I]
setorder(merged, damage_rank_nc_total)

preferred_columns <- c(
  "receptor_fips", "county_name", "is_duke_host", "county_population_acs",
  "pct_poverty", "pct_minority", "pct_black", "pct_hispanic", "med_income",
  "baseline_pm25_ug_m3", "delta_pm25_ug_m3", "total_expected_deaths",
  "mortality_damage_2020_usd", "mortality_damage_2026_usd_provisional",
  "mortality_damage_2026_per_resident", "mortality_damage_2026_per_100k",
  "total_expected_deaths_per_100k", "damage_rank_nc_total",
  "damage_rank_nc_per_100k", "pm25_rank_nc"
)
remaining_columns <- setdiff(names(merged), preferred_columns)
setcolorder(merged, c(preferred_columns, remaining_columns))

if (nrow(merged) != 100) {
  stop("Expected 100 merged county rows, found ", nrow(merged))
}

ap4_total <- sum(ap4$mortality_damage_2026_usd_provisional)
merged_total <- sum(merged$mortality_damage_2026_usd_provisional)
if (abs(ap4_total - merged_total) > 0.01) {
  stop("Merged damage total does not match the AP4 handoff")
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(merged, output_path)

metadata_text <- sprintf(
'{
  "ap4_handoff": "data/processed/ap4_nc/nc_demographic_regression_handoff.csv",
  "acs_demographics": "data/intermediate/nc_county_demographics.csv",
  "output": "data/processed/ap4_nc/nc_ap4_demographics_analysis.csv",
  "county_count": %d,
  "total_mortality_damage_2026_usd_provisional": %.2f,
  "join_key": "receptor_fips",
  "population_source": "2020-2024 ACS 5-year county estimates",
  "caution": "County-level descriptive associations do not imply causation. The 2026 dollar values are provisional."
}\n',
  nrow(merged), merged_total
)
writeLines(metadata_text, metadata_path)

message("Created ", output_path)
message("Created ", metadata_path)
message("Merged counties: ", nrow(merged))
message("Provisional 2026 damage total: $", formatC(merged_total, format = "f", digits = 2, big.mark = ","))
