# Country boundaries for the Conditionality map

`WB_countries_Admin0_10m` (shapefile: `.shp`, `.shx`, `.dbf`, `.prj`) is the World Bank Official Boundaries file of countries and territories (Admin 0, 1:10 million), 251 features in WGS 84. The World Bank publishes it under the Creative Commons Attribution 4.0 licence (World Bank Data Catalog, dataset 0038272), so the map's source note credits it.

The four files are copied unchanged from the replication package for Kentikelenis and Stubbs (2025), *Progressive rhetoric, regressive reality* (`IVTAX_Replication.zip`, Shape folder; Harvard Dataverse doi:10.7910/DVN/GNYXU1). The old Conditionality map on imfmonitor.org used the same geometry.

MD5 checksums:

| File | MD5 |
| --- | --- |
| `WB_countries_Admin0_10m.shp` | `7f0a4c2003fea9dd8d4929287c55e42e` |
| `WB_countries_Admin0_10m.shx` | `aa183d5989c909b16345c1a45dc73f84` |
| `WB_countries_Admin0_10m.dbf` | `975a2aa3cbea7ac4ba0a52ca25961d43` |
| `WB_countries_Admin0_10m.prj` | `c742bee3d4edfc2948a2ad08de1790a5` |

The R package rnaturalearth was considered instead (23 October 2026) but not used: Natural Earth draws de facto boundaries, placing Crimea in Russia and Western Sahara in Morocco, and showing Somaliland and Northern Cyprus as separate countries.
