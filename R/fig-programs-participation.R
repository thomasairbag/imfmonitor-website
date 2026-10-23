# Figure: states with an IMF program in force, 1952–2025 (Programs page).
# Input: files/programs/IMFMonitor_Programs_Panel.xlsx, sheet Country_Year.
# IMFnn, conIMFnn, and nonIMFnn are 1 if a program (any, concessional, or
# non-concessional) was in force at any time in the year (codebook, Section 3).
# Output: images/figures/programs-participation.png and -narrow.png.

source("R/fig-setup.R")
library(dplyr)
library(tidyr)

panel <- readxl::read_excel("files/programs/IMFMonitor_Programs_Panel.xlsx",
                            sheet = "Country_Year")

series_labels <- c(IMFnn = "All programs", conIMFnn = "Concessional",
                   nonIMFnn = "Non-concessional")

by_year <- panel |>
  group_by(year) |>
  summarise(states = n(), across(all_of(names(series_labels)), \(x) sum(x, na.rm = TRUE)))

message("Years ", min(by_year$year), "–", max(by_year$year))
print(as.data.frame(filter(by_year, year %in% c(1952, 1970, 1986, 1990, 1995, 2000,
                                                 2005, 2010, 2015, 2020, 2025))),
      row.names = FALSE)
message("Peak (all): ", paste(by_year$year[which.max(by_year$IMFnn)], max(by_year$IMFnn)))
message("First concessional year: ", min(by_year$year[by_year$conIMFnn > 0]))

# A state can have a concessional and a non-concessional program in the same
# year, so the two can add up to more than all programs: lines, not stacks.
long <- by_year |>
  pivot_longer(all_of(names(series_labels)), names_to = "series", values_to = "count") |>
  mutate(series = factor(series_labels[series], levels = series_labels))

plot_participation <- function(narrow) {
  ggplot(long, aes(year, count, colour = series)) +
    geom_line(linewidth = 0.7, lineend = "round", linejoin = "round") +
    scale_colour_manual(values = imfm_series) +
    scale_x_continuous(breaks = seq(1960, 2020, by = if (narrow) 20 else 10),
                       expand = expansion(add = 1)) +
    scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.05)),
                       name = "States") +
    guides(colour = guide_legend(nrow = if (narrow) 2 else 1, byrow = TRUE)) +
    theme_imfm() +
    theme(legend.key.width = unit(1.4, "lines"))
}

save_figure(plot_participation, "programs-participation", wide = c(8, 3.6), narrow = c(3.6, 3.0))
