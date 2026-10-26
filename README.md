# IMF Monitor website

IMF Monitor is an independent academic project that publishes research data on the International Monetary Fund: datasets, codebooks, citations, and replication packages. It is not affiliated with the IMF. This repository holds the source of its website, live at https://imfmonitor.org/.

To use the data, start from the dataset's page on the site, which has its files, citation, and version history. Contact: [thomas.stubbs@rhul.ac.uk](mailto:thomas.stubbs@rhul.ac.uk).

## How the site is built

- **Pages:** a Quarto website. Each page is `<slug>/index.qmd` (Home is `index.qmd`), and Quarto renders them into `docs/` as plain HTML. GitHub Pages serves `docs/` from the `main` branch, so `docs/` is committed with the sources. Only `.qmd` files are rendered, so this README, `CHANGELOG.md`, and `CLAUDE.md` never appear on the site.
- **Domain:** the `CNAME` file names the domain, imfmonitor.org, for GitHub Pages, and `.nojekyll` makes it serve the files as they are. Quarto copies both into `docs/`.
- **Design:** `_quarto.yml` holds the menu, footer, theme, and `site-url`; `styles/custom.scss` the colours and components; `fonts/` the self-hosted fonts, with their licences.
- **Dataset facts:** `data/datasets.yml` is the single source of truth for coverage, counts, versions, files, citations, and version histories, with the source of each fact. Its header documents the fields. Pages show it only through the shortcodes in `_extensions/imfmonitor/datasets.lua`, such as `dataset-downloads` and `dataset-value`, so each fact is changed in one place.
- **Downloads:** `files/` holds each dataset's files, byte-identical to their originals. Files of earlier releases carry the prefix `vYYYY-MM_` from their release date.
- **Figures:** the `R/fig-*.R` scripts draw them from the files in `files/` into `images/figures/`, and `R/fig-setup.R` holds their shared fonts, colours, and theme. They run by hand, not at render, and their PNG files are committed.
- **Conventions:** `CLAUDE.md` records the project's working rules and decisions in more detail.

## Preview and render

Rendering needs Quarto, which comes with RStudio; the site is built with Quarto 1.9. The figure scripts need R (4.3) and the packages dplyr, ggplot2, haven, png, ragg, readxl, scales, sf, systemfonts, and tidyr.

- **RStudio:** open `imfmonitor-website.Rproj`, then Build → Render Website. This renders every page into `docs/` and opens a preview.
- **Terminal**, in the project folder: `quarto render` builds the whole site; `quarto preview` serves it and re-renders each page as you save it.

Stop any preview before a full render. On Windows, a server holding `docs/` open makes the render fail partway, leaving `docs/` empty until the next render. After a Quarto upgrade, check `_includes/metadata.html`: it is a copy of Quarto's own template partial, changed only to write page titles as "Governance | IMF Monitor".

## Maintenance guide: releasing a dataset update

1. **Archive the superseded release.** Rename its files in `files/<dataset>/` with the prefix `vYYYY-MM_` from its release date, for example `v2026-03_IMFMonitor_Conditionality_Main.zip`, and leave their contents unchanged (`git mv` keeps their history). Do this first, because the new files take the current names. In `datasets.yml`, give each of them `kind: "archive"`, its new label and `href`, and its release date as `version`, with no `description`. The render warns if an archive name breaks the pattern.
2. **Copy in the new files.** Copy only approved files into `files/<dataset>/`, unchanged and under their current names (`IMFMonitor_…`). Check each copy against its original by MD5, for example in R with `tools::md5sum(c(original, copy))`. `.gitattributes` stops Git rewriting their line endings.
3. **Update `data/datasets.yml`.** Set the release date as `version` (month and year, for example "October 2026"), the coverage, counts, and citation (worded exactly as in the codebook), and each new file's label, `href`, format, size (decimal units), and a `description` of one or two lines. Add a `history` entry saying what changed. Name the source of every fact under `sources`. Leave unknown fields empty, and the site shows "To be confirmed".
4. **Redraw the figures.** From the project folder, rerun the dataset's scripts, for example `Rscript R/fig-conditionality-map.R`. Each prints the numbers its alt text states: check the alt text in the page against them, and update it if they changed. Captions take their counts from `datasets.yml`.
5. **Render** the whole site, with no errors or warnings.
6. **Check links and downloads.** Serve `docs/` at the root, for example with `Rscript -e "httpuv::runStaticServer('docs', port = 4321)"`, and open http://localhost:4321/. Check the changed pages at phone and desktop widths, and follow every link and download on them. `docs/conditionality/index.html` must stay, since the data files cite https://imfmonitor.org/conditionality/ as the codebook's home.
7. **Add a `CHANGELOG.md` entry**, dated, saying what the release changes.
8. **Deposit on Harvard Dataverse where relevant**, for example as a new version of a dataset's existing record. If the page is to cite a new DOI, deposit before step 3, so that `datasets.yml` can give it.
9. **Commit and push to `main`**, with the sources and `docs/` in one commit. A push publishes the site: GitHub Pages rebuilds it within a minute or two. Then check the changed pages and downloads on https://imfmonitor.org/. To undo a release, revert its commit and push.

## Moving to another host

The site needs no server or database: `docs/` is the whole site, as plain files, so any static host can serve it.

The domain is registered at GoDaddy, which also hosts its DNS. The records:

- `@`: GitHub's four A records (185.199.108.153, 185.199.109.153, 185.199.110.153, and 185.199.111.153) and four AAAA records (2606:50c0:8000::153, 2606:50c0:8001::153, 2606:50c0:8002::153, and 2606:50c0:8003::153);
- `www`: a CNAME to `thomasairbag.github.io`, which GitHub redirects to imfmonitor.org;
- TXT records verifying the domain with GitHub (`_github-pages-challenge-thomasairbag`) and with Google Search Console (`@`), and GoDaddy's default `_dmarc` record. There are no mail (MX) records.

To move:

1. **Publish `docs/` on the new host**, with imfmonitor.org as its custom domain, and test it at the host's own address first. The new host must also do what GitHub Pages does: serve `404.html` for missing addresses, redirect addresses without a trailing slash (`/conditionality` to `/conditionality/`), provide HTTPS, and accept files of up to 89.3 MiB (the Board minutes corpus).
2. **Repoint the DNS at GoDaddy:** replace GitHub's A, AAAA, and `www` records with the new host's, and keep the TXT records.
3. **Update the repository:** change `site-url` in `_quarto.yml` and the `CNAME` file if the address changes (only GitHub Pages reads `CNAME` and `.nojekyll`), then render, commit, and push.
4. **Leave GitHub Pages:** once the new host serves the site over HTTPS, remove the custom domain under the repository's Settings → Pages.
5. **Test the live site:** HTTPS, the `www` redirect, the 404 page, every link and download, and https://imfmonitor.org/conditionality/.

To move back, restore GitHub's records above at GoDaddy.
