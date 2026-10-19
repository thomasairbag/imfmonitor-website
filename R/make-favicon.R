# Draws the browser-tab icon, images/favicon.png: the bar mark (plan decision
# 21, option C) in sand on a green rounded square. No input file; the geometry
# is below. A 32px grid keeps every bar edge on a whole pixel, so the icon stays
# sharp at 32px and when browsers shrink it to 16px.
#
# Run from the project root: Rscript R/make-favicon.R

size <- 32
supersample <- 8 # samples per pixel side, to smooth the rounded corners
corner_radius <- 3

green <- c(0x24, 0x58, 0x4C) / 255 # $imfm-primary
sand <- c(0xF6, 0xEF, 0xE4) / 255  # $imfm-sand

# Bars as x range, then top; all share a bottom edge at y = 26 (y runs down).
bars <- list(
  list(x = c(5, 11), top = 18),
  list(x = c(13, 19), top = 12),
  list(x = c(21, 27), top = 6)
)
bar_bottom <- 26

inside_rounded_square <- function(x, y) {
  # Distance from the nearest corner centre decides membership near corners.
  cx <- pmin(pmax(x, corner_radius), size - corner_radius)
  cy <- pmin(pmax(y, corner_radius), size - corner_radius)
  (x - cx)^2 + (y - cy)^2 <= corner_radius^2
}

in_bar <- function(x, y) {
  hits <- vapply(
    bars,
    function(bar) x >= bar$x[1] & x < bar$x[2] & y >= bar$top & y < bar_bottom,
    logical(length(x))
  )
  rowSums(matrix(hits, ncol = length(bars))) > 0
}

offsets <- (seq_len(supersample) - 0.5) / supersample
image <- array(0, dim = c(size, size, 4))

for (row in seq_len(size)) {
  for (col in seq_len(size)) {
    xs <- rep(col - 1 + offsets, times = supersample)
    ys <- rep(row - 1 + offsets, each = supersample)
    inside <- inside_rounded_square(xs, ys)
    coverage <- mean(inside)
    if (coverage == 0) next
    sand_share <- mean(in_bar(xs, ys) & inside) / coverage
    image[row, col, 1:3] <- (1 - sand_share) * green + sand_share * sand
    image[row, col, 4] <- coverage
  }
}

png::writePNG(image, "images/favicon.png")
