suppressPackageStartupMessages({
  library(here)
  library(data.table)
  library(sf)
  library(ggplot2)
})

## setting filepaths to the folders
## "here" dictates from root folder of nc-duke...-ap4
path_raw   <- here("data", "raw")
path_ap4   <- here("data", "raw", "AP4")
path_int   <- here("data", "intermediate")
path_final <- here("data", "final")
path_figs  <- here("output", "figures")
path_tabs  <- here("output", "tables")

## ap4 damages reported in 2017 dollars
ap4_base_cpi_2017 <- 245.1
cpi_2026          <- 334.4
cpi_inflator      <- cpi_2026 / ap4_base_cpi_2017

## load empirical CEMS benchmarks from Step 01a (fallback to defaults if missing)
bench_file <- here(path_int, "cems_benchmarks.rds")

if (file.exists(bench_file)) {
  cems_b <- readRDS(bench_file)
  
  default_assumptions <- list(
    ct = list(
      capacity_factor = cems_b$ct$cf,
      nox_lb_mwh      = cems_b$ct$nox_lb_mwh,
      so2_lb_mwh      = cems_b$ct$so2_lb_mwh
    ),
    ccgt = list(
      capacity_factor = cems_b$ccgt$cf,
      nox_lb_mwh      = cems_b$ccgt$nox_lb_mwh,
      so2_lb_mwh      = cems_b$ccgt$so2_lb_mwh
    )
  )
} else {
  warning("cems_benchmarks.rds not found in data/intermediate/. Using static defaults.")
  default_assumptions <- list(
    ct = list(
      capacity_factor = 0.0434,
      nox_lb_mwh      = 0.1100,
      so2_lb_mwh      = 0.00577
    ),
    ccgt = list(
      capacity_factor = 0.5783,
      nox_lb_mwh      = 0.0413,
      so2_lb_mwh      = 0.00397
    )
  )
}

## match county codes to name for Duke NC host counties
nc_host_fips <- c(
  "Person"   = "37145",
  "Davie"    = "37059",
  "Catawba"  = "37035",
  "Rowan"    = "37159",
  "Richmond" = "37153",
  "Stokes"   = "37169"
)

message("00_config.R loaded successfully.")