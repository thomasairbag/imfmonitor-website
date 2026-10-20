# ==============================================================================
# IMF PROGRAMME PARTICIPATION INDICATORS: FULL OBSERVED PERIOD
# ==============================================================================
#
# Input:
#   IMFMonitor_Programs_Raw.xlsx
#
# Output:
#   IMFMonitor_Programs_Panel.xlsx
#
# Rapid Credit Facility (RCF) and Rapid Financing Instrument (RFI) observations
# are excluded before validation, spell construction, and indicator calculation.
# So are the outright purchases that the scraper adds by hand: Emergency Natural
# Disaster Assistance (ENDA), Emergency Post-Conflict Assistance (EPCA) and the
# Systemic Transformation Facility (STF). All five are listed in
# EXCLUDED_RAPID_FACILITIES and retained only in audit sheets inside the Excel
# workbook.
#
# Country-year universe (independent-state rule): the panel contains every
# independent state for exactly the years in which it existed, as set out in
# STATE_EXISTENCE below. A state is in the panel in year Y if it was an
# independent state on 31 December of Y. Programme indicators are 0/1 (or
# 0-12 months) in those years; country-years in which a state did not exist
# are absent from the panel. Dependent territories on the World Bank list
# (Aruba, Hong Kong, Puerto Rico, ...) are not independent states and are
# excluded. Former states (Yugoslavia, Czechoslovakia, the two pre-1990
# Yemens, East Germany, South Vietnam, Zanzibar) and Taiwan, which is not on
# the World Bank list, are added with their own codes.
# ==============================================================================

# ---- User settings -----------------------------------------------------------

INPUT_FILE <- "IMFMonitor_Programs_Raw.xlsx"
OUTPUT_FILE <- "IMFMonitor_Programs_Panel.xlsx"

# TRUE includes the workbook's IMF "as of" year. Because the indicators use
# approved start and expiration dates, this includes scheduled months later in
# that calendar year for arrangements already approved by the as-of date.
# Set FALSE to end at the latest complete calendar year instead.
INCLUDE_AS_OF_YEAR <- FALSE

# Leave as NA to derive the final year from the workbook metadata. A fixed
# integer can be supplied for a reproducible earlier cutoff, but not for a year
# later than the workbook's IMF as-of year.
YEAR_MAX_OVERRIDE <- NA_integer_

# How programme months are counted in each year:
#   "calendar" = number of calendar months in which a programme was in force
#                on at least one day (each month counted once; maximum 12).
#   "legacy"   = original Stata arithmetic (start year 13 - start month, end
#                year = end month, same-year spell = end - start month,
#                13 capped at 12). Use only to replicate earlier versions.
MONTH_METHOD <- "calendar"

# Facilities excluded from every programme indicator. The last three are
# outright purchases added to the raw workbook as manual rows by the scraper.
EXCLUDED_RAPID_FACILITIES <- c(
  "Rapid Credit Facility",
  "Rapid Financing Instrument",
  "Emergency Natural Disaster Assistance",
  "Emergency Post-Conflict Assistance",
  "Systemic Transformation Facility"
)

AUTO_INSTALL_PACKAGES <- TRUE

WB_COUNTRY_API <- paste0(
  "https://api.worldbank.org/v2/country",
  "?format=json&per_page=400"
)

# ---- Packages ---------------------------------------------------------------

required_packages <- c(
  "httr2",
  "jsonlite",
  "readxl",
  "dplyr",
  "tidyr",
  "purrr",
  "stringr",
  "lubridate",
  "openxlsx"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0L) {
  if (!AUTO_INSTALL_PACKAGES) {
    stop(
      "Missing required packages: ",
      paste(missing_packages, collapse = ", "),
      ". Install them and rerun the script.",
      call. = FALSE
    )
  }
  
  install.packages(
    missing_packages,
    repos = "https://cloud.r-project.org"
  )
}

still_missing <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(still_missing) > 0L) {
  stop(
    "The following packages remain unavailable: ",
    paste(still_missing, collapse = ", "),
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(lubridate)
  library(openxlsx)
})

# ---- Independent states and the years in which they existed ----------------

# One row per independent state. first_year is the year of independence (the
# start of the current spell for states independent before 1952); last_year is
# the last year in which the state existed on 31 December (NA = still exists).
# Rows are clipped to the panel window when the panel is built.
# Sources: Gleditsch & Ward list of independent states and Correlates of War
# state-system membership (via the R package "states" 0.3.3), cross-checked
# against published independence dates. "basis" records the reason for every
# date that is not simply the Gleditsch-Ward date. Decisions taken:
#   - Russia is the continuing state of the USSR (no separate USSR row).
#   - The 14 other former Soviet republics start in 1991.
#   - Croatia, Slovenia and North Macedonia start in 1992 (international
#     recognition from 15 January 1992); Yugoslavia (SFR) ends in 1991.
#   - Serbia starts in 1992 (FR Yugoslavia) and Yemen in 1990 (new states).
#   - Zimbabwe starts in 1980 (the 1965 UDI was never recognised).
#   - Syria is continuous through the United Arab Republic (1958-61).
STATE_EXISTENCE <- tibble::tribble(
  ~country_code, ~country_name, ~first_year, ~last_year, ~basis,
  "AFG", "Afghanistan"                              , 1919L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "AGO", "Angola"                                   , 1975L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ALB", "Albania"                                  , 1913L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "AND", "Andorra"                                  , 1816L, NA_integer_, "G&W microstate; COW from UN admission 1993",
  "ARE", "United Arab Emirates"                     , 1971L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ARG", "Argentina"                                , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ARM", "Armenia"                                  , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "ATG", "Antigua and Barbuda"                      , 1981L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "AUS", "Australia"                                , 1901L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "AUT", "Austria"                                  , 1918L, NA_integer_, "Continuous state, restored 1945 (G&W); occupation ended 1955 (COW)",
  "AZE", "Azerbaijan"                               , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "BDI", "Burundi"                                  , 1962L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BEL", "Belgium"                                  , 1830L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BEN", "Benin"                                    , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BFA", "Burkina Faso"                             , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BGD", "Bangladesh"                               , 1971L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BGR", "Bulgaria"                                 , 1878L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BHR", "Bahrain"                                  , 1971L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BHS", "Bahamas, The"                             , 1973L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BIH", "Bosnia and Herzegovina"                   , 1992L, NA_integer_, "Recognised 6 Apr 1992 (G&W, COW)",
  "BLR", "Belarus"                                  , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "BLZ", "Belize"                                   , 1981L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BOL", "Bolivia"                                  , 1825L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BRA", "Brazil"                                   , 1822L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BRB", "Barbados"                                 , 1966L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BRN", "Brunei Darussalam"                        , 1984L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "BTN", "Bhutan"                                   , 1949L, NA_integer_, "G&W 1949; COW from UN admission 1971",
  "BWA", "Botswana"                                 , 1966L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CAF", "Central African Republic"                 , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CAN", "Canada"                                   , 1867L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CHE", "Switzerland"                              , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CHL", "Chile"                                    , 1818L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CHN", "China"                                    , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CIV", "Cote d'Ivoire"                            , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CMR", "Cameroon"                                 , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "COD", "Congo, Dem. Rep."                         , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "COG", "Congo, Rep."                              , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "COL", "Colombia"                                 , 1830L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "COM", "Comoros"                                  , 1975L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CPV", "Cabo Verde"                               , 1975L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CRI", "Costa Rica"                               , 1840L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CSK", "Czechoslovakia"                           , 1918L, 1992L      , "Dissolved 31 Dec 1992 (IMF member key 240)",
  "CUB", "Cuba"                                     , 1902L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CYP", "Cyprus"                                   , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "CZE", "Czechia"                                  , 1993L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "DDR", "German Democratic Republic (East Germany)", 1949L, 1989L      , "G&W Oct 1949 (COW 1954); acceded 3 Oct 1990; never IMF member",
  "DEU", "Germany"                                  , 1949L, NA_integer_, "Federal Republic founded Sep 1949 (G&W); full sovereignty 1955 (COW)",
  "DJI", "Djibouti"                                 , 1977L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "DMA", "Dominica"                                 , 1978L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "DNK", "Denmark"                                  , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "DOM", "Dominican Republic"                       , 1844L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "DZA", "Algeria"                                  , 1962L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ECU", "Ecuador"                                  , 1830L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "EGY", "Egypt, Arab Rep."                         , 1922L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ERI", "Eritrea"                                  , 1993L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ESP", "Spain"                                    , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "EST", "Estonia"                                  , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "ETH", "Ethiopia"                                 , 1855L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "FIN", "Finland"                                  , 1917L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "FJI", "Fiji"                                     , 1970L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "FRA", "France"                                   , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "FSM", "Micronesia, Fed. Sts."                    , 1986L, NA_integer_, "Compact of Free Association 3 Nov 1986 (G&W); COW 1991",
  "GAB", "Gabon"                                    , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GBR", "United Kingdom"                           , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GEO", "Georgia"                                  , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "GHA", "Ghana"                                    , 1957L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GIN", "Guinea"                                   , 1958L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GMB", "Gambia, The"                              , 1965L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GNB", "Guinea-Bissau"                            , 1974L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GNQ", "Equatorial Guinea"                        , 1968L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GRC", "Greece"                                   , 1828L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GRD", "Grenada"                                  , 1974L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GTM", "Guatemala"                                , 1840L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "GUY", "Guyana"                                   , 1966L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "HND", "Honduras"                                 , 1840L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "HRV", "Croatia"                                  , 1992L, NA_integer_, "Recognised 15 Jan 1992 (COW); declared 25 Jun 1991",
  "HTI", "Haiti"                                    , 1934L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "HUN", "Hungary"                                  , 1918L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "IDN", "Indonesia"                                , 1945L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "IND", "India"                                    , 1947L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "IRL", "Ireland"                                  , 1921L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "IRN", "Iran, Islamic Rep."                       , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "IRQ", "Iraq"                                     , 1932L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ISL", "Iceland"                                  , 1944L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ISR", "Israel"                                   , 1948L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ITA", "Italy"                                    , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "JAM", "Jamaica"                                  , 1962L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "JOR", "Jordan"                                   , 1946L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "JPN", "Japan"                                    , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "KAZ", "Kazakhstan"                               , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "KEN", "Kenya"                                    , 1963L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "KGZ", "Kyrgyz Republic"                          , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "KHM", "Cambodia"                                 , 1953L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "KIR", "Kiribati"                                 , 1979L, NA_integer_, "G&W; COW from UN admission 1999",
  "KNA", "St. Kitts and Nevis"                      , 1983L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "KOR", "Korea, Rep."                              , 1948L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "KWT", "Kuwait"                                   , 1961L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "LAO", "Lao PDR"                                  , 1954L, NA_integer_, "G&W 1 May 1954; COW 22 Oct 1953",
  "LBN", "Lebanon"                                  , 1944L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "LBR", "Liberia"                                  , 1847L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "LBY", "Libya"                                    , 1951L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "LCA", "St. Lucia"                                , 1979L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "LIE", "Liechtenstein"                            , 1816L, NA_integer_, "G&W microstate; COW from UN admission 1990",
  "LKA", "Sri Lanka"                                , 1948L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "LSO", "Lesotho"                                  , 1966L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "LTU", "Lithuania"                                , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "LUX", "Luxembourg"                               , 1867L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "LVA", "Latvia"                                   , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "MAR", "Morocco"                                  , 1956L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MCO", "Monaco"                                   , 1816L, NA_integer_, "G&W microstate; COW from UN admission 1993",
  "MDA", "Moldova"                                  , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "MDG", "Madagascar"                               , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MDV", "Maldives"                                 , 1965L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MEX", "Mexico"                                   , 1821L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MHL", "Marshall Islands"                         , 1986L, NA_integer_, "Compact of Free Association 21 Oct 1986 (G&W); COW 1991",
  "MKD", "North Macedonia"                          , 1992L, NA_integer_, "Decision: first recognised 15 Jan 1992 (G&W 1991, COW 1993)",
  "MLI", "Mali"                                     , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MLT", "Malta"                                    , 1964L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MMR", "Myanmar"                                  , 1948L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MNE", "Montenegro"                               , 2006L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MNG", "Mongolia"                                 , 1921L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MOZ", "Mozambique"                               , 1975L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MRT", "Mauritania"                               , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MUS", "Mauritius"                                , 1968L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MWI", "Malawi"                                   , 1964L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "MYS", "Malaysia"                                 , 1957L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "NAM", "Namibia"                                  , 1990L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "NER", "Niger"                                    , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "NGA", "Nigeria"                                  , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "NIC", "Nicaragua"                                , 1840L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "NLD", "Netherlands"                              , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "NOR", "Norway"                                   , 1905L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "NPL", "Nepal"                                    , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "NRU", "Naoero"                                   , 1968L, NA_integer_, "G&W; COW from UN admission 1999",
  "NZL", "New Zealand"                              , 1907L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "OMN", "Oman"                                     , 1816L, NA_integer_, "G&W; COW from UN admission 1971",
  "PAK", "Pakistan"                                 , 1947L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "PAN", "Panama"                                   , 1903L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "PER", "Peru"                                     , 1824L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "PHL", "Philippines"                              , 1946L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "PLW", "Palau"                                    , 1994L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "PNG", "Papua New Guinea"                         , 1975L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "POL", "Poland"                                   , 1918L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "PRK", "Korea, Dem. People's Rep."                , 1948L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "PRT", "Portugal"                                 , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "PRY", "Paraguay"                                 , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "QAT", "Qatar"                                    , 1971L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ROU", "Romania"                                  , 1878L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "RUS", "Russian Federation"                       , 1816L, NA_integer_, "Continuing state of the USSR (G&W, COW)",
  "RVN", "Republic of Vietnam (South Vietnam)"      , 1954L, 1974L      , "G&W/COW 1954; fell 30 Apr 1975; IMF member 1956-75, no arrangements",
  "RWA", "Rwanda"                                   , 1962L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SAU", "Saudi Arabia"                             , 1932L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SDN", "Sudan"                                    , 1956L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SEN", "Senegal"                                  , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SGP", "Singapore"                                , 1965L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SLB", "Solomon Islands"                          , 1978L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SLE", "Sierra Leone"                             , 1961L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SLV", "El Salvador"                              , 1840L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SMR", "San Marino"                               , 1816L, NA_integer_, "G&W microstate; COW from UN admission 1992",
  "SOM", "Somalia, Fed. Rep."                       , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SRB", "Serbia"                                   , 1992L, NA_integer_, "FR Yugoslavia proclaimed 28 Apr 1992; new state, not SFRY continuation",
  "SSD", "South Sudan"                              , 2011L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "STP", "Sao Tome and Principe"                    , 1975L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SUR", "Suriname"                                 , 1975L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SVK", "Slovak Republic"                          , 1993L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SVN", "Slovenia"                                 , 1992L, NA_integer_, "Recognised 15 Jan 1992 (COW); declared 25 Jun 1991",
  "SWE", "Sweden"                                   , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SWZ", "Eswatini"                                 , 1968L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SYC", "Seychelles"                               , 1976L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "SYR", "Syrian Arab Republic"                     , 1946L, NA_integer_, "Continuous through UAR 1958-61 (G&W); separate IMF member, 1960 SBA",
  "TCD", "Chad"                                     , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "TGO", "Togo"                                     , 1960L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "THA", "Thailand"                                 , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "TJK", "Tajikistan"                               , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "TKM", "Turkmenistan"                             , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "TLS", "Timor-Leste"                              , 2002L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "TON", "Tonga"                                    , 1970L, NA_integer_, "G&W; COW from UN admission 1999",
  "TTO", "Trinidad and Tobago"                      , 1962L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "TUN", "Tunisia"                                  , 1956L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "TUR", "Turkiye"                                  , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "TUV", "Tuvalu"                                   , 1978L, NA_integer_, "G&W; COW from UN admission 2000",
  "TWN", "Taiwan (Republic of China)"               , 1949L, NA_integer_, "G&W/COW 1949; held China IMF seat to Apr 1980; not on World Bank list",
  "TZA", "Tanzania"                                 , 1961L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "UGA", "Uganda"                                   , 1962L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "UKR", "Ukraine"                                  , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "URY", "Uruguay"                                  , 1830L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "USA", "United States"                            , 1816L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "UZB", "Uzbekistan"                               , 1991L, NA_integer_, "Former Soviet republic; independent by 31 Dec 1991 (G&W, COW)",
  "VCT", "St. Vincent and the Grenadines"           , 1979L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "VEN", "Venezuela, RB"                            , 1829L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "VNM", "Viet Nam"                                 , 1954L, NA_integer_, "Democratic Republic of Vietnam (north) from 1954; unified 1976",
  "VUT", "Vanuatu"                                  , 1980L, NA_integer_, "G&W 30 Jul 1980; COW 1981",
  "WSM", "Samoa"                                    , 1962L, NA_integer_, "G&W; COW from UN admission 1976",
  "XKX", "Kosovo"                                   , 2008L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "YAR", "Yemen Arab Republic (North Yemen)"        , 1918L, 1989L      , "Incl. Kingdom of Yemen; merged 22 May 1990 (IMF key 1066)",
  "YEM", "Yemen, Rep."                              , 1990L, NA_integer_, "Unification 22 May 1990 created a new state (COW)",
  "YMD", "Yemen, People's Dem. Rep. (South Yemen)"  , 1967L, 1989L      , "Independent 30 Nov 1967; merged 22 May 1990 (IMF key 1068)",
  "YUG", "Yugoslavia (SFR)"                         , 1918L, 1991L      , "Dissolved 1992; last full year 1991 (IMF member key 1070)",
  "ZAF", "South Africa"                             , 1910L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ZAN", "Zanzibar"                                 , 1963L, 1963L      , "Independent 19 Dec 1963; union with Tanganyika 26 Apr 1964",
  "ZMB", "Zambia"                                   , 1964L, NA_integer_, "Gleditsch-Ward; COW agrees on panel years",
  "ZWE", "Zimbabwe"                                 , 1980L, NA_integer_, "Legal independence 18 Apr 1980 (UDI 1965 not recognised)"
)

# IMF member keys of former states and the code each maps to.
FORMER_STATE_MEMBER_KEYS <- tibble::tribble(
  ~member_key, ~imf_country,                              ~country_code,
  240L,        "Czechoslovakia",                          "CSK",
  1070L,       "Yugoslavia, Federal Republic of",         "YUG",
  1066L,       "Yemen Arab Republic",                     "YAR",
  1068L,       "Yemen, People's Democratic Republic of",  "YMD"
)

# The IMF seats of China and Vietnam were held by other states in the past.
# Arrangements under these member keys before the dates below would belong to
# Taiwan (Republic of China, which held China's seat until 17 April 1980) or
# to South Vietnam (the Vietnamese IMF member until reunification on
# 2 July 1976). None exist at present; the script stops if any appear.
SEAT_HOLDER_CHECKS <- tibble::tribble(
  ~country_code, ~before_date,              ~earlier_holder,
  "CHN",         as.Date("1980-04-17"),     "TWN",
  "VNM",         as.Date("1976-07-02"),     "RVN"
)

if (anyDuplicated(STATE_EXISTENCE$country_code) > 0L) {
  stop("STATE_EXISTENCE contains duplicate country codes.", call. = FALSE)
}

if (any(!is.na(STATE_EXISTENCE$last_year) &
        STATE_EXISTENCE$last_year < STATE_EXISTENCE$first_year)) {
  stop("STATE_EXISTENCE has a last_year before its first_year.", call. = FALSE)
}

if (!all(FORMER_STATE_MEMBER_KEYS$country_code %in% STATE_EXISTENCE$country_code)) {
  stop("Every FORMER_STATE_MEMBER_KEYS code must appear in STATE_EXISTENCE.", call. = FALSE)
}

# ---- Helpers ----------------------------------------------------------------

require_columns <- function(data, required, object_name) {
  missing <- setdiff(required, names(data))
  
  if (length(missing) > 0L) {
    stop(
      object_name,
      " is missing required column(s): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  
  invisible(data)
}

coerce_excel_date <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  
  if (inherits(x, c("POSIXct", "POSIXlt"))) {
    return(as.Date(x))
  }
  
  if (is.numeric(x)) {
    return(as.Date(x, origin = "1899-12-30"))
  }
  
  x_chr <- str_squish(as.character(x))
  x_chr[x_chr %in% c("", "NA", "N/A", "NULL")] <- NA_character_
  
  parsed <- suppressWarnings(ymd(x_chr, quiet = TRUE))
  unresolved <- is.na(parsed) & !is.na(x_chr)
  
  if (any(unresolved)) {
    parsed[unresolved] <- suppressWarnings(
      mdy(x_chr[unresolved], quiet = TRUE)
    )
  }
  
  as.Date(parsed)
}

normalize_country_name <- function(x) {
  x_ascii <- iconv(as.character(x), from = "", to = "ASCII//TRANSLIT")
  
  x_ascii |>
    str_to_lower() |>
    str_replace_all("&", " and ") |>
    str_replace_all("[^a-z0-9]+", " ") |>
    str_squish()
}

empty_metrics <- function() {
  tibble(
    country_code = character(),
    year = integer(),
    m = integer(),
    nn = integer(),
    n6 = integer(),
    ge3 = integer(),
    ge4 = integer(),
    ge5 = integer(),
    ge6 = integer()
  )
}

# Print validation rows to the console rather than creating separate files.
print_validation_rows <- function(title, data) {
  message("")
  message(title)
  
  if (nrow(data) == 0L) {
    message("  None.")
  } else {
    print(data, n = Inf, width = Inf)
  }
  
  invisible(data)
}

# Merge every connected chain of strictly overlapping arrangements. As in the
# Stata code, a new arrangement beginning exactly when the previous one expires
# is treated as a separate spell because the original overlap test used "<".
merge_overlapping_spells <- function(data) {
  if (nrow(data) == 0L) {
    return(tibble(
      country_code = character(),
      start_date = as.Date(character()),
      end_date = as.Date(character())
    ))
  }
  
  data |>
    transmute(
      country_code,
      start_date = date_of_arrangement,
      end_date = expiration_date
    ) |>
    distinct() |>
    arrange(country_code, start_date, end_date) |>
    group_by(country_code) |>
    mutate(
      end_number = as.numeric(end_date),
      prior_maximum_end = lag(cummax(end_number)),
      new_spell = row_number() == 1L |
        as.numeric(start_date) >= prior_maximum_end,
      spell_id = cumsum(new_spell)
    ) |>
    group_by(country_code, spell_id) |>
    summarise(
      start_date = min(start_date),
      end_date = max(end_date),
      .groups = "drop"
    ) |>
    arrange(country_code, start_date, end_date)
}

# Literal translation of the Stata row-by-row spell cleaning. This is used only
# to verify that robust connected-spell merging does not change the results.
clean_spells_literal_stata <- function(data) {
  if (nrow(data) == 0L) {
    return(tibble(
      country_code = character(),
      start_date = as.Date(character()),
      end_date = as.Date(character())
    ))
  }
  
  data |>
    transmute(
      country_code,
      start_date = date_of_arrangement,
      end_date = expiration_date,
      input_order = row_number(),
      duration_months =
        12L * (year(expiration_date) - year(date_of_arrangement)) +
        month(expiration_date) - month(date_of_arrangement)
    ) |>
    arrange(country_code, start_date, duration_months, input_order) |>
    group_by(country_code, start_date, end_date) |>
    slice_tail(n = 1L) |>
    ungroup() |>
    arrange(country_code, start_date, duration_months, input_order) |>
    group_by(country_code, start_date) |>
    slice_tail(n = 1L) |>
    ungroup() |>
    arrange(country_code, start_date, duration_months, input_order) |>
    group_by(country_code) |>
    mutate(
      drop_nested = coalesce(end_date <= lag(end_date), FALSE)
    ) |>
    filter(!drop_nested) |>
    ungroup() |>
    arrange(country_code, start_date, duration_months, input_order) |>
    group_by(country_code) |>
    mutate(
      next_start_date = lead(start_date),
      next_end_date = lead(end_date),
      extend_end = coalesce(
        next_start_date < end_date & next_end_date > end_date,
        FALSE
      ),
      end_date = if_else(extend_end, next_end_date, end_date)
    ) |>
    ungroup() |>
    arrange(country_code, start_date, duration_months, input_order) |>
    group_by(country_code) |>
    mutate(
      drop_overlap = coalesce(start_date < lag(end_date), FALSE)
    ) |>
    filter(!drop_overlap) |>
    ungroup() |>
    select(country_code, start_date, end_date) |>
    arrange(country_code, start_date, end_date)
}

# Reproduce the annual month arithmetic used by the Stata code.
calculate_legacy_metrics <- function(spells, years) {
  if (nrow(spells) == 0L) {
    return(empty_metrics())
  }
  
  spells |>
    mutate(
      start_year = year(start_date),
      end_year = year(end_date),
      start_month = month(start_date),
      end_month = month(end_date)
    ) |>
    crossing(year = years) |>
    filter(year >= start_year, year <= end_year) |>
    mutate(
      legacy_months = case_when(
        start_year == end_year ~ end_month - start_month,
        year == start_year ~ 13L - start_month,
        year == end_year ~ end_month,
        TRUE ~ 12L
      ),
      ended = as.integer(year == end_year)
    ) |>
    group_by(country_code, year) |>
    summarise(
      m = sum(legacy_months),
      ended = max(ended),
      .groups = "drop"
    ) |>
    mutate(
      m = as.integer(if_else(m == 13, 12, m)),
      nn = 1L,
      n6 = as.integer(ended == 1L | m >= 6L),
      ge3 = as.integer(m >= 3L),
      ge4 = as.integer(m >= 4L),
      ge5 = as.integer(m >= 5L),
      ge6 = as.integer(m >= 6L)
    ) |>
    select(country_code, year, m, nn, n6, ge3, ge4, ge5, ge6)
}

# Official method when MONTH_METHOD = “calendar”: count distinct calendar
# months touched by a spell.
calculate_calendar_month_metrics <- function(spells, years) {
  if (nrow(spells) == 0L) {
    return(empty_metrics())
  }
  
  months_present <- spells |>
    mutate(
      month_start = map2(
        start_date,
        end_date,
        ~ seq.Date(
          as.Date(floor_date(.x, unit = "month")),
          as.Date(floor_date(.y, unit = "month")),
          by = "month"
        )
      )
    ) |>
    select(country_code, month_start) |>
    unnest(month_start) |>
    mutate(year = year(month_start)) |>
    filter(year %in% years) |>
    distinct(country_code, year, month_start) |>
    group_by(country_code, year) |>
    summarise(m = n_distinct(month_start), .groups = "drop")
  
  end_events <- spells |>
    transmute(
      country_code,
      year = year(end_date),
      ended = 1L
    ) |>
    filter(year %in% years) |>
    distinct(country_code, year, .keep_all = TRUE)
  
  months_present |>
    left_join(end_events, by = c("country_code", "year")) |>
    mutate(
      m = as.integer(m),
      ended = replace_na(ended, 0L),
      nn = 1L,
      n6 = as.integer(ended == 1L | m >= 6L),
      ge3 = as.integer(m >= 3L),
      ge4 = as.integer(m >= 4L),
      ge5 = as.integer(m >= 5L),
      ge6 = as.integer(m >= 6L)
    ) |>
    select(country_code, year, m, nn, n6, ge3, ge4, ge5, ge6)
}

rename_metric_block <- function(metrics, prefix) {
  output <- metrics |>
    select(country_code, year, m, nn, n6, ge3, ge4, ge5, ge6)
  
  names(output)[3:9] <- paste0(
    prefix,
    c("m", "nn", "6n", "33", "44", "55", "66")
  )
  
  output
}

stack_metric_list <- function(metric_list) {
  imap_dfr(
    metric_list,
    ~ mutate(.x, program_group = .y, .before = 1L)
  )
}

compare_metric_sets <- function(reference, comparison, suffixes) {
  metric_names <- c("m", "nn", "n6", "ge3", "ge4", "ge5", "ge6")
  
  compared <- full_join(
    reference,
    comparison,
    by = c("program_group", "country_code", "year"),
    suffix = suffixes
  )
  
  comparison_columns <- c(
    paste0(metric_names, suffixes[[1]]),
    paste0(metric_names, suffixes[[2]])
  )
  
  compared |>
    mutate(
      across(
        all_of(comparison_columns),
        ~ replace_na(as.integer(.x), 0L)
      ),
      different =
        .data[[paste0("m", suffixes[[1]])]] !=
        .data[[paste0("m", suffixes[[2]])]] |
        .data[[paste0("nn", suffixes[[1]])]] !=
        .data[[paste0("nn", suffixes[[2]])]] |
        .data[[paste0("n6", suffixes[[1]])]] !=
        .data[[paste0("n6", suffixes[[2]])]] |
        .data[[paste0("ge3", suffixes[[1]])]] !=
        .data[[paste0("ge3", suffixes[[2]])]] |
        .data[[paste0("ge4", suffixes[[1]])]] !=
        .data[[paste0("ge4", suffixes[[2]])]] |
        .data[[paste0("ge5", suffixes[[1]])]] !=
        .data[[paste0("ge5", suffixes[[2]])]] |
        .data[[paste0("ge6", suffixes[[1]])]] !=
        .data[[paste0("ge6", suffixes[[2]])]]
    ) |>
    filter(different) |>
    select(-different)
}

# ---- Read and validate the IMF workbook -------------------------------------

if (!file.exists(INPUT_FILE)) {
  stop(
    "Input workbook not found: ",
    INPUT_FILE,
    ". Place the workbook in the working directory or update INPUT_FILE.",
    call. = FALSE
  )
}

available_sheets <- excel_sheets(INPUT_FILE)
required_sheets <- c("Arrangements", "Members", "Run_Metadata")
missing_sheets <- setdiff(required_sheets, available_sheets)

if (length(missing_sheets) > 0L) {
  stop(
    "Input workbook is missing sheet(s): ",
    paste(missing_sheets, collapse = ", "),
    call. = FALSE
  )
}

arrangements <- read_excel(INPUT_FILE, sheet = "Arrangements") |>
  as_tibble()

members <- read_excel(INPUT_FILE, sheet = "Members") |>
  as_tibble()

run_metadata <- read_excel(INPUT_FILE, sheet = "Run_Metadata") |>
  as_tibble()

require_columns(
  arrangements,
  c(
    "country",
    "member_key",
    "facility",
    "date_of_arrangement",
    "expiration_date"
  ),
  "Arrangements sheet"
)

require_columns(
  members,
  c("country", "member_key"),
  "Members sheet"
)

require_columns(
  run_metadata,
  c("item", "value"),
  "Run_Metadata sheet"
)

# Rows the scraper appended from its MANUAL_ARRANGEMENTS table (source column
# added by the scraper; older raw workbooks without it have no manual rows).
manual_arrangements_in_input <- if ("source" %in% names(arrangements)) {
  arrangements |>
    filter(source == "Manual addition")
} else {
  arrangements[0, ]
}

# Older raw workbooks have no source columns; their rows are all scraped.
if (!"source" %in% names(arrangements)) {
  arrangements$source <- "IMF lending page"
}
if (!"source_note" %in% names(arrangements)) {
  arrangements$source_note <- NA_character_
}

arrangements <- arrangements |>
  transmute(
    imf_country = str_squish(as.character(country)),
    member_key = as.integer(member_key),
    facility = as.character(facility) |>
      str_remove_all(regex("<sup[^>]*>.*?</sup>", ignore_case = TRUE)) |>
      str_squish(),
    date_of_arrangement = coerce_excel_date(date_of_arrangement),
    expiration_date = coerce_excel_date(expiration_date),
    source = as.character(source),
    source_note = as.character(source_note)
  )

# Separate rapid facilities immediately. Only arrangements_for_indicators is
# permitted to enter validation, overlap cleaning, spells, or indicators.
excluded_rapid_arrangements <- arrangements |>
  filter(facility %in% EXCLUDED_RAPID_FACILITIES)

arrangements_for_indicators <- arrangements |>
  filter(!facility %in% EXCLUDED_RAPID_FACILITIES)

members <- members |>
  transmute(
    imf_country = str_squish(as.character(country)),
    member_key = as.integer(member_key)
  ) |>
  distinct()

# The scraper's Members sheet lists only current members (the IMF dropdown).
# Former or withdrawn members whose arrangements were added to the
# Arrangements sheet (e.g. Cuba, Czechoslovakia, Yugoslavia) are added here
# from the Arrangements sheet so that every arrangement has a member row.
members_added_from_arrangements <- arrangements |>
  distinct(imf_country, member_key) |>
  anti_join(members, by = "member_key")

members <- bind_rows(members, members_added_from_arrangements)

as_of_value <- run_metadata |>
  filter(item == "IMF As of Date used") |>
  pull(value)

if (length(as_of_value) != 1L) {
  stop(
    "Run_Metadata must contain exactly one 'IMF As of Date used' value.",
    call. = FALSE
  )
}

imf_as_of_date <- coerce_excel_date(as_of_value)

if (length(imf_as_of_date) != 1L || is.na(imf_as_of_date)) {
  stop("The IMF as-of date could not be parsed from Run_Metadata.", call. = FALSE)
}

if (!is.logical(INCLUDE_AS_OF_YEAR) ||
    length(INCLUDE_AS_OF_YEAR) != 1L ||
    is.na(INCLUDE_AS_OF_YEAR)) {
  stop("INCLUDE_AS_OF_YEAR must be either TRUE or FALSE.", call. = FALSE)
}

if (length(YEAR_MAX_OVERRIDE) != 1L ||
    (!is.na(YEAR_MAX_OVERRIDE) &&
     (!is.numeric(YEAR_MAX_OVERRIDE) ||
      YEAR_MAX_OVERRIDE != as.integer(YEAR_MAX_OVERRIDE)))) {
  stop("YEAR_MAX_OVERRIDE must be NA or one integer year.", call. = FALSE)
}

default_year_max <- year(imf_as_of_date) -
  if (isTRUE(INCLUDE_AS_OF_YEAR)) 0L else 1L

year_max <- if (is.na(YEAR_MAX_OVERRIDE)) {
  default_year_max
} else {
  as.integer(YEAR_MAX_OVERRIDE)
}

if (length(year_max) != 1L || is.na(year_max)) {
  stop("YEAR_MAX_OVERRIDE must be NA or one integer year.", call. = FALSE)
}

if (year_max > year(imf_as_of_date)) {
  stop(
    "YEAR_MAX_OVERRIDE cannot exceed the year of the workbook's IMF as-of date.",
    call. = FALSE
  )
}

analysis_cutoff_date <- min(
  imf_as_of_date,
  make_date(year_max, 12L, 31L)
)

if (anyNA(arrangements_for_indicators$date_of_arrangement) ||
    anyNA(arrangements_for_indicators$expiration_date)) {
  stop(
    "At least one retained programme arrangement or expiration date is missing or could not be parsed.",
    call. = FALSE
  )
}

future_dated_arrangements <- arrangements_for_indicators |>
  filter(date_of_arrangement > imf_as_of_date)

if (nrow(future_dated_arrangements) > 0L) {
  print_validation_rows(
    "Arrangements after the workbook IMF as-of date:",
    future_dated_arrangements
  )
  
  stop(
    "At least one retained programme arrangement begins after the workbook's IMF as-of date.",
    call. = FALSE
  )
}

invalid_intervals <- arrangements_for_indicators |>
  mutate(
    reversal_days = as.integer(date_of_arrangement - expiration_date)
  ) |>
  filter(reversal_days > 0L)

invalid_intervals_in_window <- invalid_intervals |>
  filter(date_of_arrangement <= analysis_cutoff_date)

invalid_intervals_after_cutoff <- invalid_intervals |>
  filter(date_of_arrangement > analysis_cutoff_date)

if (nrow(invalid_intervals_in_window) > 0L) {
  print_validation_rows(
    "Invalid retained arrangement intervals:",
    invalid_intervals_in_window
  )
  
  stop(
    "At least one retained programme arrangement expires before it begins.",
    call. = FALSE
  )
}

duplicate_member_keys <- members |>
  count(member_key) |>
  filter(n > 1L)

if (nrow(duplicate_member_keys) > 0L) {
  print_validation_rows(
    "Duplicate IMF member keys:",
    duplicate_member_keys
  )
  
  stop(
    "The Members sheet contains duplicate member keys assigned to different rows.",
    call. = FALSE
  )
}

# ---- Download the live World Bank economy universe --------------------------

wb_response <- tryCatch(
  request(WB_COUNTRY_API) |>
    req_user_agent("IMFMonitor country-year research script/1.0") |>
    req_timeout(seconds = 60) |>
    req_retry(max_tries = 4) |>
    req_perform(),
  error = function(e) {
    stop(
      "Could not retrieve the World Bank country list: ",
      conditionMessage(e),
      call. = FALSE
    )
  }
)

wb_json <- fromJSON(resp_body_string(wb_response), flatten = TRUE)

if (length(wb_json) < 2L || is.null(wb_json[[2]])) {
  stop("The World Bank API returned an unexpected response.", call. = FALSE)
}

wb_all <- as_tibble(wb_json[[2]])

require_columns(
  wb_all,
  c(
    "id",
    "iso2Code",
    "name",
    "region.id",
    "region.value",
    "incomeLevel.value",
    "lendingType.value"
  ),
  "World Bank country response"
)

wb_economies <- wb_all |>
  filter(!is.na(region.id), region.id != "NA") |>
  transmute(
    country_code = as.character(id),
    country_code2 = as.character(iso2Code),
    country_name = str_squish(as.character(name)),
    region = str_squish(as.character(region.value)),
    income_level = str_squish(as.character(incomeLevel.value)),
    lending_type = str_squish(as.character(lendingType.value)),
    normalized_name = normalize_country_name(country_name)
  ) |>
  arrange(country_code)

if (anyDuplicated(wb_economies$country_code) > 0L) {
  stop("The World Bank economy list contains duplicate three-letter codes.", call. = FALSE)
}

if (nrow(wb_economies) != 217L) {
  warning(
    "The World Bank API currently returns ",
    nrow(wb_economies),
    " non-aggregate economies rather than the 217 expected when this script was written. ",
    "The script will continue using the live list."
  )
}

# ---- IMF-to-World Bank country concordance ----------------------------------

manual_country_map <- tribble(
  ~imf_country,                                      ~manual_code,
  "Afghanistan, Islamic Republic of",               "AFG",
  "Armenia, Republic of",                           "ARM",
  "Bahrain, Kingdom of",                            "BHR",
  "Belarus, Republic of",                           "BLR",
  "Congo, Democratic Republic of",                  "COD",
  "Congo, Republic of",                             "COG",
  "Croatia, Republic of",                           "HRV",
  "Czech Republic",                                 "CZE",
  "Egypt",                                          "EGY",
  "Estonia, Republic of",                           "EST",
  "Eswatini, The Kingdom of",                       "SWZ",
  "Iran, Islamic Republic of",                      "IRN",
  "Kazakhstan, Republic of",                        "KAZ",
  "Korea",                                          "KOR",
  "Lao People's Democratic Republic",               "LAO",
  "Latvia, Republic of",                            "LVA",
  "Lithuania, Republic of",                         "LTU",
  "Micronesia, Federated States of",                "FSM",
  "Moldova, Republic of",                           "MDA",
  "Montenegro, Republic of",                        "MNE",
  "Nauru",                                          "NRU",
  "Naoero, Republic of",                            "NRU",
  "Netherlands, The",                               "NLD",
  "North Macedonia, Republic of",                   "MKD",
  "Poland, Republic of",                            "POL",
  "San Marino, Republic of",                        "SMR",
  "Sao Tome & Principe",                            "STP",
  "Serbia, Republic of",                            "SRB",
  "Slovenia, Republic of",                          "SVN",
  "Somalia",                                        "SOM",
  "Tajikistan, Republic of",                        "TJK",
  "Timor-Leste, The Democratic Republic of",        "TLS",
  "Turkmenistan, Republic of",                      "TKM",
  "Türkiye, Republic of",                           "TUR",
  "Uzbekistan, Republic of",                        "UZB",
  "Venezuela",                                      "VEN",
  "Vietnam",                                        "VNM",
  "Yemen, Republic of",                             "YEM"
)

wb_auto_lookup <- wb_economies |>
  add_count(normalized_name, name = "normalized_name_count") |>
  filter(normalized_name_count == 1L) |>
  select(normalized_name, auto_code = country_code)

former_members <- members |>
  filter(member_key %in% FORMER_STATE_MEMBER_KEYS$member_key)

current_members <- members |>
  filter(!member_key %in% FORMER_STATE_MEMBER_KEYS$member_key)

member_crosswalk <- current_members |>
  mutate(normalized_name = normalize_country_name(imf_country)) |>
  left_join(wb_auto_lookup, by = "normalized_name") |>
  left_join(manual_country_map, by = "imf_country")

conflicting_matches <- member_crosswalk |>
  filter(
    !is.na(auto_code),
    !is.na(manual_code),
    auto_code != manual_code
  )

if (nrow(conflicting_matches) > 0L) {
  print_validation_rows(
    "Conflicting automatic/manual country matches:",
    conflicting_matches
  )
  
  stop(
    "At least one automatic country match conflicts with the manual concordance.",
    call. = FALSE
  )
}

member_crosswalk <- member_crosswalk |>
  mutate(
    country_code = coalesce(manual_code, auto_code),
    match_method = case_when(
      !is.na(manual_code) ~ "Reviewed manual concordance",
      !is.na(auto_code) ~ "Normalized exact name",
      TRUE ~ "Unmatched"
    )
  ) |>
  left_join(
    wb_economies |>
      select(country_code, country_name),
    by = "country_code"
  ) |>
  select(
    imf_country,
    member_key,
    country_code,
    country_name,
    match_method
  )

# Former member states never match the live World Bank list, so they are
# mapped to their own codes from FORMER_STATE_MEMBER_KEYS.
former_crosswalk <- former_members |>
  left_join(
    FORMER_STATE_MEMBER_KEYS |>
      select(member_key, country_code),
    by = "member_key"
  ) |>
  left_join(
    STATE_EXISTENCE |>
      select(country_code, country_name),
    by = "country_code"
  ) |>
  transmute(
    imf_country,
    member_key,
    country_code,
    country_name,
    match_method = "Former IMF member: own code"
  )

member_crosswalk <- bind_rows(member_crosswalk, former_crosswalk) |>
  arrange(country_code, imf_country)

unmatched_members <- member_crosswalk |>
  filter(is.na(country_code) | is.na(country_name))

if (nrow(unmatched_members) > 0L) {
  print_validation_rows(
    "Unmatched IMF members:",
    unmatched_members
  )
  
  stop(
    "At least one IMF member could not be mapped to the World Bank universe.",
    call. = FALSE
  )
}

duplicate_wb_matches <- member_crosswalk |>
  count(country_code) |>
  filter(n > 1L)

if (nrow(duplicate_wb_matches) > 0L) {
  print_validation_rows(
    "Duplicate World Bank matches:",
    duplicate_wb_matches
  )
  
  stop(
    "More than one IMF member maps to the same World Bank economy.",
    call. = FALSE
  )
}

# Every IMF member must map to an independent state in STATE_EXISTENCE.
members_not_states <- member_crosswalk |>
  filter(!country_code %in% STATE_EXISTENCE$country_code)

if (nrow(members_not_states) > 0L) {
  print_validation_rows(
    "IMF members mapped to an economy that is not in STATE_EXISTENCE:",
    members_not_states
  )
  
  stop(
    "At least one IMF member maps to an economy with no STATE_EXISTENCE row.",
    call. = FALSE
  )
}

member_code_lookup <- member_crosswalk |>
  select(imf_country_member = imf_country, member_key, country_code)

arrangements_for_indicators <- arrangements_for_indicators |>
  left_join(member_code_lookup, by = "member_key")

excluded_rapid_arrangements <- excluded_rapid_arrangements |>
  left_join(member_code_lookup, by = "member_key")

arrangements_all <- bind_rows(
  arrangements_for_indicators,
  excluded_rapid_arrangements
)

country_name_mismatches <- arrangements_all |>
  filter(imf_country != imf_country_member)

if (nrow(country_name_mismatches) > 0L) {
  print_validation_rows(
    "IMF arrangement/member country-name mismatches:",
    country_name_mismatches
  )
  
  stop(
    "Arrangement and member-sheet country names disagree for at least one member key.",
    call. = FALSE
  )
}

if (anyNA(arrangements_all$country_code)) {
  stop("At least one arrangement lacks a World Bank country code.", call. = FALSE)
}

seat_holder_conflicts <- arrangements_all |>
  inner_join(SEAT_HOLDER_CHECKS, by = "country_code") |>
  filter(date_of_arrangement < before_date)

if (nrow(seat_holder_conflicts) > 0L) {
  print_validation_rows(
    "Arrangements recorded under a seat held at the time by another state:",
    seat_holder_conflicts
  )
  
  stop(
    "At least one China or Vietnam arrangement predates the current seat ",
    "holder; reassign it to TWN or RVN (see SEAT_HOLDER_CHECKS).",
    call. = FALSE
  )
}

# ---- Select years and classify facilities -----------------------------------

year_min <- min(
  year(arrangements_for_indicators$date_of_arrangement),
  na.rm = TRUE
)

if (year_max < year_min) {
  stop("The final year precedes the earliest arrangement year.", call. = FALSE)
}

years <- seq.int(year_min, year_max)

# Panel universe: every independent state in STATE_EXISTENCE for each year in
# which it existed. World Bank names are used where the World Bank lists the
# state; former states and Taiwan keep the names in STATE_EXISTENCE.
panel_names <- STATE_EXISTENCE |>
  select(country_code, existence_name = country_name) |>
  left_join(
    wb_economies |>
      select(country_code, wb_name = country_name),
    by = "country_code"
  ) |>
  transmute(
    country_code,
    country_name = coalesce(wb_name, existence_name),
    on_world_bank_list = !is.na(wb_name)
  )

panel_universe <- STATE_EXISTENCE |>
  select(country_code, first_year, last_year) |>
  crossing(year = years) |>
  filter(
    year >= first_year,
    is.na(last_year) | year <= last_year
  ) |>
  left_join(
    panel_names |>
      select(country_code, country_name),
    by = "country_code"
  ) |>
  select(country_name, country_code, year)

states_not_on_wb_list <- panel_names |>
  filter(!on_world_bank_list) |>
  select(country_code, country_name)

# World Bank economies that are not independent states (dependent
# territories) are excluded from the panel.
excluded_wb_economies <- wb_economies |>
  filter(!country_code %in% STATE_EXISTENCE$country_code) |>
  select(country_code, country_name, region, income_level)

EXPECTED_EXCLUDED_TERRITORIES <- c(
  "ABW", "ASM", "BMU", "CHI", "CUW", "CYM", "FRO", "GIB", "GRL", "GUM",
  "HKG", "IMN", "MAC", "MAF", "MNP", "NCL", "PRI", "PSE", "PYF", "SXM",
  "TCA", "VGB", "VIR"
)

unexpected_exclusions <- setdiff(
  excluded_wb_economies$country_code,
  EXPECTED_EXCLUDED_TERRITORIES
)

if (length(unexpected_exclusions) > 0L) {
  warning(
    "The World Bank list contains economies that are neither in ",
    "STATE_EXISTENCE nor known dependent territories: ",
    paste(unexpected_exclusions, collapse = ", "),
    ". They are excluded; add them to STATE_EXISTENCE if they are ",
    "independent states."
  )
}

expected_wb_states_missing <- STATE_EXISTENCE |>
  filter(
    is.na(last_year),
    country_code != "TWN",
    !country_code %in% wb_economies$country_code
  )

if (nrow(expected_wb_states_missing) > 0L) {
  warning(
    "These existing states are not on the live World Bank list and keep their ",
    "STATE_EXISTENCE names: ",
    paste(expected_wb_states_missing$country_code, collapse = ", ")
  )
}

window_start <- make_date(year_min, 1L, 1L)

arrangements_window <- arrangements_for_indicators |>
  filter(
    date_of_arrangement <= analysis_cutoff_date,
    expiration_date >= window_start
  )

excluded_rapid_facilities <- excluded_rapid_arrangements |>
  filter(
    is.na(date_of_arrangement) |
      date_of_arrangement <= analysis_cutoff_date
  ) |>
  mutate(
    exclusion_reason = if_else(
      facility %in% c("Rapid Credit Facility", "Rapid Financing Instrument"),
      paste0(
        "Excluded rapid-disbursement facility; does not enter ",
        "IMF*, conIMF*, or nonIMF* indicators"
      ),
      paste0(
        "Excluded outright purchase (manual addition); does not enter ",
        "IMF*, conIMF*, or nonIMF* indicators"
      )
    ),
    interval_status = case_when(
      is.na(date_of_arrangement) | is.na(expiration_date) ~
        "Missing or unparsed date",
      expiration_date < date_of_arrangement ~
        "Expiration precedes approval",
      TRUE ~ "Valid"
    )
  ) |>
  relocate(source, source_note, .after = last_col()) |>
  arrange(country_code, date_of_arrangement, facility)

# Excluded observations do not enter the indicators, but each should still
# belong to a state that existed in that year. A failure here usually means a
# wrong member key (e.g. an FR Yugoslavia purchase recorded under the SFR
# Yugoslavia key) or a STATE_EXISTENCE error.
excluded_outside_panel <- excluded_rapid_facilities |>
  filter(!is.na(date_of_arrangement)) |>
  mutate(year = year(date_of_arrangement)) |>
  anti_join(panel_universe, by = c("country_code", "year"))

if (nrow(excluded_outside_panel) > 0L) {
  print_validation_rows(
    "Excluded facility observations with no row in the panel universe:",
    excluded_outside_panel
  )

  stop(
    "At least one excluded facility observation falls in a country-year ",
    "outside the panel universe (check its member key and STATE_EXISTENCE).",
    call. = FALSE
  )
}

arrangements_window_all <- bind_rows(
  arrangements_window |>
    mutate(
      exclusion_reason = NA_character_,
      interval_status = "Valid"
    ),
  excluded_rapid_facilities
)

# The original Stata split defined non-concessional programmes as the
# complement of a named concessional list. Here that exhaustive split is
# applied only after RCF, RFI, ENDA, EPCA and STF observations have been
# removed. The RSF is an
# RST—not a GRA—facility, but it remains in nonIMF* because it lies outside the
# PRGT/legacy concessional group.
facility_classification <- tibble::tribble(
  ~facility, ~indicator_group, ~institutional_group, ~classification_note, ~source_url,
  "Extended Credit Facility", "Concessional", "PRGT", "Current PRGT concessional facility", "https://www.imf.org/en/about/factsheets/imf-support-for-low-income-countries",
  "Standby Credit Facility", "Concessional", "PRGT", "Current PRGT concessional facility", "https://www.imf.org/en/about/factsheets/imf-support-for-low-income-countries",
  "Rapid Credit Facility", "Excluded", "PRGT", "Rapid-disbursement facility excluded from all programme indicators", "https://www.imf.org/en/about/factsheets/sheets/2023/rapid-credit-facility-rcf",
  "Exogenous Shock Facility", "Concessional", "Legacy PRGT/LIC facility", "Legacy concessional low-income-country facility", "https://www.imf.org/en/news/articles/2015/09/28/04/53/pn0994",
  "Structural Adjustment Facility Commitment", "Concessional", "Legacy LIC facility", "Legacy concessional low-income-country facility", "https://archivescatalog.imf.org/Details/archive/110050371",
  "Standby Arrangement", "Non-concessional", "GRA", "GRA facility", "https://www.imf.org/en/about/factsheets/imf-lending",
  "Extended Fund Facility", "Non-concessional", "GRA", "GRA facility", "https://www.imf.org/en/about/factsheets/imf-lending",
  "Flexible Credit Line", "Non-concessional", "GRA", "GRA facility", "https://www.imf.org/en/about/factsheets/imf-lending",
  "Precautionary and Liquidity Line", "Non-concessional", "GRA", "GRA facility", "https://www.imf.org/en/about/factsheets/imf-lending",
  "Rapid Financing Instrument", "Excluded", "GRA", "Rapid-disbursement instrument excluded from all programme indicators", "https://www.imf.org/en/about/factsheets/sheets/2023/rapid-financing-instrument-rfi",
  "Short-Term Liquidity Line", "Non-concessional", "GRA", "GRA facility", "https://www.imf.org/en/about/factsheets/imf-lending",
  "Resilience and Sustainability Facility", "Non-concessional", "RST", "Included in the non-PRGT complement to reproduce the original Stata split; not a GRA facility", "https://www.imf.org/en/about/factsheets/sheets/2023/resilience-sustainability-facility-rsf",
  "Emergency Natural Disaster Assistance", "Excluded", "GRA", "Outright emergency purchase, 1962-2011 (manual addition in the raw workbook); excluded from all programme indicators", "https://www.imf.org/external/np/pp/eng/2005/011005.pdf",
  "Emergency Post-Conflict Assistance", "Excluded", "GRA", "Outright emergency purchase, 1995-2011 (manual addition in the raw workbook); excluded from all programme indicators", "https://www.imf.org/external/np/pp/eng/2008/030308.pdf",
  "Systemic Transformation Facility", "Excluded", "GRA", "Temporary facility for transition economies, 1993-95; outright purchases (manual addition in the raw workbook); excluded from all programme indicators", "https://www.imf.org/external/pubs/ft/history/2012/pdf/c5.pdf"
)

if (!all(EXCLUDED_RAPID_FACILITIES %in%
         facility_classification$facility[facility_classification$indicator_group == "Excluded"])) {
  stop(
    "Every EXCLUDED_RAPID_FACILITIES entry needs an 'Excluded' row in facility_classification.",
    call. = FALSE
  )
}

concessional_facilities <- facility_classification |>
  filter(indicator_group == "Concessional") |>
  pull(facility)

nonconcessional_facilities <- facility_classification |>
  filter(indicator_group == "Non-concessional") |>
  pull(facility)

if (any(arrangements_window$facility %in% EXCLUDED_RAPID_FACILITIES)) {
  stop("A rapid facility leaked into the retained programme dataset.", call. = FALSE)
}

unclassified_facilities <- setdiff(
  sort(unique(arrangements_window$facility)),
  c(concessional_facilities, nonconcessional_facilities)
)

if (length(unclassified_facilities) > 0L) {
  stop(
    "Facility classification is incomplete for the requested period: ",
    paste(unclassified_facilities, collapse = ", "),
    call. = FALSE
  )
}

arrangement_groups <- list(
  all = arrangements_window,
  concessional = arrangements_window |>
    filter(facility %in% concessional_facilities),
  nonconcessional = arrangements_window |>
    filter(facility %in% nonconcessional_facilities)
)

# ---- Construct spells and indicators ----------------------------------------

robust_spells <- map(arrangement_groups, merge_overlapping_spells)
literal_stata_spells <- map(arrangement_groups, clean_spells_literal_stata)

legacy_metrics <- map(
  robust_spells,
  calculate_legacy_metrics,
  years = years
)

literal_stata_metrics <- map(
  literal_stata_spells,
  calculate_legacy_metrics,
  years = years
)

calendar_metrics <- map(
  robust_spells,
  calculate_calendar_month_metrics,
  years = years
)

legacy_metrics_long <- stack_metric_list(legacy_metrics)
literal_metrics_long <- stack_metric_list(literal_stata_metrics)
calendar_metrics_long <- stack_metric_list(calendar_metrics)

overlap_diagnostic <- compare_metric_sets(
  legacy_metrics_long,
  literal_metrics_long,
  suffixes = c("_robust", "_literal")
) |>
  left_join(
    panel_names,
    by = "country_code"
  ) |>
  relocate(country_name, .after = country_code) |>
  arrange(program_group, country_code, year)

calendar_diagnostic <- compare_metric_sets(
  legacy_metrics_long,
  calendar_metrics_long,
  suffixes = c("_legacy", "_calendar")
) |>
  left_join(
    panel_names,
    by = "country_code"
  ) |>
  relocate(country_name, .after = country_code) |>
  arrange(program_group, country_code, year)

if (!MONTH_METHOD %in% c("calendar", "legacy")) {
  stop("MONTH_METHOD must be \"calendar\" or \"legacy\".", call. = FALSE)
}

official_metrics <- if (MONTH_METHOD == "calendar") {
  calendar_metrics
} else {
  legacy_metrics
}

indicator_blocks <- list(
  rename_metric_block(official_metrics$all, "IMF"),
  rename_metric_block(official_metrics$concessional, "conIMF"),
  rename_metric_block(official_metrics$nonconcessional, "nonIMF")
)

programme_indicators <- reduce(
  indicator_blocks,
  full_join,
  by = c("country_code", "year")
)

indicator_variables <- c(
  "IMFm", "IMFnn", "IMF6n", "IMF33", "IMF44", "IMF55", "IMF66",
  "conIMFm", "conIMFnn", "conIMF6n", "conIMF33", "conIMF44",
  "conIMF55", "conIMF66",
  "nonIMFm", "nonIMFnn", "nonIMF6n", "nonIMF33", "nonIMF44",
  "nonIMF55", "nonIMF66"
)

# Guard against programme years that fall outside the panel universe (a left
# join would otherwise drop them without warning).
indicators_outside_panel <- programme_indicators |>
  anti_join(panel_universe, by = c("country_code", "year"))

if (nrow(indicators_outside_panel) > 0L) {
  print_validation_rows(
    "Programme country-years with no row in the panel universe:",
    indicators_outside_panel
  )
  
  stop(
    "At least one programme country-year falls outside the panel universe ",
    "(check STATE_EXISTENCE first_year/last_year).",
    call. = FALSE
  )
}

country_year_panel <- panel_universe |>
  left_join(
    programme_indicators,
    by = c("country_code", "year")
  ) |>
  mutate(
    across(
      all_of(indicator_variables),
      ~ replace_na(as.integer(.x), 0L)
    )
  ) |>
  arrange(country_code, year)

# ---- Validation --------------------------------------------------------------

if (anyDuplicated(country_year_panel[c("country_code", "year")]) > 0L) {
  stop("The final panel contains duplicate country-year observations.", call. = FALSE)
}

expected_rows <- nrow(panel_universe)

if (nrow(country_year_panel) != expected_rows) {
  stop(
    "The final panel has ",
    nrow(country_year_panel),
    " rows; expected ",
    expected_rows,
    ".",
    call. = FALSE
  )
}

month_variables <- c("IMFm", "conIMFm", "nonIMFm")
binary_variables <- setdiff(indicator_variables, month_variables)

invalid_month_values <- country_year_panel |>
  filter(if_any(all_of(month_variables), ~ .x < 0L | .x > 12L))

if (nrow(invalid_month_values) > 0L) {
  print_validation_rows(
    "Invalid programme-month values:",
    invalid_month_values
  )
  
  stop(
    "At least one programme-month value lies outside 0-12.",
    call. = FALSE
  )
}

invalid_binary_values <- country_year_panel |>
  filter(if_any(all_of(binary_variables), ~ !.x %in% c(0L, 1L)))

if (nrow(invalid_binary_values) > 0L) {
  print_validation_rows(
    "Invalid binary indicator values:",
    invalid_binary_values
  )
  
  stop(
    "At least one binary indicator has a value other than 0 or 1.",
    call. = FALSE
  )
}

if (nrow(overlap_diagnostic) > 0L) {
  warning(
    "Robust spell merging differs from the literal Stata cleaning for ",
    nrow(overlap_diagnostic),
    " country-year/group observation(s). Review the Overlap_Diagnostic sheet."
  )
}

# ---- Audit tables ------------------------------------------------------------

arrangement_country_summary <- arrangements_window |>
  distinct(country_code) |>
  summarise(n = n()) |>
  pull(n)

rapid_only_countries <- excluded_rapid_facilities |>
  distinct(country_code, imf_country) |>
  anti_join(
    arrangements_window |>
      distinct(country_code),
    by = "country_code"
  ) |>
  left_join(
    panel_names,
    by = "country_code"
  ) |>
  select(country_code, country_name, imf_country) |>
  arrange(country_code)

rapid_interval_anomalies <- excluded_rapid_facilities |>
  filter(interval_status != "Valid")

facility_counts <- arrangements_window_all |>
  count(facility, name = "arrangements") |>
  left_join(facility_classification, by = "facility") |>
  select(
    indicator_group,
    institutional_group,
    facility,
    arrangements,
    classification_note,
    source_url
  ) |>
  arrange(indicator_group, institutional_group, facility)

member_crosswalk_export <- member_crosswalk |>
  left_join(
    arrangements_window |>
      count(member_key, name = "programme_arrangements_retained"),
    by = "member_key"
  ) |>
  left_join(
    excluded_rapid_facilities |>
      count(member_key, name = "rapid_facilities_excluded"),
    by = "member_key"
  ) |>
  mutate(
    programme_arrangements_retained = replace_na(
      programme_arrangements_retained,
      0L
    ),
    rapid_facilities_excluded = replace_na(
      rapid_facilities_excluded,
      0L
    )
  ) |>
  arrange(country_code)

manual_arrangements_other <- manual_arrangements_in_input |>
  filter(!facility %in% EXCLUDED_RAPID_FACILITIES)

manual_outright_counts <- manual_arrangements_in_input |>
  filter(facility %in% EXCLUDED_RAPID_FACILITIES) |>
  count(facility) |>
  arrange(match(facility, EXCLUDED_RAPID_FACILITIES))

scheduled_expirations_after_panel <- arrangements_window |>
  filter(year(expiration_date) > year_max) |>
  select(
    imf_country,
    country_code,
    facility,
    date_of_arrangement,
    expiration_date
  ) |>
  arrange(country_code, date_of_arrangement, expiration_date)

run_summary <- tibble(
  item = c(
    "Input workbook",
    "Excel output",
    "World Bank country API",
    "Run time (UTC)",
    "IMF as-of date",
    "Arrangement approval cutoff date",
    "Earliest arrangement year",
    "Final year",
    "As-of year included",
    "Latest scheduled expiration year in source",
    "Years in panel",
    "World Bank non-aggregate economies",
    "Final country-year rows",
    "IMF members mapped",
    "Raw arrangement observations in analysis period",
    "Programme arrangement observations retained",
    "Countries with a retained programme arrangement",
    "Excluded facility observations (RCF, RFI, ENDA, EPCA, STF)",
    "RCF observations excluded",
    "RFI observations excluded",
    "ENDA observations excluded",
    "EPCA observations excluded",
    "STF observations excluded",
    "Countries represented only by excluded facilities",
    "Date anomalies among excluded facilities",
    "Invalid retained-programme intervals after cutoff excluded",
    "Retained programmes expiring after final panel year",
    "All-programme merged spells",
    "Concessional merged spells",
    "Non-concessional merged spells",
    "Robust-versus-literal overlap differences",
    "Legacy-versus-calendar diagnostic differences",
    "Panel universe rule",
    "Independent states in panel",
    "States added that are not on the World Bank list",
    "World Bank economies excluded (not independent states)",
    "Members added from Arrangements sheet",
    "Manual arrangement additions in input",
    "Official indicator method"
  ),
  value = c(
    INPUT_FILE,
    OUTPUT_FILE,
    WB_COUNTRY_API,
    format(Sys.time(), tz = "UTC", usetz = TRUE),
    as.character(imf_as_of_date),
    as.character(analysis_cutoff_date),
    as.character(year_min),
    as.character(year_max),
    as.character(year_max == year(imf_as_of_date)),
    as.character(max(year(arrangements_all$expiration_date), na.rm = TRUE)),
    as.character(length(years)),
    as.character(nrow(wb_economies)),
    as.character(nrow(country_year_panel)),
    as.character(nrow(member_crosswalk)),
    as.character(nrow(arrangements_window_all)),
    as.character(nrow(arrangements_window)),
    as.character(arrangement_country_summary),
    as.character(nrow(excluded_rapid_facilities)),
    as.character(sum(
      excluded_rapid_facilities$facility == "Rapid Credit Facility",
      na.rm = TRUE
    )),
    as.character(sum(
      excluded_rapid_facilities$facility == "Rapid Financing Instrument",
      na.rm = TRUE
    )),
    as.character(sum(
      excluded_rapid_facilities$facility == "Emergency Natural Disaster Assistance",
      na.rm = TRUE
    )),
    as.character(sum(
      excluded_rapid_facilities$facility == "Emergency Post-Conflict Assistance",
      na.rm = TRUE
    )),
    as.character(sum(
      excluded_rapid_facilities$facility == "Systemic Transformation Facility",
      na.rm = TRUE
    )),
    as.character(nrow(rapid_only_countries)),
    as.character(nrow(rapid_interval_anomalies)),
    as.character(nrow(invalid_intervals_after_cutoff)),
    as.character(nrow(scheduled_expirations_after_panel)),
    as.character(nrow(robust_spells$all)),
    as.character(nrow(robust_spells$concessional)),
    as.character(nrow(robust_spells$nonconcessional)),
    as.character(nrow(overlap_diagnostic)),
    as.character(nrow(calendar_diagnostic)),
    paste0(
      "Independent states only, for years in which the state existed on ",
      "31 December (see State_Existence sheet)"
    ),
    as.character(n_distinct(panel_universe$country_code)),
    paste(states_not_on_wb_list$country_code, collapse = ", "),
    paste(excluded_wb_economies$country_code, collapse = ", "),
    if (nrow(members_added_from_arrangements) == 0L) {
      "None"
    } else {
      paste0(
        members_added_from_arrangements$imf_country,
        " (", members_added_from_arrangements$member_key, ")",
        collapse = "; "
      )
    },
    if (nrow(manual_arrangements_in_input) == 0L) {
      "None"
    } else {
      paste0(
        nrow(manual_arrangements_in_input), ": ",
        paste(
          c(
            paste0(
              manual_arrangements_other$country, " ",
              manual_arrangements_other$facility, " approved ",
              as.Date(manual_arrangements_other$date_of_arrangement)
            ),
            paste0(
              manual_outright_counts$n, " ",
              manual_outright_counts$facility, " outright purchases"
            )
          ),
          collapse = "; "
        )
      )
    },
    paste0(
      if (MONTH_METHOD == "calendar") {
        "Calendar months in force (each month with at least one day under a programme counted once)"
      } else {
        "Legacy Stata month arithmetic"
      },
      " after robust connected-spell merging; ",
      "RCF, RFI, ENDA, EPCA and STF observations excluded before all ",
      "indicator calculations"
    )
  )
)

# ---- Prepare Excel sheets ----------------------------------------------------

calendar_excel <- if (nrow(calendar_diagnostic) == 0L) {
  tibble(note = "No legacy-versus-calendar differences were found.")
} else {
  calendar_diagnostic
}

overlap_excel <- if (nrow(overlap_diagnostic) == 0L) {
  tibble(note = "Robust spell merging and literal Stata cleaning agree.")
} else {
  overlap_diagnostic
}

rapid_exclusions_excel <- if (nrow(excluded_rapid_facilities) == 0L) {
  tibble(note = "No excluded-facility observations occurred in the analysis period.")
} else {
  excluded_rapid_facilities
}

rapid_only_countries_excel <- if (nrow(rapid_only_countries) == 0L) {
  tibble(note = "No country appeared only in excluded-facility observations.")
} else {
  rapid_only_countries
}

future_expirations_excel <- if (nrow(scheduled_expirations_after_panel) == 0L) {
  tibble(note = "No arrangements expire after the final panel year.")
} else {
  scheduled_expirations_after_panel
}

# ---- Save the single output workbook ----------------------------------------

write.xlsx(
  x = list(
    Country_Year = country_year_panel,
    Summary = run_summary,
    Country_Crosswalk = member_crosswalk_export,
    WB_Economies = wb_economies,
    State_Existence = STATE_EXISTENCE |>
      left_join(panel_names, by = "country_code", suffix = c("", "_panel")) |>
      mutate(
        panel_first_year = pmax(first_year, year_min),
        panel_last_year = pmin(coalesce(last_year, year_max), year_max)
      ),
    Excluded_Economies = excluded_wb_economies,
    Facility_Counts = facility_counts,
    Facility_Classification = facility_classification,
    Excluded_Rapid_Facilities = rapid_exclusions_excel,
    Rapid_Only_Countries = rapid_only_countries_excel,
    Future_Expirations = future_expirations_excel,
    Calendar_Diagnostic = calendar_excel,
    Overlap_Diagnostic = overlap_excel
  ),
  file = OUTPUT_FILE,
  overwrite = TRUE
)

# ---- Console summary ---------------------------------------------------------

message("Completed successfully.")
message("Independent states in panel: ", n_distinct(panel_universe$country_code))
message("IMF as-of date: ", imf_as_of_date)
message("Years: ", year_min, "-", year_max)
message(
  "Excluded facility observations (RCF, RFI, ENDA, EPCA, STF): ",
  nrow(excluded_rapid_facilities)
)
message("Country-year rows: ", nrow(country_year_panel))
message("Excel output: ", normalizePath(OUTPUT_FILE, winslash = "/", mustWork = FALSE))
