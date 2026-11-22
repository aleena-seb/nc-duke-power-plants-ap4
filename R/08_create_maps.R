suppressPackageStartupMessages({
  library(here)
  library(data.table)
  library(tigris)
  library(sf)
  library(ggplot2)
})

options(tigris_use_cache = TRUE)

input_path <- here("data", "processed", "ap4_nc", "nc_ap4_demographics_analysis.csv")
plant_path <- here("data", "raw", "plant_points.csv")
figure_dir <- here("output", "figures")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

analysis <- fread(input_path, colClasses = c(receptor_fips = "character"))
plants <- fread(plant_path)

analysis[, receptor_fips := sprintf("%05s", receptor_fips)]
if (nrow(analysis) != 100) {
  stop("Expected 100 analysis rows, found ", nrow(analysis))
}

nc_counties <- counties(state = "NC", cb = TRUE, year = 2024, progress_bar = FALSE)
nc_counties$GEOID <- as.character(nc_counties$GEOID)

map_data <- merge(
  nc_counties,
  analysis,
  by.x = "GEOID",
  by.y = "receptor_fips",
  all.x = FALSE,
  sort = FALSE
)

if (nrow(map_data) != 100) {
  stop("Expected 100 mapped counties, found ", nrow(map_data))
}

plant_sf <- st_as_sf(
  plants,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
)
plant_sf <- st_transform(plant_sf, st_crs(map_data))

make_map <- function(value_column, title, legend_title, filename,
                     label_format = scales::label_number(scale_cut = scales::cut_short_scale()),
                     viridis_option = "C") {
  p <- ggplot(map_data) +
    geom_sf(aes(fill = .data[[value_column]]), color = "white", linewidth = 0.12) +
    geom_sf(
      data = plant_sf,
      shape = 21,
      fill = "black",
      color = "white",
      size = 2.2,
      stroke = 0.7,
      inherit.aes = FALSE
    ) +
    scale_fill_viridis_c(
      name = legend_title,
      option = viridis_option,
      labels = label_format,
      na.value = "grey90"
    ) +
    coord_sf(datum = NA) +
    labs(
      title = title,
      subtitle = "NC receiving counties; black points indicate proposed Duke host locations",
      caption = "Source: AP4 county results and 2020-2024 ACS 5-year county estimates"
    ) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      plot.subtitle = element_text(size = 10),
      plot.caption = element_text(size = 8, color = "grey35"),
      panel.grid = element_blank(),
      legend.position = "right",
      legend.title = element_text(face = "bold", size = 9)
    )

  ggsave(file.path(figure_dir, filename), p, width = 9, height = 7.5, dpi = 300)
  message("Wrote ", file.path(figure_dir, filename))
}

make_map(
  "mortality_damage_2026_usd_provisional",
  "Combined modeled mortality damages in NC",
  "Provisional 2026 USD",
  "ap4_nc_total_damage_map.png"
)

make_map(
  "mortality_damage_2026_per_100k",
  "Combined modeled mortality damages per 100,000 residents",
  "2026 USD per 100k",
  "ap4_nc_damage_per_100k_map.png",
  label_format = scales::label_comma(accuracy = 1)
)

make_map(
  "delta_pm25_ug_m3",
  "Incremental modeled PM2.5 from all 11 proposed units",
  "µg/m³",
  "ap4_nc_delta_pm25_map.png",
  label_format = scales::label_scientific(digits = 2),
  viridis_option = "C"
)

make_map(
  "pct_poverty",
  "County poverty rate",
  "Percent",
  "ap4_nc_poverty_map.png",
  label_format = scales::label_number(accuracy = 0.1),
  viridis_option = "C"
)

make_map(
  "pct_minority",
  "County minority population share",
  "Percent",
  "ap4_nc_minority_share_map.png",
  label_format = scales::label_number(accuracy = 0.1),
  viridis_option = "C"
)

make_map(
  "pct_black",
  "County Black population share",
  "Percent",
  "ap4_nc_black_share_map.png",
  label_format = scales::label_number(accuracy = 0.1),
  viridis_option = "C"
)

make_map(
  "med_income",
  "County median household income",
  "ACS 2020-2024 USD",
  "ap4_nc_median_income_map.png",
  label_format = scales::label_dollar(scale_cut = scales::cut_short_scale()),
  viridis_option = "C"
)
