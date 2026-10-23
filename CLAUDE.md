# CLAUDE.md: IMF Monitor website

## Purpose

IMF Monitor (imfmonitor.org) is an independent academic project that publishes research data on the International Monetary Fund: datasets, codebooks, citations, and replication packages. This repository rebuilds the site, formerly on Wix, as a static Quarto website served free from GitHub Pages. The goals are portability (the site can move to another static host within a day), reproducibility, and accurate, well-documented access to the data. Project director: Professor Thomas Stubbs, Royal Holloway, University of London.

## Working rules

- Write in British English with Oxford commas. Keep prose concise; avoid marketing language and absolute claims such as "comprehensive" unless every dataset meets them. One exception: write "program", not "programme", to match the dataset names and codebooks (Thomas, 20 October 2026).
- Dataset pages carry no funding line (Thomas, 20 October 2026).
- Never invent data, statistics, links, DOIs, versions, file names, citations, or release status.
- Programs is a standalone page, separate from Conditionality (see below).
- No DNS changes, deletions, dataset replacements, pushes, or deployments without Thomas's explicit approval (full list at the end).
- Work one stage at a time. After each, report what changed, what was tested, and what Thomas needs to do next.
- The repository will be public, with its full history. Confidential material (plans, the audit, correspondence) belongs only in `_private/`, which Git ignores. Thomas agreed on 22 October 2026 that the committed files may be public as they stand, including CLAUDE.md and the source notes in `datasets.yml` (plan decision 47).

## Private and local files (never committed)

| File | Use it for |
| --- | --- |
| `_private/WEBSITE_AUDIT_PLAN.md` | **The agreed plan:** structure, URL map, file hosting, design, stages, and decisions log (Section 8) |
| `_private/IMFMonitor_Claude_Project_Knowledge.md` | Dataset descriptions, DOI and link inventory, tone rules, and items marked VERIFY |
| `CLAUDE.local.md` | This machine's paths: source data in Dropbox, R, and Quarto |

- Read the relevant section of the plan before working on a page, dataset, figure, URL, or deployment step. Don't copy plan or audit content into committed files; there is deliberately no public plan document.
- Where the two documents disagree, the audit plan wins.
- Decisions still open in Section 8 are not settled. Don't anticipate them in copy, code, or file names; ask.
- Don't redesign the site or change an approved decision without asking Thomas first. If the plan looks wrong, raise it rather than work around it.

## Technical stack

- Quarto website: `.qmd` pages, optionally with R chunks, edited and previewed in RStudio on Windows.
- R 4.3.3 for figures and data-driven content. Quarto 1.9.38 comes with RStudio and is not on PATH (full path in `CLAUDE.local.md`).
- Render with RStudio's Build pane (Render Website) or `quarto render`. Output goes to `docs/`, which GitHub Pages serves. Only `.qmd` files are rendered, so Markdown files such as this one are never published.
- Git, branch `main`, with the remote `origin`, https://github.com/thomasairbag/imfmonitor-website (public; added and first pushed on 23 October 2026, plan decisions 55–58). A push publishes the site, so each push needs Thomas's yes.
- Harvard Dataverse holds replication packages and large files; the site links to their DOIs.
- No backend, database, CMS, JavaScript framework, paid service, or CI pipeline. Use Quarto's Bootstrap theme with modest SCSS, and Bootstrap Icons for icons.

## Architecture (plan Sections 4–6)

- Flat menu, in order: wordmark (Home) · Conditionality · Programs · Governance · Technical Assistance · Other Data · About.
- There is no Download Data page: each dataset's page has its files (Thomas, 23 October 2026; plan decision 60). It left the menu on 21 October (decision 45) and was then removed, so `/download-data` shows the 404 page.
- Each page is `<slug>/index.qmd`, publishing at `/<slug>/`. The slugs are `conditionality`, `programs`, `governance`, `technical-assistance`, `other-data`, and `about`, plus root `index.qmd` and `404.qmd`. About moved from the Wix site's `about-us` on 23 October 2026 (plan decision 61).
- There is no Replication Data page (Thomas, 19 October 2026). Replication materials live on Harvard Dataverse: Home ("More data") and Other Data link to the IMF Monitor collection, https://dataverse.harvard.edu/dataverse/imfmonitor, as the Wix site did. Don't call the collection complete.
- Every dataset page uses one template: summary, at-a-glance panel, download list, how to cite, figures, related datasets, publications using the data, and version history. Copy an existing dataset page to start a new one; Conditionality is the model (Stage 4). Governance and Technical Assistance have no related datasets, so their pages leave that section out.
  - The summary is one paragraph, so the Downloads heading and first file stay visible without scrolling on a 1366 × 768 screen. What each file holds goes in its `description` in `datasets.yml`, shown in the download list.
  - Downloads lists only the current release. Version history comes from the dataset's `history` list (release date, old version number, and a note on what changed), with each earlier release's archive files under its entry.
- Other Data is one page of short entries: the program reviews dataset (the Conditionality download's copy of `IMFMonitor_Reviews.xlsx`), then the replication packages, newest first: *Greening the International Monetary Fund*, tax advice, social spending floors, and *A Thousand Cuts*. Books are headed by their titles in italics, articles by topic (Thomas, 21 October 2026). Each is a `datasets.yml` record with `page: other-data`, shown by `dataset-entry ID` under a heading anchored by its id. A package links to its Dataverse DOI and cites its publication, not the Dataverse record (Thomas, 21 October 2026).
- `data/datasets.yml` is the single source of truth for coverage, versions, counts, files, release notes, and citations; its header documents the fields. Pages show it only through the shortcodes in `_extensions/imfmonitor/datasets.lua`: `dataset-glance`, `dataset-downloads`, `dataset-history`, `dataset-value`, `dataset-cite`, `dataset-card ID`, and `dataset-entry ID`. Never hard-code a fact that belongs in the file: a number in running text comes from `counts` through `{{< dataset-value counts.NAME >}}`. Empty fields display "To be confirmed".
- The shortcodes read `datasets.yml` directly. Don't load it with Quarto's `metadata-files`: that rewrites values matching file or folder names (on Windows, "Conditionality" becomes "../Conditionality").
- Text still to be written goes in a `::: {.draft-note}` block, which shows as a dashed box. None may remain at launch. Bootstrap already uses the class name `.placeholder`, so don't use it.
- Shared design: `_quarto.yml` (menu, footer, theme) and `styles/custom.scss` (palette, components). `_includes/` holds the skip link, the citation copy script, and `metadata.html`, a copy of Quarto's template partial that changes only the page-title separator. The menu collapses to a button below 992px, so laptop screens show it in full (Thomas, 21 October 2026). Its six items fit on one line at 992px with about 60px to spare; check that margin before adding a menu item. The footer is one centred paragraph at one size: the reuse sentence and contact, then, after a line break, the independence note linking to About's Independence section (Thomas, 22 and 23 October 2026; plan decisions 50 and 63). The note's link is project-root relative (`/about/index.qmd#independence`), since footer links resolve against each page.
- Dataset files live under `files/`, and every dataset page offers its files for direct download, as the Wix site did. That includes the Board minutes codebook and corpus, not a Dataverse link (Thomas, 20 October 2026), and the meeting-level file `IMFMonitor_ExecutiveBoardMeetings.rds`. That file was missing from the Wix download, so it was copied from Dataverse 7N7LCH, where it is `IMFEBM_Meeting_Nov2024_V1.rds`, and checked by MD5 (Thomas, 21 October 2026; plan decision 12). The corpus zip (89.3 MiB) is hosted in the repository too, as an agreed exception to the size rule under Working conventions (Thomas, 20 October 2026; plan decision 31). Replication packages link to their Dataverse DOIs.
- `IMFMonitor_Reviews.xlsx` is part of the Conditionality download, because the Conditionality code needs it; Other Data may also list it (Thomas, 20 October 2026).
- Staging safeguards: a `noindex` robots tag on every page (remove only at cutover, with approval), and `.nojekyll` so GitHub Pages serves files as they are. `site-url` is the staging address, `https://thomasairbag.github.io/imfmonitor-website/`, from the public repository `imfmonitor-website` on Thomas's GitHub account, thomasairbag (plan decisions 4 and 46), created on 23 October 2026, with Pages serving `main` `/docs`. It becomes `https://imfmonitor.org/` at cutover.
- Approved on 19 October 2026: the palette, the homepage introduction and "More data" one-liners, and the footer wording. The Download Data one-liner was dropped on 21 October 2026 (decision 45). On 22 October 2026 Thomas approved new Other Data and Replication Data one-liners, matching the built Other Data page. The footer's reuse sentence was added on 20 October 2026, and on 22 October 2026 its independence notice became a one-line note linking to About.
- Page titles (the browser tab) follow the Wix site: "IMF Monitor" on Home and "Governance | IMF Monitor" on other pages (Thomas, 23 October 2026; plan decision 62). `_includes/metadata.html` swaps Quarto's " – " for " | ", and Home sets no `pagetitle`, so its title is the site's name alone; recheck that partial after a Quarto upgrade.
- Home: title, the approved introduction, the four dataset cards (name, tagline, coverage, and status), and "More data". Each tagline is one line in `datasets.yml`, approved by Thomas on 22 October 2026, with no numbers, since the card's coverage line gives them. The Wix "What Is The IMF?" slideshow is dropped (Thomas, 22 October 2026).
- Wordmark (chosen 19 October 2026): the bar mark, `images/logo-mark.svg` in sand, beside the "IMF Monitor" title; the mark alone is the browser-tab icon, `images/favicon.png`, drawn by `R/make-favicon.R`. Don't set "IMF" apart from "Monitor", which would read like an IMF sub-brand.
- Source Serif 4 (headings) and Source Sans 3 (text) are self-hosted in `fonts/`, unmodified from Adobe's releases, with their SIL OFL licences. `styles/fonts.css` declares them; only regular, italic, and semibold (600) exist, so use 600 for bold.

## Programs and Conditionality are separate datasets

- Programs records participation in IMF lending arrangements; Conditionality records the policy conditions within them. Neither is a subset of the other.
- Each has its own top-level page, menu item, `datasets.yml` record, at-a-glance panel, download list, citation, and version history. They cross-link; neither nests under the other.
- The October 2026 Programs release (`IMFMonitor_Programs_Raw.xlsx` and `IMFMonitor_Programs_Panel.xlsx`, with the Programs codebook as a PDF and the two build scripts) replaces the June 2020 `IMFMonitor_Programs.xlsx`, which sat in the Conditionality download folder, and is published on the Programs page. The June 2020 file stays available in the Programs version history, as `v2020-06_IMFMonitor_Programs.xlsx`. A codebook that documents both may be linked from both pages.
- The current Conditionality release is October 2026 (Thomas, 20 October 2026). It drops the 21 program participation indicators that March 2026 (v2.1) added, so program participation lives only in the Programs dataset; its data equal July 2023 (v2.0) exactly. March 2026 stays in Version history with its files (`v2026-03_…`). The release is archived in Dropbox at `IMFMonitor/TO_SORT/IMFMonitor_Conditionality_2026-10/`.
- Programs has a Dataverse record that Thomas deposited: doi:10.7910/DVN/V4V1BA, in the IMF Monitor collection, published 13 October 2026, with files identical to the October 2026 release. The Programs citation uses it (Thomas, 20 October 2026).

## Design principles (plan Section 5)

- A documentation-first research portal: content before decoration, downloads visible without scrolling, no full-screen hero, animation, or carousels. Use static charts unless interaction adds clear research value.
- One left-aligned layout used everywhere, with a collapsible menu on phones. Meet WCAG 2.2 AA.
- Independence: no IMF seal, logo, emblem, colours, or house style, and no globe-and-magnifier imagery. Every footer carries a one-line independence note linking to About, which has the full statement and a contact line for rights holders (Thomas, 22 October 2026).
- About (Thomas, 21 October 2026): introduction, independence, team, funding, and contact. The team is the Wix list, confirmed current: the project director first, then the collaborators by surname, with Al Mahmud under M. Its photos in `images/team/` are 240 px copies of the Dropbox originals (`Website/Images/about_*.jpg`), used with their subjects' agreement and needing no credit; their alt text is empty because each sits beside the person's name. Funding is text, not logos (decision 15), naming INET, the Centre for Business Research (CPEST grant), the Cambridge-INET Institute, and the ESRC.
- Never host copies of IMF documents; cite them by reference.
- Reuse an image only once its provenance and rights are confirmed. Redraw figures in R from authorised data. The conditionality map is a static R map drawn from the current Conditionality data; the old Shiny app is not reused.
- Figures (Stage 6, 23 October 2026; plan decisions 51–54): Conditionality has a map of conditions per country and a chart of conditions per year, Programs a chart of states with a program in force, and Governance a chart of Board discussions per year by topic. Technical Assistance has no figures, and no Figures section, until its data are released. The article's Figure 1 isn't redrawn on Governance, because the published files can't reproduce it.
  - Each figure has a script, `R/fig-*.R`, which names its input in `files/` and prints the numbers its alt text states. `R/fig-setup.R` holds the fonts, colours, and theme, and `save_figure()` writes two PNG files to `images/figures/`: one for the 799px desktop column and a `-narrow` one for phones. The scripts run by hand, not at render; rerun them after a data release and recheck each alt text.
  - Pages show a figure in a Quarto figure div (`{#fig-…}`) holding a raw-HTML `<picture>`: the narrow image below 576px, alt text on the `<img>`, and a markdown caption whose counts come from `dataset-value`. `_quarto.yml` lists `images/figures/**` as a resource, because Quarto doesn't follow `srcset`.
  - Chart colours: `#007d66` (the site green's hue, lighter and stronger), `#eb6834`, and `#6250d6`, in that order, plus a one-hue green ramp for the map. All were checked with the dataviz palette validator. Never use blue, the IMF's colour.
  - Figure text is Source Sans 3 from the TTF files in `R/fonts/`, from the same Adobe release as the site's WOFF2 files, which R can't read (Thomas approved the download).
  - Map boundaries: the World Bank Official Boundaries file in `R/boundaries/` (CC BY 4.0, credited in the caption), copied unchanged from the tax-advice replication package. Natural Earth (rnaturalearth) was rejected because it draws de facto boundaries, such as Crimea in Russia.

## Academic accuracy

- Every published fact must trace to a named source: a data file, codebook, publication, or Thomas. If a fact is unverified, leave it out or mark it open, and ask.
- Reproduce citations exactly as the sources give them. A dataset's citation is the one in its codebook, with the codebook's wording and italics (Thomas, 20 October 2026).
- Every dataset is versioned by release date, as month and year (for example "March 2026"), not by number (Thomas, 20 October 2026). Old numbers (v1.0, v2.0, v2.1) survive only in file names and version histories. Dataverse numbers its records itself (V1, V1.1); leave those as they are.
- Licence: one sentence in the footer covers the whole site: "You may reuse IMF Monitor data provided you cite it (CC BY 4.0)." Dataset pages, `datasets.yml`, and download lists state no licence (Thomas, 20 October 2026). The Dataverse records carry CC0 1.0; leave them as they are.
- Distinguish full public datasets from research-specific replication packages. Don't present a DOI as part of the IMF Monitor Dataverse collection until its membership is confirmed. Checked 20 October 2026: DPV99L, GNYXU1, 8BSKWO, and V4V1BA are in the collection; 7N7LCH (Board minutes) and KVVFV1 (social spending floors) are not.

## Addresses, file names, and DOIs

- Old addresses aren't kept as such (Thomas, 23 October 2026; plan decision 61). Each page sits at its own slug; Home, Conditionality, Governance, and Technical Assistance happen to have the addresses they had on the Wix site. Everything else shows the 404 page, which links to Home: `/about-us` (About is at `/about/`), `/download-data`, the 2017 pages `/imf-conditionality.html` and `/imf-surveillance.html` (the Article IV Scanner), the 2023 codebook path `/wp-content/uploads/2023/07/IMFMonitor_Conditions_Codebook.pdf`, Wix file links, and Wix leftovers such as `/general-9-1` (plan decisions 14, 16, 48, 49, and 60). Researchers can find the files from imfmonitor.org.
- Changing a page's slug needs Thomas's approval. `/conditionality/` must stay: the data files cite `https://imfmonitor.org/conditionality/` as the codebook's home.
- Keep the current release's data file names (`IMFMonitor_...`) unchanged. When a release is superseded, its files move to Version history with the prefix `vYYYY-MM_` from its release date, for example `v2017-09_IMFMonitor_Conditionality_Raw.xlsx`. Their contents stay unchanged (Thomas, 20 October 2026). The render warns if an archive entry in `datasets.yml` breaks this pattern.
- Keep every existing DOI and Dataverse link. Link to DOIs, not to temporary Dataverse file URLs or Wix file links.
- The site has no redirects: no Quarto `aliases` and no redirect pages (Thomas, 22 October 2026; plan decision 49). GitHub Pages itself sends `/conditionality` to `/conditionality/`, so addresses typed without the trailing slash still work (checked on staging, 23 October 2026). Ask before adding a redirect.

## Working conventions

- Stages follow plan Section 7, each ending with something Thomas can inspect and an explicit go-ahead. Current position: Thomas reviewed the site framework and chose the wordmark on 19 October 2026. Stage 1 (Facts) was done on 20 October 2026. Stage 4 (the Conditionality model page) was built and approved the same day, together with the October 2026 Conditionality release. Stage 5 carries the template over to the other pages. Programs and Governance were approved on 21 October 2026. Technical Assistance was approved the same day as a forthcoming dataset (decision 9): its 1964–1989 data stay unpublished until the working paper is published, and nothing from them goes into `files/`. Other Data was approved the same day (decisions 11, 13, and 42–44). Download Data was then taken out of the menu and kept only as a page for old links (decision 45), and the full menu now shows from 992px; both were approved the same day. About was approved the same day (decision 15 settled). Home, with the dataset taglines, was approved on 22 October 2026, which completes Stage 5 (decision 17 closed as moot). The decisions needed before staging were settled on 22 October 2026 (decisions 14, 16, and 46–48). Stage 6 (figures) was built and approved on 23 October 2026 (decisions 51–54). Stage 7 (staging) began the same day: the repository is public, and the site is live at the staging address (decisions 55–58). Staging tests led to three accessibility fixes (decision 59); Download Data was removed (decision 60); the rule keeping old addresses was dropped, with About moving to `/about/` (decision 61); page titles now follow the Wix site's form (decision 62); and the footer is one paragraph at one size (decision 63). Next: Thomas's staging checks, from the checklist in `_private/stage7-staging-checklist.md`.
- Source data stays in Dropbox (paths in `CLAUDE.local.md`). Treat it as read-only, and copy into `files/` only files Thomas has approved for publication.
- Pages and scripts read only files inside the repository and use relative paths, so the site builds on any machine.
- Never commit unpublished or internal files (such as coder notes), credentials, or files approaching GitHub's 100 MiB limit. The one agreed exception is the Board minutes corpus, `IMFMonitor_ExecutiveBoardMinutes.zip` (89.3 MiB; Thomas, 20 October 2026). GitHub warns about it on push but accepts it. Ask before adding any other file over 50 MiB.
- Files in `files/` are copied unchanged from the Dropbox originals; check by MD5 that each copy is identical. `.gitattributes` stops Git from rewriting their line endings (`core.autocrlf` is on), so the published `.R` scripts stay byte-identical to the originals and to their Dataverse copies.
- Code: R scripts in `R/` use tidyverse style, and each figure script names its input file. Comment to explain why, not what.
- Prefer Quarto's native features (page options, column classes, Bootstrap classes, shortcodes) over custom CSS or JavaScript. Keep colours as the `$imfm-*` variables in `custom.scss`, and check contrast for any new colour pair.

## Testing

Before reporting a change as done:

1. Render the whole site with no errors or warnings. Quarto prints warnings as `(W)` lines.
2. Preview the affected pages at 375px, 1200px, and a wide desktop. In the Claude app, start the `site` server in `.claude/launch.json` (it serves `docs/` at http://localhost:4321), and add `?v=2` to addresses to skip the browser cache. To check filled-in components, render a scratch copy with sample `datasets.yml` values; never put sample values in the real file.
3. Check that every internal link and download resolves to a file in `docs/`, and that `docs/conditionality/index.html` is still there (the data files cite it).
4. List any new external links for Thomas to check. Harvard Dataverse blocks scripted requests but opens in the Claude app's built-in browser, where its API also works from a Dataverse page.
5. Check alt text, heading order, and colour contrast for new content.

Say what was checked and what was not. The full staging checklist comes at Stage 7.

## Documentation

- Record each decision in the plan's decisions log (`_private/WEBSITE_AUDIT_PLAN.md`, Section 8).
- Add a `CHANGELOG.md` entry for each site or data release, and keep the Unreleased section current.
- Each `datasets.yml` entry names the source of each fact.

## Approval required

Ask Thomas and wait for an explicit yes, each time, before:

- Committing (unless asked), adding a Git remote, or pushing. Once a remote exists, a push publishes the site, because GitHub Pages serves `docs/`.
- Creating GitHub repositories or organisations, or changing Pages settings, the custom domain, HTTPS, or search-engine visibility.
- Any DNS change at GoDaddy, Wix, or elsewhere, including email and verification records. Never change DNS yourself.
- Deleting files, or replacing a published dataset or its files.
- Changing anything in the Dropbox copy of the project, which is the archive.
- Changing, unpublishing, or deleting anything on Wix, or cancelling it.
- Depositing to or editing Harvard Dataverse, or submitting to Google Search Console.
