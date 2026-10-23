# Shared set-up for the figure scripts (R/fig-*.R): fonts, colours, theme,
# and saving. Each figure script sources this file and names its own input.
#
# Run a figure script from the project root, for example:
#   Rscript R/fig-conditionality-map.R
# The site doesn't run these scripts when it renders; their PNG files in
# images/figures/ are committed with the site.

library(ggplot2)

# Source Sans 3, the site's text face. The site serves it as WOFF2, which R's
# graphics devices can't read, so R/fonts holds the TTF files from the same
# Adobe release (SIL Open Font Licence). Semibold stands in for bold, as on
# the site.
systemfonts::register_font(
  "IMFM Sans",
  plain = "R/fonts/source-sans-3/SourceSans3-Regular.ttf",
  bold = "R/fonts/source-sans-3/SourceSans3-Semibold.ttf",
  italic = "R/fonts/source-sans-3/SourceSans3-It.ttf"
)

# Text colours are the site's ($imfm-text, $imfm-muted in custom.scss).
imfm_text <- "#1A1F1E"
imfm_muted <- "#5C625F"
imfm_grid <- "#E5E2DC"

# Series colours, in fixed order. The first is the site green's hue at a
# lighter, stronger step: $imfm-primary itself is too dark and grey to mark a
# series. Checked with the dataviz palette validator (23 October 2026): inside
# the lightness band, above the chroma floor, colour-blind separation of at
# least 8.5 for every pair, and at least 3:1 against white. No blue, which is
# the IMF's house colour.
imfm_series <- c("#007d66", "#eb6834", "#6250d6")

# Map shades: one hue (the site green's), light to dark, checked as an ordered
# ramp. Grey marks countries with no conditions; it stays clearly apart from
# the lightest green.
imfm_ramp <- c("#7cc1af", "#4fa691", "#1b8a75", "#006d5a", "#004f41")
imfm_none <- "#E4E2DD"

# At 11pt and 200 dpi, axis labels show at about 13px in the desktop column
# and 12px on phones.
theme_imfm <- function(base_size = 11) {
  theme_minimal(base_size = base_size, base_family = "IMFM Sans") +
    theme(
      text = element_text(colour = imfm_text),
      axis.text = element_text(colour = imfm_muted, size = rel(0.85)),
      legend.text = element_text(size = rel(0.9)),
      axis.title = element_text(colour = imfm_muted, size = rel(0.9)),
      axis.title.x = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_line(colour = imfm_grid, linewidth = 0.3),
      legend.position = "top",
      legend.justification = "left",
      legend.title = element_blank(),
      legend.margin = margin(0, 0, 0, 0),
      plot.margin = margin(6, 10, 6, 4)
    )
}

# Saves two PNG files from one plot function: name.png for the 799px desktop
# column and name-narrow.png for phones (below 576px), so the text reads at
# about 13px on both. plot_fn(narrow) returns the plot, so a figure can adjust
# its legend or axis breaks for the narrow version.
save_figure <- function(plot_fn, name, wide = c(8, 4.2), narrow = c(3.6, 3.6)) {
  sizes <- list(list(suffix = "", dims = wide, narrow = FALSE),
                list(suffix = "-narrow", dims = narrow, narrow = TRUE))
  for (size in sizes) {
    path <- file.path("images", "figures", paste0(name, size$suffix, ".png"))
    ragg::agg_png(path, width = size$dims[1], height = size$dims[2],
                  units = "in", res = 200, background = "white")
    print(plot_fn(size$narrow))
    invisible(grDevices::dev.off())
    message("Wrote ", path)
  }
}
