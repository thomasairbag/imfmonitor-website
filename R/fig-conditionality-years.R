# Figure: IMF conditions per year, 1980–2019 (Conditionality page).
# Input: files/conditionality/IMFMonitor_Conditionality_Main.zip, the main
# dataset; BA1TOT is each country-year's total of conditions.
# Output: images/figures/conditionality-years.png and -narrow.png.

source("R/fig-setup.R")
library(dplyr)
library(haven)

main <- read_dta(unzip(
  "files/conditionality/IMFMonitor_Conditionality_Main.zip",
  "IMFMonitor_Conditionality_Main.dta",
  exdir = tempdir()
))

by_year <- main |>
  group_by(year) |>
  summarise(conditions = sum(BA1TOT, na.rm = TRUE))

message("Total: ", format(sum(by_year$conditions), big.mark = ","),
        "; years ", min(by_year$year), "–", max(by_year$year))
message("Fewest: ", paste(by_year$year[which.min(by_year$conditions)], min(by_year$conditions)),
        "; most: ", paste(by_year$year[which.max(by_year$conditions)], max(by_year$conditions)))
print(as.data.frame(by_year), row.names = FALSE)

plot_years <- function(narrow) {
  ggplot(by_year, aes(year, conditions)) +
    geom_col(fill = imfm_series[1], width = 0.7) +
    scale_x_continuous(breaks = seq(1980, 2015, by = if (narrow) 10 else 5),
                       expand = expansion(add = 0.6)) +
    scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.05)),
                       name = "Conditions") +
    theme_imfm()
}

save_figure(plot_years, "conditionality-years", wide = c(8, 3.6), narrow = c(3.6, 2.8))
