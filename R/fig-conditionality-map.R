# Figure: total IMF conditions per country, 1980–2019 (Conditionality page).
# Input: files/conditionality/IMFMonitor_Conditionality_Main.zip, the main
# dataset; BA1TOT is each country-year's total of conditions.
# Boundaries: R/boundaries/WB_countries_Admin0_10m.shp (World Bank Official
# Boundaries, CC BY 4.0; see R/boundaries/README.md).
# Output: images/figures/conditionality-map.png and -narrow.png.

source("R/fig-setup.R")
library(dplyr)
library(haven)
library(sf)

main <- read_dta(unzip(
  "files/conditionality/IMFMonitor_Conditionality_Main.zip",
  "IMFMonitor_Conditionality_Main.dta",
  exdir = tempdir()
))

totals <- main |>
  group_by(ccode, cname) |>
  summarise(conditions = sum(BA1TOT, na.rm = TRUE), .groups = "drop")

# Work in plain coordinates: one shape in the file is invalid and needs
# repair, and some (Russia, Fiji) cross the 180th meridian within one ring,
# which projected would draw stripes across the map. st_break_antimeridian()
# splits them there first.
sf_use_s2(FALSE)

# The World Bank's codes differ from the dataset's for six countries; the old
# Shiny map used the same recodes.
world <- read_sf("R/boundaries/WB_countries_Admin0_10m.shp") |>
  st_make_valid() |>
  mutate(ccode = recode(WB_A3, ADO = "AND", ZAR = "COD", IMY = "IMN",
                        KSV = "XKX", ROM = "ROU", TMP = "TLS")) |>
  filter(ccode != "ATA") |>
  left_join(totals, by = "ccode")

class_labels <- c("1–100", "101–250", "251–500", "501–1,000", "1,001 or more")
none_label <- "No conditions recorded"
world <- world |>
  mutate(
    class = cut(conditions, c(0, 100, 250, 500, 1000, Inf), labels = class_labels),
    class = factor(ifelse(is.na(class), none_label, as.character(class)),
                   levels = c(class_labels, none_label))
  )

# Countries with conditions that the map can't show: states that no longer
# exist (Czechoslovakia, Yugoslavia) have no boundaries.
unmapped <- totals |>
  filter(conditions > 0, !ccode %in% world$ccode)
message("Countries with conditions: ", sum(totals$conditions > 0),
        "; total conditions: ", format(sum(totals$conditions), big.mark = ","))
message("Not on the map: ", paste0(unmapped$cname, " (", unmapped$conditions, ")",
                                   collapse = ", "))
message("Countries per class (mapped):")
print(table(world$class[!duplicated(world$ccode)]))

# Equal Earth keeps countries' areas in proportion.
st_agr(world) <- "constant"
world <- suppressMessages(st_break_antimeridian(world, lon_0 = 0)) |>
  st_transform("+proj=eqearth +datum=WGS84")

plot_map <- function(narrow) {
  ggplot(world) +
    geom_sf(aes(fill = class), colour = "white", linewidth = 0.08) +
    scale_fill_manual(values = c(imfm_ramp, imfm_none), drop = FALSE,
                      name = "Conditions, 1980–2019") +
    coord_sf(expand = FALSE, datum = NA) +
    guides(fill = guide_legend(nrow = if (narrow) 3 else 1, byrow = TRUE,
                               title.position = "top")) +
    theme_void(base_size = 11, base_family = "IMFM Sans") +
    theme(
      text = element_text(colour = imfm_text),
      legend.position = "bottom",
      legend.justification = "left",
      legend.title = element_text(colour = imfm_muted, size = rel(0.9)),
      legend.text = element_text(colour = imfm_muted, size = rel(0.9)),
      legend.key.size = unit(0.8, "lines"),
      plot.margin = margin(4, 4, 4, 4)
    )
}

save_figure(plot_map, "conditionality-map", wide = c(8, 4.3), narrow = c(3.6, 2.7))
