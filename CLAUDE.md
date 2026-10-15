# CLAUDE.md: IMF Monitor website

## Purpose

IMF Monitor (imfmonitor.org) is an independent academic project that publishes research data on the International Monetary Fund: datasets, codebooks, citations, and replication packages. This repository rebuilds the site, formerly on Wix, as a static Quarto website served free from GitHub Pages. The goals are portability (the site can move to another static host within a day), reproducibility, and accurate, well-documented access to the data. Project director: Professor Thomas Stubbs, Royal Holloway, University of London.

## Working rules

- Write in British English with Oxford commas. Keep prose concise; avoid marketing language and absolute claims such as "comprehensive" unless every dataset meets them.
- Never invent data, statistics, links, DOIs, versions, file names, citations, or release status.
- Programs is a standalone page, separate from Conditionality (see below).
- No DNS changes, deletions, dataset replacements, pushes, or deployments without Thomas's explicit approval (full list at the end).
- Work one stage at a time. After each, report what changed, what was tested, and what Thomas needs to do next.
- The repository will be public. Confidential material (plans, the audit, correspondence) belongs only in `_private/`, which Git ignores.

## Private and local files (never committed)

| File | Use it for |
| --- | --- |
| `_private/WEBSITE_AUDIT_PLAN.md` | **The agreed plan:** structure, URL map, file hosting, design, stages, and decisions log (Section 8) |
| `_private/IMFMonitor_Claude_Project_Knowledge.md` | Dataset descriptions, DOI and link inventory, tone rules, and items marked VERIFY |
| `CLAUDE.local.md` | This machine's paths: source data in Dropbox, R, and Quarto |

- Read the relevant section of the plan before working on a page, dataset, figure, URL, or deployment step. Don't copy plan or audit content into committed files; there is deliberately no public plan document.
- Where the two documents disagree, the audit plan wins (for example, About stays at `/about-us/`).
- Decisions still open in Section 8 are not settled. Don't anticipate them in copy, code, or file names; ask.
- Don't redesign the site or change an approved decision without asking Thomas first. If the plan looks wrong, raise it rather than work around it.

## Technical stack

- Quarto website: `.qmd` pages, optionally with R chunks, edited and previewed in RStudio on Windows.
- R 4.3.3 for figures and data-driven content. Quarto 1.9.38 comes with RStudio and is not on PATH (full path in `CLAUDE.local.md`).
- Render with RStudio's Build pane (Render Website) or `quarto render`. Output goes to `docs/`, which GitHub Pages will serve. Only `.qmd` files are rendered, so Markdown files such as this one are never published.
- Git, branch `main`, local only for now: no remote until Thomas approves one.
- Harvard Dataverse holds replication packages and large files; the site links to their DOIs.
- No backend, database, CMS, JavaScript framework, paid service, or CI pipeline. Use Quarto's Bootstrap theme with modest SCSS, and Bootstrap Icons for icons.

## Architecture (plan Sections 4–6)

- Flat menu, in order: wordmark (Home) · Conditionality · Programs · Governance · Technical Assistance · Other Data · Download Data · Replication Data · About.
- Each page is `<slug>/index.qmd`, publishing at `/<slug>/`. The slugs are `conditionality`, `programs`, `governance`, `technical-assistance`, `other-data`, `download-data`, `replication-data`, and `about-us`, plus root `index.qmd` and `404.qmd`.
- Every dataset page uses one template: summary, at-a-glance panel, download list, how to cite, figures, related datasets, publications using the data, and version history. Copy an existing dataset page to start a new one.
- `data/datasets.yml` is the single source of truth for coverage, versions, counts, files, and citations; its header documents the fields. Pages show it only through the shortcodes in `_extensions/imfmonitor/datasets.lua`: `dataset-glance`, `dataset-downloads`, `dataset-cite`, `dataset-card ID`, and `dataset-hub`. Never hard-code a fact that belongs in the file. Empty fields display "To be confirmed".
- The shortcodes read `datasets.yml` directly. Don't load it with Quarto's `metadata-files`: that rewrites values matching file or folder names (on Windows, "Conditionality" becomes "../Conditionality").
- Text still to be written goes in a `::: {.draft-note}` block, which shows as a dashed box. None may remain at launch. Bootstrap already uses the class name `.placeholder`, so don't use it.
- Shared design: `_quarto.yml` (menu, footer, theme) and `styles/custom.scss` (palette, components). `_includes/` holds the skip link and the citation copy script. The menu collapses to a button below 1200px, because eight items need that width.
- Small public files live under `files/`. The Board minutes corpus and replication packages link to Dataverse DOIs.
- Staging safeguards: a `noindex` robots tag on every page (remove only at cutover, with approval), and `.nojekyll` so GitHub Pages serves files as they are. `site-url` is unset until the GitHub Pages address is known.
- Provisional until Thomas approves: the palette, the homepage introduction, the footer wording, and the text wordmark. Fonts fall back to system fonts until Source Serif 4 and Source Sans 3 are self-hosted.

## Programs and Conditionality are separate datasets

- Programs records participation in IMF lending arrangements; Conditionality records the policy conditions within them. Neither is a subset of the other.
- Each has its own top-level page, menu item, `datasets.yml` record, at-a-glance panel, download list, citation, and version history. They cross-link; neither nests under the other.
- The Programs file moves out of the Conditionality download folder and onto the Programs page. A codebook that documents both may be linked from both pages.
- Programs has no verified Dataverse DOI. Don't create, borrow, or imply one.

## Design principles (plan Section 5)

- A documentation-first research portal: content before decoration, downloads visible without scrolling, no full-screen hero, animation, or carousels. Use static charts unless interaction adds clear research value.
- One left-aligned layout used everywhere, with a collapsible menu on phones. Meet WCAG 2.2 AA.
- Independence: no IMF seal, logo, emblem, colours, or house style, and no globe-and-magnifier imagery. Every footer carries the independence notice; About carries the full statement and a contact line for rights holders.
- Never host copies of IMF documents; cite them by reference.
- Reuse an image only once its provenance and rights are confirmed. Redraw figures in R from authorised data.

## Academic accuracy

- Every published fact must trace to a named source: a data file, codebook, publication, or Thomas. If a fact is unverified, leave it out or mark it open, and ask.
- Reproduce citations exactly as the sources give them.
- Distinguish full public datasets from research-specific replication packages. Don't present a DOI as part of the IMF Monitor Dataverse collection until its membership is confirmed.

## Preserve existing links

- Keep every existing address working: `/`, `/conditionality`, `/governance`, `/technical-assistance`, `/download-data`, `/about-us`, and the legacy codebook at `/wp-content/uploads/2023/07/IMFMonitor_Conditions_Codebook.pdf`. The data files cite `https://imfmonitor.org/conditionality/` as the codebook's home.
- Keep data file names (`IMFMonitor_...`) unchanged.
- Keep every existing DOI and Dataverse link. Link to DOIs, not to temporary Dataverse file URLs or Wix file links.
- Quarto `aliases` redirects run in the browser. Don't promise a redirect until it has been tested on staging.

## Working conventions

- Stages follow plan Section 7, each ending with something Thomas can inspect and an explicit go-ahead. Current position: the site framework (shared design, menu, homepage, and empty dataset templates) awaits Thomas's review, and the project now lives outside Dropbox in a local Git repository. Stage 1 (Facts: filling `datasets.yml`) is next. No dataset content until Thomas asks.
- Source data stays in Dropbox (paths in `CLAUDE.local.md`). Treat it as read-only, and copy into `files/` only files Thomas has approved for publication.
- Pages and scripts read only files inside the repository and use relative paths, so the site builds on any machine.
- Never commit unpublished or internal files (such as coder notes), credentials, or files approaching GitHub's 100 MiB limit.
- Code: R scripts in `R/` use tidyverse style, and each figure script names its input file. Comment to explain why, not what.
- Prefer Quarto's native features (page options, column classes, Bootstrap classes, shortcodes) over custom CSS or JavaScript. Keep colours as the `$imfm-*` variables in `custom.scss`, and check contrast for any new colour pair.

## Testing

Before reporting a change as done:

1. Render the whole site with no errors or warnings. Quarto prints warnings as `(W)` lines.
2. Preview the affected pages at 375px, 1200px, and a wide desktop. In the Claude app, start the `site` server in `.claude/launch.json` (it serves `docs/` at http://localhost:4321), and add `?v=2` to addresses to skip the browser cache. To check filled-in components, render a scratch copy with sample `datasets.yml` values; never put sample values in the real file.
3. Check that every internal link and download resolves to a file in `docs/`, and that the legacy addresses still exist there.
4. List any new external links for Thomas to check; Harvard Dataverse blocks automated access.
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
