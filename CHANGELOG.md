# Changelog

One entry per site or data release, newest first.

## Unreleased

- Each page names its main address, ending in a slash (for example `https://imfmonitor.org/conditionality/`), in a canonical link, so search engines treat it and its `…/index.html` form as one page.

## 26 October 2026: the rebuilt site goes live

The first release of IMF Monitor as a static Quarto site on GitHub Pages, replacing the Wix site at imfmonitor.org. Its source, with full history, is in the public repository thomasairbag/imfmonitor-website.

- Pages: Home, Conditionality, Programs, Governance, Technical Assistance, Other Data, and About, in a flat menu that shows in full from 992px wide. Each dataset page follows one template: a summary, an at-a-glance panel, downloads, how to cite, figures, related datasets, publications using the data, and version history.
- Programs is a dataset of its own for the first time. Its October 2026 release has raw and panel datasets, a PDF codebook, and the two R scripts that build them, also on Harvard Dataverse (doi:10.7910/DVN/V4V1BA). The June 2020 file is in its version history.
- Conditionality, October 2026 release: the 21 program participation indicators added in March 2026 are removed, since program participation is now in the Programs dataset, and its data equal July 2023's exactly. The codebook is a PDF for the first time. The March 2026 and September 2017 releases are in its version history.
- Governance offers the Executive Board minutes codebook and text corpus, as before, and now also the meeting-level data, which the Wix download lacked.
- Technical Assistance (1964–1989) is listed as forthcoming, with the working paper to cite.
- Other Data has the program reviews dataset and the replication packages for four publications, linked to their Harvard Dataverse records. Further replication data are in the IMF Monitor collection on Harvard Dataverse, linked from Home and Other Data. There are no Replication Data or Download Data pages.
- Every file downloads directly from its dataset page and is byte-identical to its original. Files of earlier releases carry their release date in the name, for example `v2017-09_IMFMonitor_Conditionality_Raw.xlsx`.
- Figures redrawn in R from the published data: a world map and a yearly chart of conditions, states with an IMF program in force, and Executive Board discussions per year by topic.
- Citations follow each dataset's codebook exactly, with a copy button. Versions are release dates. One footer sentence states the licence (CC BY 4.0).
- Independence: an original wordmark, no IMF seal, logo, or colours, an independence note in every footer, and the full statement on About.
- Old addresses: Home, Conditionality, Governance, and Technical Assistance keep their Wix addresses, and About moves to `/about/`. Every other old address shows the "page not found" page, which links to Home; the site has no redirects.
- Accessibility (WCAG 2.2 AA): a skip link, visible keyboard focus, alt text, layouts for phones, and checks with axe. Screen readers announce the result of copying a citation, and phones don't turn coverage ranges into phone-number links.
