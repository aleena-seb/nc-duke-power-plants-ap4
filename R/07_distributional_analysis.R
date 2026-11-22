suppressPackageStartupMessages({
  library(here)
  library(data.table)
})

input_path <- here("data", "processed", "ap4_nc", "nc_ap4_demographics_analysis.csv")
table_dir <- here("output", "tables")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

d <- fread(input_path, colClasses = c(receptor_fips = "character"))
if (nrow(d) != 100) {
  stop("Expected 100 county rows, found ", nrow(d))
}

numeric_columns <- c(
  "mortality_damage_2026_usd_provisional",
  "mortality_damage_2026_per_resident",
  "mortality_damage_2026_per_100k",
  "total_expected_deaths",
  "total_expected_deaths_per_100k",
  "delta_pm25_ug_m3",
  "pct_poverty",
  "pct_minority",
  "pct_black",
  "pct_hispanic",
  "med_income",
  "county_population_acs"
)
missing_columns <- setdiff(numeric_columns, names(d))
if (length(missing_columns) > 0) {
  stop("Missing analysis columns: ", paste(missing_columns, collapse = ", "))
}

summary_rows <- lapply(numeric_columns, function(column) {
  x <- d[[column]]
  data.table(
    variable = column,
    n = sum(!is.na(x)),
    mean = mean(x, na.rm = TRUE),
    sd = sd(x, na.rm = TRUE),
    min = min(x, na.rm = TRUE),
    p25 = quantile(x, 0.25, na.rm = TRUE)[[1]],
    median = median(x, na.rm = TRUE),
    p75 = quantile(x, 0.75, na.rm = TRUE)[[1]],
    max = max(x, na.rm = TRUE)
  )
})
descriptive_summary <- rbindlist(summary_rows)
fwrite(descriptive_summary, file.path(table_dir, "ap4_nc_descriptive_summary.csv"))

correlation_variables <- c(
  "mortality_damage_2026_usd_provisional",
  "mortality_damage_2026_per_100k",
  "delta_pm25_ug_m3",
  "pct_poverty",
  "pct_minority",
  "pct_black",
  "pct_hispanic",
  "med_income",
  "county_population_acs"
)
correlation_matrix <- cor(d[, .SD, .SDcols = correlation_variables], use = "complete.obs")
correlation_table <- data.table(variable = rownames(correlation_matrix), correlation_matrix)
fwrite(correlation_table, file.path(table_dir, "ap4_nc_demographic_correlations.csv"))

rank_total <- d[, .(
  receptor_fips,
  county_name,
  county_population_acs,
  pct_poverty,
  pct_minority,
  pct_black,
  pct_hispanic,
  med_income,
  mortality_damage_2026_usd_provisional,
  mortality_damage_2026_per_100k,
  delta_pm25_ug_m3
)][order(-mortality_damage_2026_usd_provisional)]
rank_total[, damage_rank_nc_total := .I]
fwrite(rank_total, file.path(table_dir, "ap4_nc_ranked_by_total_damage.csv"))

rank_per_100k <- d[, .(
  receptor_fips,
  county_name,
  county_population_acs,
  pct_poverty,
  pct_minority,
  pct_black,
  pct_hispanic,
  med_income,
  mortality_damage_2026_usd_provisional,
  mortality_damage_2026_per_100k,
  delta_pm25_ug_m3
)][order(-mortality_damage_2026_per_100k)]
rank_per_100k[, damage_rank_nc_per_100k := .I]
fwrite(rank_per_100k, file.path(table_dir, "ap4_nc_ranked_by_damage_per_100k.csv"))

host_counties <- d[is_duke_host %in% c(TRUE, "TRUE", "True", "true")][,
  .(
    receptor_fips,
    county_name,
    county_population_acs,
    mortality_damage_2026_usd_provisional,
    mortality_damage_2026_per_100k,
    delta_pm25_ug_m3,
    pct_poverty,
    pct_minority,
    pct_black,
    pct_hispanic,
    med_income
  )
][order(-mortality_damage_2026_usd_provisional)]
fwrite(host_counties, file.path(table_dir, "ap4_nc_host_counties_receiving_results.csv"))

# Descriptive county-level regressions. These are associations, not causal estimates.
models <- list()
models[["m1_poverty_linear"]] <- lm(
  mortality_damage_2026_per_100k ~ pct_poverty,
  data = d
)
models[["m2_demographics_linear"]] <- lm(
  mortality_damage_2026_per_100k ~ pct_poverty + pct_minority + med_income,
  data = d
)
models[["m3_race_income_linear"]] <- lm(
  mortality_damage_2026_per_100k ~ pct_black + pct_hispanic + med_income,
  data = d
)
models[["m4_log_per_100k"]] <- lm(
  log(mortality_damage_2026_per_100k) ~ pct_poverty + pct_black + pct_hispanic + med_income,
  data = d
)
models[["m5_population_weighted"]] <- lm(
  mortality_damage_2026_per_100k ~ pct_poverty + pct_minority + med_income,
  data = d,
  weights = county_population_acs
)

model_tables <- list()
for (model_name in names(models)) {
  fit <- models[[model_name]]
  coefficient_rows <- data.table(
    model = model_name,
    term = names(coef(fit)),
    estimate = unname(coef(fit)),
    std_error = summary(fit)$coefficients[, "Std. Error"],
    statistic = summary(fit)$coefficients[, "t value"],
    p_value = summary(fit)$coefficients[, "Pr(>|t|)"]
  )
  model_tables[[model_name]] <- coefficient_rows
}
model_coefficients <- rbindlist(model_tables)
fwrite(model_coefficients, file.path(table_dir, "ap4_nc_regression_coefficients.csv"))

model_fit <- rbindlist(lapply(names(models), function(model_name) {
  fit <- models[[model_name]]
  s <- summary(fit)
  data.table(
    model = model_name,
    n = nobs(fit),
    r_squared = s$r.squared,
    adjusted_r_squared = s$adj.r.squared,
    residual_std_error = s$sigma,
    f_statistic = if (!is.null(s$fstatistic)) unname(s$fstatistic[1]) else NA_real_,
    model_p_value = if (!is.null(s$fstatistic)) {
      pf(s$fstatistic[1], s$fstatistic[2], s$fstatistic[3], lower.tail = FALSE)
    } else {
      NA_real_
    }
  )
}))
fwrite(model_fit, file.path(table_dir, "ap4_nc_regression_fit.csv"))

message("Wrote descriptive and regression tables to: ", table_dir)
print(descriptive_summary)
print(head(rank_per_100k, 10))
