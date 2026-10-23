# Figure: Executive Board discussions of individual countries per year, by
# topic, 1995–2015 (Governance page).
# Input: files/governance/IMFMonitor_ExecutiveBoardMeetings.rds, the
# meeting-level data. Only meetings with a discussion that are not restricted
# have minutes in the corpus (codebook, p. 5): 3,111 of them.
# Output: images/figures/governance-meetings.png and -narrow.png.

source("R/fig-setup.R")
library(dplyr)

meetings <- readRDS("files/governance/IMFMonitor_ExecutiveBoardMeetings.rds") |>
  filter(disc_discussion == "Y", disc_restricted == "N")

topics <- c("Lending program", "Article IV", "Other")
by_year <- meetings |>
  count(disc_year, disc_topic) |>
  mutate(disc_topic = factor(disc_topic, levels = rev(topics)))

message("Discussions: ", format(nrow(meetings), big.mark = ","))
print(count(meetings, disc_topic))
totals <- count(meetings, disc_year)
message("Fewest: ", paste(totals$disc_year[which.min(totals$n)], min(totals$n)),
        "; most: ", paste(totals$disc_year[which.max(totals$n)], max(totals$n)))
stopifnot(setequal(unique(meetings$disc_topic), topics))

plot_meetings <- function(narrow) {
  # The white outline is the 2px gap between stacked segments.
  ggplot(by_year, aes(disc_year, n, fill = disc_topic)) +
    geom_col(width = 0.7, colour = "white", linewidth = 0.35) +
    scale_fill_manual(values = setNames(imfm_series, topics), breaks = topics) +
    scale_x_continuous(breaks = seq(1995, 2015, by = 5), expand = expansion(add = 0.6)) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05)), name = "Discussions") +
    theme_imfm()
}

save_figure(plot_meetings, "governance-meetings", wide = c(8, 3.6), narrow = c(3.6, 3.0))
