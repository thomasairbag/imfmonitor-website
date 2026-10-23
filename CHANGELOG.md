# Changelog

One entry per site or data release, newest first.

## Unreleased

Nothing released yet. A staging copy is online for testing, hidden from search engines.

- Site framework: shared design, menu, footer with independence notice, homepage, and empty templates for the four dataset pages, which read their facts from `data/datasets.yml`.
- Project moved out of Dropbox into a local Git repository.
- Fonts: Source Serif 4 and Source Sans 3 are now self-hosted, with their SIL Open Font Licences.
- Wordmark: an original bar mark beside "IMF Monitor" in the menu bar, and the same mark as the browser-tab icon.
- Governance and Technical Assistance pages no longer have a "Related datasets" section.
- Replication Data page removed: replication materials are on Harvard Dataverse, linked from Home and Other Data. The menu now has seven items.
- Dataset facts: `data/datasets.yml` now holds verified coverage, version, unit, status, citation, and file details for Conditionality, Programs, and Governance, each with its source. Unverified fields still show "To be confirmed".
- Versions are now release dates (Conditionality March 2026, Programs October 2026, Governance January 2025) instead of numbers. The at-a-glance panel drops its separate "Last updated" row.
- Citations follow each dataset's codebook exactly. Programs cites its Harvard Dataverse record (doi:10.7910/DVN/V4V1BA).
- Licences: one footer sentence covers the whole site ("You may reuse IMF Monitor data provided you cite it (CC BY 4.0)"); dataset pages no longer have a licence row.
- Governance offers its codebook and text corpus for direct download, as the Wix site did.
- Downloads lists only the current release; files of earlier releases (Conditionality September 2017, Programs June 2020) appear under Version history. The Reviews dataset moves from Conditionality to Other Data.
- Files of earlier releases are named with their release date, for example `v2017-09_IMFMonitor_Conditionality_Raw.xlsx` (formerly `v1.0_…`) and `v2020-06_IMFMonitor_Programs.xlsx` (formerly `IMFMonitor_Programs.xlsx`).
- Footer: one centred block, with the reuse sentence and contact above the independence notice.
- Conditionality page drafted in full as the model dataset page: a summary, a description of each file in the download list, notes on each release in Version history, and the publications the codebooks ask users to cite. Figures follow at Stage 6. Numbers in running text now come from `data/datasets.yml`.
- Phone layout: long links such as DOIs wrap instead of widening the page.
- Download buttons sit consistently at the right of each file on wider screens, and below it on phones.
- Conditionality, October 2026 release: the 21 program participation indicators added in March 2026 are removed (program participation is in the Programs dataset), with a new codebook and code. The main dataset was rebuilt with the new code and matches July 2023 exactly. The March 2026 files move to Version history as `v2026-03_…`.
- Conditionality: the Reviews dataset is back in the download list, because the code needs it; 14 publications listed; the second release is dated July 2023.
- Downloads: the Conditionality (March 2026 and September 2017), Programs (October 2026 and June 2020), and Governance files are now on the site under `files/`, each byte-identical to its original, and every Download button on those pages works. The Conditionality and Programs codebooks are offered as PDFs for the first time.
- Download lists show "To be confirmed" instead of a Download button until a file is approved for publication.
- Phone layout: long file names and DOI links wrap instead of widening the page.
- Programs page drafted in full from the Conditionality model: a summary from the codebook, a description of each file, notes on the October 2026 and June 2020 releases in Version history, and the publication the codebook names. Figures follow at Stage 6. The scraper's description says the code is provided for transparency, and that rerunning it gives an updated dataset that may differ from the October 2026 release.
- Governance page drafted in full from the same model: a summary from the codebook, a description of each file, a Version history note on the January 2025 release, and the article the codebook asks users to cite. Figures follow at Stage 6.
- Technical Assistance page drafted from the model: the dataset (1964–1989) is marked Forthcoming, to be released once its working paper is published. The page gives a summary with counts from the unreleased data, coverage, and the working paper to cite. The September 2026 release date on the Wix page is dropped. A forthcoming dataset shows "Not yet released" as its version and under Downloads and Version history.
- Governance: the meeting-level data, which the codebook describes but the Wix download lacked, is now offered beside the text corpus as `IMFMonitor_ExecutiveBoardMeetings.rds`. It is byte-identical to `IMFEBM_Meeting_Nov2024_V1.rds` on Harvard Dataverse.
- Other Data page drafted: short entries for the program reviews dataset (downloadable from the site) and the replication packages for *Greening the International Monetary Fund*, the tax advice and social spending floors articles, and *A Thousand Cuts*, each with its coverage, status, Harvard Dataverse DOI, and the publication to cite. The packages the Wix "Other Data" folder offered as zip files now link to their Dataverse records.
- Links to Harvard Dataverse records show a "Harvard Dataverse" button instead of "Download", because they open the record's page rather than a file.
- Download Data page removed, since each dataset's page has its files, with its codebook, citation, and earlier releases. Its old address shows the "page not found" page, which links to Home. The menu has six items.
- The full menu now shows on screens from 992px wide, such as laptops; narrower screens keep the menu button (previously below 1200px).
- About page drafted: a short introduction, the full independence statement with a contact line for rights holders, the five team members with photos and profile links, the funders as text (INET, the Centre for Business Research, the Cambridge-INET Institute, and the ESRC), and contact details.
- Home completed: each dataset card now has a one-line description, which also appears on the Related datasets cards on Conditionality and Programs. The "More data" list describes Other Data as the program reviews dataset and data and code for selected publications, and the Harvard Dataverse link as data and code for further publications. The Wix site's "What Is The IMF?" slideshow is not carried over.
- Dataset card headings no longer carry an empty anchor link, which keyboard users met as an extra "Anchor" stop leading to the top of the page.
- Old addresses aren't kept, and the site has no redirects. Home, Conditionality, Governance, and Technical Assistance have the same addresses as on the Wix site; About moves from `/about-us/` to `/about/`. Every other old address shows the "page not found" page, which links to Home: `/about-us`, Download Data, the 2023 codebook path under `/wp-content/`, the 2017 pages (`/imf-conditionality.html` and the Article IV Scanner), and Wix file links.
- Footer: the independence notice is now one shorter line, "IMF Monitor is an independent academic project, not affiliated with the International Monetary Fund", which links to the full statement on About. It sits directly below the reuse line, at the same size, with no gap between them.
- Page titles in the browser tab follow the Wix site: "IMF Monitor" on Home (before, "Independent research data on the International Monetary Fund – IMF Monitor") and, for example, "Governance | IMF Monitor" on other pages.
- Opening a page at a section link, such as Independence from the footer note, no longer hides the section's heading under the menu bar.
- Figures, redrawn in R from the published data: Conditionality has a world map of conditions per country, 1980–2019 (replacing the old interactive map), and a chart of conditions per year. Programs has a chart of states with an IMF program in force, 1952–2025. Governance has a chart of Executive Board discussions per year by topic, 1995–2015. Phones get versions laid out for a narrow screen. Technical Assistance has no figures until its data are released. Each figure is drawn by a script in `R/` that names its data file.
- About: the team photos now carry explicit empty alt text, so screen readers skip them instead of reading their file names.
- The site address is set to the staging address, thomasairbag.github.io/imfmonitor-website, so the "page not found" page's links work there. Quarto now also writes a sitemap.
- Accessibility fixes from staging tests: the logo in the menu bar is now a link named "IMF Monitor" (screen readers met it as an unnamed link); menu links show a sand outline when they have keyboard focus (the ring was the menu bar's own green); and the About team list no longer makes the page scroll sideways on phones narrower than 366px.
