# ==============================================================================
# IMF Financial Arrangements: all-member reproducible scraper
#
# Source landing page:
#   https://www.imf.org/external/np/fin/tad/extarr1.aspx
#
# Output:
#   IMFMonitor_Programs_Raw.xlsx
#
# The script discovers the current member keys, date choices, form action, and
# exact parameter names from the live landing page. It selects the maximum date
# actually offered by the IMF, then queries every numeric member option one at a
# time. Monetary values are parsed as numbers but are NOT converted: a source
# value of 1,000,000 remains 1,000,000 and is labelled "Thousands of SDRs".
#
# In addition to the dropdown members, former and withdrawn members whose
# records the IMF still serves under retired member keys are queried
# (FORMER_MEMBERS). Arrangements that the IMF approved but no longer lists at
# the latest as-of date are appended from MANUAL_ARRANGEMENTS, and outright
# purchases that the lending page never lists (Emergency Natural Disaster
# Assistance, Emergency Post-Conflict Assistance and Systemic Transformation
# Facility) from MANUAL_OUTRIGHT_PURCHASES. Both are labelled in the source and
# source_note columns. "of which Supplemental Reserve Facility" rows, which are
# components of a parent arrangement, are dropped. Footnote markup is removed
# from facility names.
# ==============================================================================

# ---- 1. Packages -------------------------------------------------------------

REQUIRED_PACKAGES <- c(
  "httr2",
  "rvest",
  "xml2",
  "readr",
  "dplyr",
  "stringr",
  "tibble",
  "openxlsx"
)

missing_packages <- setdiff(REQUIRED_PACKAGES, rownames(installed.packages()))

if (length(missing_packages) > 0L) {
  # On Windows, explicitly request CRAN binaries. Without this, an older R
  # release can mix older binary dependencies with a newer source package. For
  # example, R 4.3 may install binary rlang 1.1.5 and then try to install source
  # httr2 1.3.0, which requires rlang >= 1.3.0 and therefore fails without the
  # matching compilation toolchain.
  package_type <- if (identical(.Platform$OS.type, "windows")) {
    "binary"
  } else {
    getOption("pkgType")
  }
  
  message(
    "Installing missing CRAN packages: ",
    paste(missing_packages, collapse = ", ")
  )
  if (identical(.Platform$OS.type, "windows")) {
    message("Using CRAN Windows binaries (Rtools is not required).")
  }
  
  install.packages(
    missing_packages,
    repos = "https://cloud.r-project.org",
    type = package_type
  )
}

still_missing <- setdiff(REQUIRED_PACKAGES, rownames(installed.packages()))
if (length(still_missing) > 0L) {
  stop(
    paste0(
      "The following required package(s) could not be installed: ",
      paste(still_missing, collapse = ", "),
      ". On Windows, update R if CRAN no longer provides compatible binaries ",
      "for your R version."
    ),
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(httr2)
  library(rvest)
  library(xml2)
  library(readr)
  library(dplyr)
  library(stringr)
  library(tibble)
  library(openxlsx)
})

# ---- 2. User-adjustable settings --------------------------------------------

LANDING_URL <- "https://www.imf.org/external/np/fin/tad/extarr1.aspx"
OUTPUT_FILE <- "IMFMonitor_Programs_Raw.xlsx"

# Requests are deliberately sequential. Increase the pause if the IMF server
# begins returning HTTP 429 or 5xx responses.
REQUEST_PAUSE_SECONDS <- 0.60
REQUEST_TIMEOUT_SECONDS <- 60
MAX_ATTEMPTS <- 4L
RETRY_BASE_DELAY_SECONDS <- 1.5

# A safety check against silently scraping a truncated dropdown. The live page
# contained 191 numeric member options when this script was prepared.
MIN_EXPECTED_MEMBER_COUNT <- 180L

# Arrangements that the IMF lending page no longer lists at the latest as-of
# date but that the IMF approved. Each is appended to the Arrangements sheet
# with source = "Manual addition" and the evidence in source_note. Values are
# taken from the IMF lending page at an earlier as-of date and are in thousands
# of SDRs, like the scraped rows. A manual row is skipped automatically if the
# IMF lists the arrangement again (same member key, facility and approval date).
MANUAL_ARRANGEMENTS <- tribble(
  ~member_key, ~facility,                  ~date_of_arrangement, ~expiration_date, ~amount_agreed, ~amount_drawn, ~amount_outstanding, ~source_note,
  "65",        "Extended Credit Facility", "2010-06-14",         "2014-06-03",     74280,          74280,         NA_real_,            paste0(
    "Benin ECF approved 14 Jun 2010 (IMF Press Release 10/243). Listed on the ",
    "IMF lending page up to the 2022-12-31 as-of date (agreed and drawn ",
    "SDR 74,280 thousand; expiration Jun 03, 2014) but omitted from later ",
    "as-of dates. Amount outstanding at the current as-of date is not ",
    "reported and is left blank."
  )
)

# Outright purchases that the IMF lending page never lists, because they are
# not arrangements: Emergency Natural Disaster Assistance (ENDA, 1962-2011),
# Emergency Post-Conflict Assistance (EPCA, 1995-2011) and the Systemic
# Transformation Facility (STF, 1993-95). Each is appended to the Arrangements
# sheet as a manual addition. The panel builder excludes these facilities from
# all programme indicators, as it does RCF and RFI disbursements.
#
# Each row is one purchase. The expiration date is set to the approval date,
# and the amounts agreed and drawn are the amount purchased, in thousands of
# SDRs. The amount outstanding is not tracked and is left blank. Where only the
# year of an early ENDA is known (seven cases), the approval date is a
# placeholder within that year, explained in the evidence column. Sources are
# cited in the evidence column: the hand-coded IMFMonitor_Programs dataset
# ("IMFMonitor_Programs"), IMF press releases (PR/), Executive Board documents
# (EBM/, EBS/, DEC/), IMF (2005) "Subsidization of the Fund's Emergency
# Assistance for Natural Disasters to PRGF-Eligible Members", Table 1
# (https://www.imf.org/external/np/pp/eng/2005/011005.pdf), and the IMF's
# official history for 1990-99 (Boughton, "Tearing Down Walls", 2012), Table 5.1
# (https://www.imf.org/external/pubs/ft/history/2012/pdf/c5.pdf).
OUTRIGHT_PURCHASE_FACILITIES <- c(
  ENDA = "Emergency Natural Disaster Assistance",
  EPCA = "Emergency Post-Conflict Assistance",
  STF  = "Systemic Transformation Facility"
)

MANUAL_OUTRIGHT_PURCHASES <- tribble(
  ~member_key, ~type,  ~date_of_arrangement, ~amount_sdr_thousands, ~evidence,
  # Emergency Natural Disaster Assistance (1962-2011). Years and amounts for
  # 1962-2004 agree with IMF (2005), Table 1.
  "275",       "ENDA", "1962-07-01",         22400,                 "Egypt (then United Arab Republic), crop failure. IMF (2005) Table 1: 1962, SDR 22.4m (rounded). Approval date not found; 1 Jul placeholder.",
  "1070",      "ENDA", "1963-08-01",         30000,                 "SFR Yugoslavia, Skopje earthquake of 26 Jul 1963. IMF (2005) Table 1: 1963, SDR 30.0m. Approval date not found; placeholder is the first day of the month after the earthquake.",
  "430",       "ENDA", "1966-03-16",         187500,                "Drought. IMF (2005) Table 1: 1966, SDR 187.5m. Date is a likely Board date, not confirmed: IMF Archives 'India - Purchase Transaction', 16 Mar 1966.",
  "720",       "ENDA", "1973-07-01",         12000,                 "Managua earthquake of 23 Dec 1972. IMF (2005) Table 1: 1973, SDR 12.0m (44% of quota). Approval date not found; 1 Jul placeholder.",
  "160",       "ENDA", "1974-07-01",         2800,                  "Drought. IMF (2005) Table 1: 1974, SDR 2.8m (rounded). Approval date not found; 1 Jul placeholder.",
  "255",       "ENDA", "1979-09-01",         1000,                  "Hurricane David (29 Aug 1979). IMF (2005) Table 1: 1979, SDR 1.0m. Approval date not found; placeholder is the first day of the month after the hurricane.",
  "260",       "ENDA", "1979-09-01",         23300,                 "Hurricanes David and Frederic (Aug-Sep 1979). IMF (2005) Table 1: 1979, SDR 23.3m (rounded). Approval date not found; placeholder is the first day of the month after Hurricane David.",
  "822",       "ENDA", "1980-09-01",         1800,                  "Hurricane Allen (4 Aug 1980). IMF (2005) Table 1: 1980, SDR 1.8m (rounded). Approval date not found; placeholder is the first day of the month after the hurricane.",
  "824",       "ENDA", "1980-11-14",         400,                   "Hurricane Allen. IMF (2005) Table 1: 1980, SDR 0.4m. Date is a likely Board date, not confirmed: IMF Archives EBS/80/240 Sup. 1, first-credit-tranche purchase, 14 Nov 1980.",
  "1068",      "ENDA", "1982-06-30",         15400,                 "Floods (Mar 1982). IMF (2005) Table 1: 1982, SDR 15.4m (rounded). Date is a likely Board date, not confirmed: IMF Archives EBS/82/104 Sup. 1, credit-tranche purchase, 30 Jun 1982.",
  "1066",      "ENDA", "1983-02-28",         9800,                  "Earthquake (Dec 1982). IMF (2005) Table 1: 1983, SDR 9.8m (rounded). Board approval 28 Feb 1983 (EBM/83/40, DEC/7348).",
  "670",       "ENDA", "1986-01-10",         291375,                "Earthquake. IMFMonitor_Programs; EBM/86/5.",
  "620",       "ENDA", "1986-05-28",         16600,                 "Cyclone. IMFMonitor_Programs; EBM/86/90.",
  "865",       "ENDA", "1986-09-19",         1250,                  "Cyclone. IMFMonitor_Programs; EBM/86/159.",
  "270",       "ENDA", "1987-06-29",         37700,                 "Earthquake. IMFMonitor_Programs; EBM/87/94.",
  "55",        "ENDA", "1988-11-14",         71900,                 "Floods. IMF (2005) Table 1: 1988, SDR 71.9m (rounded). Board approval 14 Nov 1988 (IMF Archives).",
  "510",       "ENDA", "1989-02-17",         36375,                 "Hurricane. IMFMonitor_Programs; EBM/89/19.",
  "760",       "ENDA", "1992-11-25",         189550,                "Floods. IMFMonitor_Programs; PR/92/83.",
  "55",        "ENDA", "1998-10-28",         98125,                 "Floods. IMFMonitor_Programs; PR/98/52.",
  "260",       "ENDA", "1998-10-29",         39700,                 "Hurricane. IMFMonitor_Programs; PR/98/53.",
  "400",       "ENDA", "1998-11-30",         15175,                 "Hurricane. IMFMonitor_Programs; PR/98/58.",
  "410",       "ENDA", "1998-12-07",         47500,                 "Hurricane. IMFMonitor_Programs; PR/98/60.",
  "821",       "ENDA", "1998-12-17",         1625,                  "Hurricane. IMFMonitor_Programs; PR/98/62.",
  "980",       "ENDA", "1999-10-13",         361500,                "Earthquake. IMFMonitor_Programs; PR/99/49.",
  "630",       "ENDA", "2002-08-30",         17350,                 "Food shortage. IMFMonitor_Programs; PR/02/38. The press release is dated 3 Sep 2002 and gives no Board date.",
  "361",       "ENDA", "2003-01-27",         2930,                  "Tropical storm Lili. PR/03/10. IMFMonitor_Programs has the same date but cites EBM/04/4.",
  "361",       "ENDA", "2004-11-15",         2925,                  "Hurricane Ivan. IMFMonitor_Programs; EBM/04/106.",
  "645",       "ENDA", "2005-03-04",         4100,                  "Tsunami. IMFMonitor_Programs; EBM/05/21.",
  "895",       "ENDA", "2005-03-04",         103350,                "Tsunami. IMFMonitor_Programs; EBM/05/21.",
  "255",       "ENDA", "2008-02-04",         2050,                  "Hurricane Dean. IMFMonitor_Programs; EBM/08/11.",
  "55",        "ENDA", "2008-04-02",         133325,                "Cyclone Sidr. IMFMonitor_Programs; EBM/08/30; PR/08/70.",
  "62",        "ENDA", "2009-02-18",         4700,                  "Floods. IMFMonitor_Programs; EBM/09/17; PR/09/41.",
  "821",       "ENDA", "2009-05-15",         2225,                  "Hurricane Omar. IMFMonitor_Programs; PR/09/167.",
  "760",       "ENDA", "2010-09-15",         296980,                "Floods. IMFMonitor_Programs; PR/10/344.",
  "822",       "ENDA", "2011-01-12",         1530,                  "Hurricane Tomas. IMFMonitor_Programs; PR/11/6. ENDA part only; the SDR 3.83m RCF approved the same day is on the IMF lending page.",
  # Emergency Post-Conflict Assistance (1995-2011).
  "75",        "EPCA", "1995-12-20",         30300,                 "IMFMonitor_Programs; PR/95/70.",
  "820",       "EPCA", "1997-04-22",         8925,                  "IMFMonitor_Programs; PR/97/19.",
  "15",        "EPCA", "1997-11-07",         8825,                  "IMFMonitor_Programs; PR/97/51.",
  "820",       "EPCA", "1997-12-12",         5950,                  "IMFMonitor_Programs; PR/97/57.",
  "925",       "EPCA", "1997-12-19",         7500,                  "IMFMonitor_Programs; PR/97/61.",
  "925",       "EPCA", "1998-04-01",         7500,                  "IMFMonitor_Programs; PR/98/10.",
  "200",       "EPCA", "1998-07-15",         7240,                  "IMFMonitor_Programs; PR/98/30.",
  "850",       "EPCA", "1998-11-09",         11580,                 "IMFMonitor_Programs; PR/98/55.",
  "383",       "EPCA", "1999-09-14",         2130,                  "IMFMonitor_Programs; PR/99/43.",
  "850",       "EPCA", "1999-12-17",         15560,                 "IMFMonitor_Programs; PR/99/62.",
  "383",       "EPCA", "2000-01-07",         1420,                  "IMFMonitor_Programs; PR/00/2.",
  "850",       "EPCA", "2000-09-13",         10400,                 "IMFMonitor_Programs; EBM/00/94. IMF (2008) fragile-states paper, App. Table 3, gives 8 Sep 2000.",
  "200",       "EPCA", "2000-11-17",         10575,                 "IMFMonitor_Programs; PR/00/62.",
  "1072",      "EPCA", "2000-12-20",         116925,                "FR Yugoslavia, recorded under Serbia (key 1072). IMFMonitor_Programs; EBM/00/128.",
  "110",       "EPCA", "2002-10-09",         9625,                  "IMFMonitor_Programs; PR/02/48.",
  "110",       "EPCA", "2003-05-05",         9625,                  "IMFMonitor_Programs; EBM/03/42.",
  "140",       "EPCA", "2004-07-23",         5570,                  "IMFMonitor_Programs; EBM/04/72.",
  "460",       "EPCA", "2004-09-29",         297100,                "IMFMonitor_Programs; PR/04/206.",
  "400",       "EPCA", "2005-01-10",         10230,                 "PR/05/04; IMF (2008) fragile-states paper, App. Table 3.",
  "400",       "EPCA", "2005-10-19",         10230,                 "PR/05/234; IMF (2008) fragile-states paper, App. Table 3.",
  "140",       "EPCA", "2006-01-27",         6962.5,                "IMFMonitor_Programs; EBM/06/7.",
  "580",       "EPCA", "2007-04-09",         50750,                 "Board approval 9 Apr 2007 (IMF Archives); PR/07/86 is dated 4 May 2007; IMF Annual Report 2007.",
  "225",       "EPCA", "2007-08-03",         40600,                 "IMFMonitor_Programs; PR/07/176.",
  "383",       "EPCA", "2008-01-28",         1775,                  "PR/08/11; Board date restated in PR/09/224.",
  "225",       "EPCA", "2008-04-04",         40600,                 "IMFMonitor_Programs; PR/08/73.",
  "383",       "EPCA", "2008-07-28",         1775,                  "PR/08/183; Board date restated in PR/09/224.",
  "580",       "EPCA", "2008-11-14",         25375,                 "IMFMonitor_Programs; EBM/08/99.",
  "195",       "EPCA", "2008-12-15",         1125,                  "IMFMonitor_Programs; PR/08/327.",
  "383",       "EPCA", "2009-06-19",         1775,                  "PR/09/224 (third EPCA purchase); date is the press release date, which gives no separate Board date. IMF Country Report 09/236.",
  # Systemic Transformation Facility (1993-95): 20 first and 17 second
  # purchases, SDR 3,984 million in total (IMF Annual Report 1996: SDR 4.0
  # billion to 20 countries, 17 of which drew twice).
  "565",       "STF",  "1993-05-12",         16125,                 "First purchase. IMFMonitor_Programs; PR/93/21; IMF History 1990-99 Table 5.1.",
  "819",       "STF",  "1993-06-30",         1078275,               "First purchase. IMFMonitor_Programs; PR/93/25; IMF History 1990-99 Table 5.1.",
  "535",       "STF",  "1993-07-23",         61875,                 "First purchase. IMFMonitor_Programs; PR/93/29; IMF History 1990-99 Table 5.1.",
  "862",       "STF",  "1993-07-26",         64350,                 "First purchase. Board approval 26 Jul 1993 (EBM/93/104, DEC/10430); IMFMonitor_Programs uses the PR/93/30 date of 27 Jul 1993. IMF History 1990-99 Table 5.1.",
  "58",        "STF",  "1993-07-28",         70100,                 "First purchase. IMFMonitor_Programs; PR/93/31; IMF History 1990-99 Table 5.1.",
  "672",       "STF",  "1993-09-16",         22500,                 "First purchase. IMFMonitor_Programs; PR/93/39; IMF History 1990-99 Table 5.1.",
  "565",       "STF",  "1993-09-20",         16125,                 "Second purchase. IMFMonitor_Programs; PR/93/41; EBM/93/138; IMF History 1990-99 Table 5.1.",
  "115",       "STF",  "1993-10-04",         6250,                  "First and only purchase. IMFMonitor_Programs; PR/93/44; IMF History 1990-99 Table 5.1.",
  "1060",      "STF",  "1993-10-06",         12080,                 "First purchase (5% of quota). IMFMonitor_Programs; PR/93/45; IMF History 1990-99 Table 5.1.",
  "607",       "STF",  "1993-10-22",         25875,                 "First purchase. IMFMonitor_Programs; PR/93/47; EBM/93/146; IMF History 1990-99 Table 5.1.",
  "287",       "STF",  "1993-10-27",         11625,                 "First purchase. IMFMonitor_Programs; PR/93/48; IMF History 1990-99 Table 5.1.",
  "575",       "STF",  "1993-12-15",         22875,                 "First purchase. IMFMonitor_Programs; PR/93/50; DEC/10537; IMF History 1990-99 Table 5.1.",
  "672",       "STF",  "1993-12-17",         22500,                 "Second purchase. IMFMonitor_Programs; PR/93/51; EBM/93/173; IMF History 1990-99 Table 5.1.",
  "535",       "STF",  "1994-01-26",         61875,                 "Second purchase. IMFMonitor_Programs; PR/94/2; IMF History 1990-99 Table 5.1.",
  "618",       "STF",  "1994-02-11",         12400,                 "First purchase. IMFMonitor_Programs; PR/94/4; IMF History 1990-99 Table 5.1.",
  "607",       "STF",  "1994-04-08",         25875,                 "Second purchase. IMFMonitor_Programs; PR/94/25; IMF History 1990-99 Table 5.1.",
  "93",        "STF",  "1994-04-11",         116220,                "First and only purchase. IMFMonitor_Programs (cites PR/94/61, which looks like a wrong number); IMF History 1990-99 Table 5.1.",
  "819",       "STF",  "1994-04-20",         1078275,               "Second purchase. IMFMonitor_Programs; EBM/94/37; IMF History 1990-99 Table 5.1.",
  "818",       "STF",  "1994-05-11",         188525,                "First and only purchase. IMFMonitor_Programs; PR/94/34; IMF History 1990-99 Table 5.1.",
  "1060",      "STF",  "1994-06-08",         12080,                 "Second purchase (5% of quota). IMFMonitor_Programs; PR/94/41; EBS/94/105; IMF History 1990-99 Table 5.1.",
  "575",       "STF",  "1994-07-15",         22875,                 "Second purchase. IMFMonitor_Programs; PR/94/52; IMF History 1990-99 Table 5.1.",
  "862",       "STF",  "1994-07-22",         64350,                 "Second purchase. IMFMonitor_Programs; PR/94/55; IMF History 1990-99 Table 5.1.",
  "227",       "STF",  "1994-10-14",         65400,                 "First purchase. IMFMonitor_Programs; PR/94/72; IMF History 1990-99 Table 5.1.",
  "993",       "STF",  "1994-10-26",         249325,                "First purchase. IMFMonitor_Programs; PR/94/76; IMF History 1990-99 Table 5.1.",
  "35",        "STF",  "1994-12-14",         16875,                 "First purchase. IMFMonitor_Programs; PR/94/86; IMF History 1990-99 Table 5.1.",
  "335",       "STF",  "1994-12-15",         27750,                 "First purchase. IMFMonitor_Programs; PR/94/88; IMF History 1990-99 Table 5.1.",
  "287",       "STF",  "1995-01-09",         11625,                 "Second purchase. IMFMonitor_Programs; PR/95/1; IMF History 1990-99 Table 5.1.",
  "1042",      "STF",  "1995-01-25",         49875,                 "First purchase. IMFMonitor_Programs; PR/95/7; IMF History 1990-99 Table 5.1.",
  "58",        "STF",  "1995-01-30",         70100,                 "Second purchase. IMFMonitor_Programs; PR/95/9; IMF History 1990-99 Table 5.1.",
  "993",       "STF",  "1995-04-07",         249325,                "Second purchase. IMFMonitor_Programs; PR/95/19; IMF History 1990-99 Table 5.1.",
  "227",       "STF",  "1995-04-10",         65400,                 "Second purchase. IMFMonitor_Programs; PR/95/20; IMF History 1990-99 Table 5.1.",
  "51",        "STF",  "1995-04-19",         29250,                 "First purchase. IMFMonitor_Programs; PR/95/24; IMF History 1990-99 Table 5.1.",
  "618",       "STF",  "1995-05-05",         12400,                 "Second purchase. IMFMonitor_Programs; PR/95/28; IMF Annual Report 1996.",
  "35",        "STF",  "1995-06-28",         16875,                 "Second purchase. IMFMonitor_Programs; PR/95/36; IMF Annual Report 1996.",
  "335",       "STF",  "1995-06-28",         27750,                 "Second purchase. IMFMonitor_Programs; PR/95/37; IMF Annual Report 1996.",
  "51",        "STF",  "1995-11-17",         29250,                 "Second purchase. IMFMonitor_Programs; EBM/95/109; IMF Annual Report 1996.",
  "1042",      "STF",  "1995-12-18",         49875,                 "Second purchase. IMFMonitor_Programs; PR/95/67; IMF Annual Report 1996."
)

if (!all(MANUAL_OUTRIGHT_PURCHASES$type %in% names(OUTRIGHT_PURCHASE_FACILITIES))) {
  stop(
    "MANUAL_OUTRIGHT_PURCHASES contains an unknown type: ",
    paste(
      setdiff(MANUAL_OUTRIGHT_PURCHASES$type, names(OUTRIGHT_PURCHASE_FACILITIES)),
      collapse = ", "
    ),
    call. = FALSE
  )
}

MANUAL_ARRANGEMENTS <- bind_rows(
  MANUAL_ARRANGEMENTS,
  MANUAL_OUTRIGHT_PURCHASES |>
    transmute(
      member_key,
      facility = unname(OUTRIGHT_PURCHASE_FACILITIES[type]),
      date_of_arrangement,
      expiration_date = date_of_arrangement,
      amount_agreed = amount_sdr_thousands,
      amount_drawn = amount_sdr_thousands,
      amount_outstanding = NA_real_,
      source_note = paste0(
        "Outright purchase (", type, "), not listed on the IMF lending page. ",
        "Expiration date set to the approval date. ",
        evidence
      )
    )
)

USER_AGENT <- paste0(
  "IMF-Financial-Arrangements-Research-Scraper/1.0 ",
  "(R; sequential academic-research requests; source: ", LANDING_URL, ")"
)

RUN_STARTED_UTC <- format(
  Sys.time(),
  format = "%Y-%m-%dT%H:%M:%SZ",
  tz = "UTC"
)

# ---- 3. Empty-table templates ------------------------------------------------

empty_source_data <- function() {
  tibble(
    facility = character(),
    date_of_arrangement = as.Date(character()),
    expiration_date = as.Date(character()),
    amount_agreed = double(),
    amount_drawn = double(),
    amount_outstanding = double(),
    amount_unit = character()
  )
}

empty_arrangements <- function() {
  tibble(
    country = character(),
    member_key = character(),
    as_of_date = as.Date(character()),
    facility = character(),
    date_of_arrangement = as.Date(character()),
    expiration_date = as.Date(character()),
    amount_agreed = double(),
    amount_drawn = double(),
    amount_outstanding = double(),
    amount_unit = character()
  )
}

empty_error_log <- function() {
  tibble(
    stage = character(),
    country = character(),
    member_key = character(),
    url_queried = character(),
    error_status = character(),
    http_status = integer(),
    attempts = integer(),
    content_type = character()
  )
}

# ---- 4. HTTP helpers: timeout, retry, and throttling -------------------------

retry_delay <- function(attempt, retry_after_header = NULL) {
  retry_after_numeric <- suppressWarnings(as.numeric(retry_after_header))
  
  if (
    length(retry_after_numeric) == 1L &&
    !is.na(retry_after_numeric) &&
    retry_after_numeric >= 0
  ) {
    return(min(retry_after_numeric, 60))
  }
  
  min(
    30,
    RETRY_BASE_DELAY_SECONDS * 2^(attempt - 1L) + stats::runif(1L, 0, 0.5)
  )
}

fetch_with_retry <- function(url, max_attempts = MAX_ATTEMPTS) {
  last_status <- NA_integer_
  last_error <- "Unknown request error"
  last_content_type <- NA_character_
  
  for (attempt in seq_len(max_attempts)) {
    req <- request(url) |>
      req_user_agent(USER_AGENT) |>
      req_headers(
        Accept = paste0(
          "text/tab-separated-values, text/plain, ",
          "text/html;q=0.9, */*;q=0.8"
        )
      ) |>
      req_timeout(REQUEST_TIMEOUT_SECONDS) |>
      # Return non-2xx responses for explicit status handling below.
      req_error(is_error = function(resp) FALSE)
    
    response_or_error <- tryCatch(
      req_perform(req),
      error = function(e) e
    )
    
    if (inherits(response_or_error, "error")) {
      last_error <- conditionMessage(response_or_error)
      should_retry <- TRUE
      retry_after <- NULL
    } else {
      resp <- response_or_error
      last_status <- as.integer(resp_status(resp))
      last_content_type <- resp_header(resp, "content-type")
      if (is.null(last_content_type) || length(last_content_type) == 0L) {
        last_content_type <- NA_character_
      }
      
      if (last_status == 200L) {
        body_or_error <- tryCatch(
          resp_body_string(resp),
          error = function(e) e
        )
        
        if (!inherits(body_or_error, "error") && nzchar(body_or_error)) {
          return(list(
            ok = TRUE,
            body = body_or_error,
            status = last_status,
            attempts = attempt,
            content_type = last_content_type,
            error = NA_character_
          ))
        }
        
        if (inherits(body_or_error, "error")) {
          last_error <- paste(
            "HTTP 200 but the response body could not be read:",
            conditionMessage(body_or_error)
          )
        } else {
          last_error <- "HTTP 200 with an empty response body"
        }
        
        should_retry <- TRUE
      } else {
        last_error <- sprintf("HTTP %d", last_status)
        should_retry <- (
          last_status %in% c(408L, 425L, 429L) ||
            (last_status >= 500L && last_status <= 599L)
        )
      }
      
      retry_after <- resp_header(resp, "retry-after")
    }
    
    if (!should_retry || attempt == max_attempts) {
      break
    }
    
    delay <- retry_delay(attempt, retry_after)
    message(
      sprintf(
        "  Attempt %d/%d failed (%s); retrying in %.1f seconds...",
        attempt,
        max_attempts,
        last_error,
        delay
      )
    )
    Sys.sleep(delay)
  }
  
  list(
    ok = FALSE,
    body = NA_character_,
    status = last_status,
    attempts = attempt,
    content_type = last_content_type,
    error = last_error
  )
}

encode_query_component <- function(x) {
  utils::URLencode(as.character(x), reserved = TRUE)
}

build_results_url <- function(
    results_base_url,
    member_parameter,
    date_parameter,
    member_key,
    as_of_date,
    tsv = TRUE
) {
  parameters <- list()
  parameters[[member_parameter]] <- member_key
  parameters[[date_parameter]] <- format(as_of_date, "%Y-%m-%d")
  
  if (isTRUE(tsv)) {
    parameters[["tsvflag"]] <- "Y"
  }
  
  query_string <- paste(
    paste0(
      vapply(names(parameters), encode_query_component, character(1L)),
      "=",
      vapply(parameters, encode_query_component, character(1L))
    ),
    collapse = "&"
  )
  
  separator <- if (str_detect(results_base_url, fixed("?"))) "&" else "?"
  paste0(results_base_url, separator, query_string)
}

# ---- 5. Parsing and validation helpers --------------------------------------

REQUIRED_IMF_COLUMNS <- c(
  "facility",
  "date_of_arrangement",
  "expiration_date",
  "amount_agreed",
  "amount_drawn",
  "amount_outstanding"
)

AMOUNT_COLUMNS <- c(
  "amount_agreed",
  "amount_drawn",
  "amount_outstanding"
)

DATE_COLUMNS <- c("date_of_arrangement", "expiration_date")

split_tab <- function(x) {
  str_split(x, fixed("\t"), simplify = FALSE)[[1L]]
}

pad_character <- function(x, required_length) {
  length(x) <- required_length
  x[is.na(x)] <- ""
  x
}

clean_imf_headers <- function(x) {
  x |>
    str_replace_all("\u00a0", " ") |>
    str_squish() |>
    # The source header currently says "Expiration Date 4/". The 4/ is a
    # footnote marker, not part of the field name.
    str_remove("\\s+\\d+/\\s*$") |>
    str_to_lower(locale = "en") |>
    str_replace_all("[^a-z0-9]+", "_") |>
    str_replace_all("^_+|_+$", "")
}

# Facility names sometimes carry IMF footnote markup, e.g.
# "Precautionary and Liquidity Line<sup>1/</sup>" in the TSV or a trailing
# "1/" in the HTML table. The footnote does not change the facility, so the
# markup and marker are removed to give one name per facility.
clean_facility_name <- function(x) {
  x |>
    str_remove_all(regex("<sup[^>]*>.*?</sup>", ignore_case = TRUE)) |>
    str_remove_all("<[^>]+>") |>
    str_remove("\\s*\\d+/\\s*$") |>
    str_squish()
}

canonicalize_unit <- function(x) {
  x <- str_squish(x)
  
  if (str_detect(x, regex("^thousands\\s+of\\s+SDRs$", ignore_case = TRUE))) {
    return("Thousands of SDRs")
  }
  
  x
}

parse_label_date <- function(x, context = "date") {
  x <- str_squish(x)
  formats <- c("%B %d, %Y", "%b %d, %Y", "%Y-%m-%d")
  
  for (date_format in formats) {
    candidate <- suppressWarnings(
      parse_date(
        x,
        format = date_format,
        locale = locale(date_names = "en")
      )
    )
    
    if (length(candidate) == 1L && !is.na(candidate)) {
      return(candidate)
    }
  }
  
  stop(sprintf("Could not parse %s: '%s'", context, x), call. = FALSE)
}

standardize_missing <- function(x) {
  x <- as.character(x)
  x <- str_replace_all(x, "\u00a0", " ")
  x <- str_squish(x)
  
  missing_tokens <- c("", "NA", "N/A", "N.A.", "...", "-", "–", "—")
  is_missing <- str_to_upper(x, locale = "en") %in% str_to_upper(
    missing_tokens,
    locale = "en"
  )
  x[is_missing] <- NA_character_
  x
}

parse_date_column <- function(x, column_name, context) {
  cleaned <- standardize_missing(x)
  parsed <- suppressWarnings(
    parse_date(
      cleaned,
      format = "%b %d, %Y",
      locale = locale(date_names = "en")
    )
  )
  
  # The live data use abbreviated month names (e.g. "May 09, 2025").
  # Accept full English month names as a controlled fallback in case the IMF
  # changes presentation without changing the underlying date meaning.
  needs_full_month_fallback <- !is.na(cleaned) & is.na(parsed)
  if (any(needs_full_month_fallback)) {
    parsed[needs_full_month_fallback] <- suppressWarnings(
      parse_date(
        cleaned[needs_full_month_fallback],
        format = "%B %d, %Y",
        locale = locale(date_names = "en")
      )
    )
  }
  
  bad <- !is.na(cleaned) & is.na(parsed)
  if (any(bad)) {
    examples <- paste(unique(cleaned[bad])[seq_len(min(3L, sum(bad)))], collapse = "; ")
    stop(
      sprintf(
        "%s: could not parse %s value(s): %s",
        context,
        column_name,
        examples
      ),
      call. = FALSE
    )
  }
  
  parsed
}

parse_amount_column <- function(x, column_name, context) {
  cleaned <- standardize_missing(x)
  
  # Validate the whole field before parse_number(). This prevents a malformed
  # value such as "1,000 text" from being silently parsed as 1000.
  valid_numeric_format <- is.na(cleaned) | str_detect(
    cleaned,
    "^[+-]?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\\.[0-9]+)?$"
  )
  if (any(!valid_numeric_format)) {
    examples <- paste(
      head(unique(cleaned[!valid_numeric_format]), 3L),
      collapse = "; "
    )
    stop(
      sprintf(
        "%s: unexpected numeric format in %s: %s",
        context,
        column_name,
        examples
      ),
      call. = FALSE
    )
  }
  
  parsed <- suppressWarnings(
    parse_number(
      cleaned,
      locale = locale(decimal_mark = ".", grouping_mark = ","),
      na = character()
    )
  )
  
  bad <- !is.na(cleaned) & is.na(parsed)
  if (any(bad)) {
    examples <- paste(unique(cleaned[bad])[seq_len(min(3L, sum(bad)))], collapse = "; ")
    stop(
      sprintf(
        "%s: could not parse %s value(s): %s",
        context,
        column_name,
        examples
      ),
      call. = FALSE
    )
  }
  
  parsed
}

parse_source_table <- function(source_table, amount_unit, context) {
  source_headers <- names(source_table)
  cleaned_headers <- clean_imf_headers(source_headers)
  
  if (anyDuplicated(cleaned_headers)) {
    stop(
      paste0(
        context,
        ": duplicate column names after cleaning: ",
        paste(cleaned_headers[duplicated(cleaned_headers)], collapse = ", ")
      ),
      call. = FALSE
    )
  }
  
  names(source_table) <- cleaned_headers
  missing_columns <- setdiff(REQUIRED_IMF_COLUMNS, names(source_table))
  
  if (length(missing_columns) > 0L) {
    stop(
      paste0(
        context,
        ": expected IMF columns were absent: ",
        paste(missing_columns, collapse = ", "),
        ". Returned headers were: ",
        paste(source_headers, collapse = " | ")
      ),
      call. = FALSE
    )
  }
  
  out <- source_table |>
    select(all_of(REQUIRED_IMF_COLUMNS)) |>
    mutate(across(everything(), as.character)) |>
    mutate(across(everything(), ~ str_squish(str_replace_all(.x, "\u00a0", " ")))) |>
    filter(if_any(everything(), ~ !is.na(.x) & .x != "")) |>
    # Defensive removal in addition to the explicit TSV slicing.
    filter(!str_detect(str_to_lower(facility), "^(facility|total)$")) |>
    mutate(facility = clean_facility_name(facility))

  out$date_of_arrangement <- parse_date_column(
    out$date_of_arrangement,
    "date_of_arrangement",
    context
  )
  out$expiration_date <- parse_date_column(
    out$expiration_date,
    "expiration_date",
    context
  )
  
  for (column_name in AMOUNT_COLUMNS) {
    out[[column_name]] <- parse_amount_column(
      out[[column_name]],
      column_name,
      context
    )
  }
  
  out <- out |>
    mutate(amount_unit = amount_unit)
  
  list(data = out, source_headers = source_headers)
}

validate_returned_date <- function(returned_date, requested_date, context) {
  if (!identical(as.Date(returned_date), as.Date(requested_date))) {
    stop(
      sprintf(
        "%s: response date %s did not match requested date %s",
        context,
        format(returned_date, "%Y-%m-%d"),
        format(requested_date, "%Y-%m-%d")
      ),
      call. = FALSE
    )
  }
}

parse_tsv_response <- function(body, requested_date, context) {
  normalized_text <- str_replace_all(body, "\r\n?", "\n")
  lines <- str_split(normalized_text, "\n", simplify = FALSE)[[1L]]
  lines[1L] <- str_remove(lines[1L], "^\ufeff")
  
  nonblank_indices <- which(str_trim(lines) != "")
  if (length(nonblank_indices) == 0L) {
    stop(paste0(context, ": TSV response was blank"), call. = FALSE)
  }
  
  title_line <- str_squish(lines[nonblank_indices[1L]])
  title_pattern <- regex(
    "^(.+?):\\s*History of Lending Commitments$",
    ignore_case = TRUE
  )
  title_match <- str_match(title_line, title_pattern)
  
  if (is.na(title_match[1L, 1L])) {
    stop(
      paste0(context, ": unexpected TSV title line: ", title_line),
      call. = FALSE
    )
  }
  response_country <- str_squish(title_match[1L, 2L])
  
  as_of_indices <- which(
    str_detect(lines, regex("^\\s*as of\\s+", ignore_case = TRUE))
  )
  if (length(as_of_indices) == 0L) {
    stop(paste0(context, ": no as-of date was found in TSV"), call. = FALSE)
  }
  as_of_text <- str_remove(
    str_squish(lines[as_of_indices[1L]]),
    regex("^as of\\s+", ignore_case = TRUE)
  )
  returned_date <- parse_label_date(as_of_text, paste0(context, " as-of date"))
  validate_returned_date(returned_date, requested_date, context)
  
  unit_matches <- str_match(
    lines,
    regex("^\\s*\\(In\\s+(.+?)\\)\\s*$", ignore_case = TRUE)
  )
  unit_values <- unit_matches[, 2L]
  unit_values <- unit_values[!is.na(unit_values)]
  if (length(unit_values) == 0L) {
    stop(paste0(context, ": monetary unit line was not found"), call. = FALSE)
  }
  amount_unit <- canonicalize_unit(unit_values[1L])
  
  header_indices <- which(
    str_detect(lines, regex("^\\s*Facility\\t", ignore_case = TRUE))
  )
  if (length(header_indices) == 0L) {
    stop(paste0(context, ": TSV header row was not found"), call. = FALSE)
  }
  header1_index <- header_indices[1L]
  header1 <- split_tab(lines[header1_index])
  number_of_columns <- length(header1)
  
  possible_header2 <- seq.int(
    header1_index + 1L,
    min(length(lines), header1_index + 3L)
  )
  header2_candidates <- possible_header2[
    str_count(lines[possible_header2], fixed("\t")) >= number_of_columns - 1L
  ]
  if (length(header2_candidates) == 0L) {
    stop(paste0(context, ": second TSV header row was not found"), call. = FALSE)
  }
  header2_index <- header2_candidates[1L]
  header2 <- pad_character(split_tab(lines[header2_index]), number_of_columns)
  header1 <- pad_character(header1, number_of_columns)
  
  source_headers <- str_squish(paste(header1, header2))
  
  search_indices <- seq.int(header2_index + 1L, length(lines))
  first_fields <- vapply(
    lines[search_indices],
    function(line) str_trim(split_tab(line)[1L]),
    character(1L)
  )
  total_candidates <- search_indices[str_to_lower(first_fields) == "total"]
  
  if (length(total_candidates) == 0L) {
    stop(paste0(context, ": TSV Total row was not found"), call. = FALSE)
  }
  total_index <- total_candidates[1L]
  
  if (total_index > header2_index + 1L) {
    data_lines <- lines[seq.int(header2_index + 1L, total_index - 1L)]
    data_lines <- data_lines[str_trim(data_lines) != ""]
  } else {
    data_lines <- character()
  }
  
  if (length(data_lines) == 0L) {
    source_table <- as_tibble(
      setNames(
        replicate(number_of_columns, character(), simplify = FALSE),
        source_headers
      ),
      .name_repair = "minimal"
    )
  } else {
    field_counts <- vapply(data_lines, function(x) length(split_tab(x)), integer(1L))
    if (any(field_counts != number_of_columns)) {
      bad_examples <- paste(
        head(data_lines[field_counts != number_of_columns], 3L),
        collapse = " || "
      )
      stop(
        paste0(
          context,
          ": unexpected TSV field count in data row(s): ",
          bad_examples
        ),
        call. = FALSE
      )
    }
    
    source_table <- read_tsv(
      I(paste(data_lines, collapse = "\n")),
      col_names = source_headers,
      col_types = cols(.default = col_character()),
      trim_ws = TRUE,
      na = character(),
      quote = "",
      progress = FALSE,
      show_col_types = FALSE,
      name_repair = "minimal"
    )
    
    parsing_problems <- problems(source_table)
    if (nrow(parsing_problems) > 0L) {
      stop(
        paste0(
          context,
          ": readr reported ",
          nrow(parsing_problems),
          " TSV parsing problem(s)"
        ),
        call. = FALSE
      )
    }
  }
  
  parsed <- parse_source_table(source_table, amount_unit, context)
  
  list(
    status = if (nrow(parsed$data) == 0L) "no_arrangements" else "arrangements",
    data = parsed$data,
    returned_as_of_date = returned_date,
    amount_unit = amount_unit,
    response_country = response_country,
    response_format = "TSV",
    source_headers = parsed$source_headers
  )
}

parse_html_response <- function(body, requested_date, context) {
  doc <- read_html(body)
  content_node <- html_element(doc, css = "div#content")
  page_text <- if (inherits(content_node, "xml_missing")) {
    html_text2(doc)
  } else {
    html_text2(content_node)
  }
  
  heading <- html_element(doc, css = "div.h1Smallest")
  if (inherits(heading, "xml_missing")) {
    stop(paste0(context, ": result heading was absent from HTML"), call. = FALSE)
  }
  
  date_node <- html_element(heading, css = "b")
  if (inherits(date_node, "xml_missing")) {
    stop(paste0(context, ": as-of date was absent from HTML"), call. = FALSE)
  }
  as_of_text <- html_text2(date_node) |>
    str_squish() |>
    str_remove(regex("^as of\\s+", ignore_case = TRUE))
  returned_date <- parse_label_date(as_of_text, paste0(context, " as-of date"))
  validate_returned_date(returned_date, requested_date, context)
  
  country_node <- html_element(heading, css = "a")
  response_country <- if (inherits(country_node, "xml_missing")) {
    NA_character_
  } else {
    str_squish(html_text2(country_node))
  }
  
  no_record <- str_detect(
    page_text,
    regex(
      "No record was found for the specified search criteria",
      ignore_case = TRUE
    )
  )
  
  if (no_record) {
    return(list(
      status = "no_arrangements",
      data = empty_source_data(),
      returned_as_of_date = returned_date,
      amount_unit = NA_character_,
      response_country = response_country,
      response_format = "HTML no-record page",
      source_headers = character()
    ))
  }
  
  unit_match <- str_match(
    page_text,
    regex("\\(In\\s+([^\\)]+)\\)", ignore_case = TRUE)
  )
  if (is.na(unit_match[1L, 2L])) {
    stop(paste0(context, ": monetary unit was absent from HTML"), call. = FALSE)
  }
  amount_unit <- canonicalize_unit(unit_match[1L, 2L])
  
  result_table_node <- html_element(doc, css = "table.moneyGreen")
  if (inherits(result_table_node, "xml_missing")) {
    stop(
      paste0(context, ": expected result table was absent from HTML"),
      call. = FALSE
    )
  }
  
  source_table <- html_table(
    result_table_node,
    header = TRUE,
    trim = TRUE,
    convert = FALSE
  )
  parsed <- parse_source_table(source_table, amount_unit, context)
  
  list(
    status = if (nrow(parsed$data) == 0L) "no_arrangements" else "arrangements",
    data = parsed$data,
    returned_as_of_date = returned_date,
    amount_unit = amount_unit,
    response_country = response_country,
    response_format = "HTML table fallback",
    source_headers = parsed$source_headers
  )
}

parse_member_response <- function(body, requested_date, context) {
  leading_text <- str_sub(str_trim(body), 1L, 500L)
  looks_like_html <- str_detect(
    leading_text,
    regex("<!DOCTYPE\\s+html|<html(?:\\s|>)", ignore_case = TRUE)
  )
  
  if (looks_like_html) {
    parse_html_response(body, requested_date, context)
  } else {
    parse_tsv_response(body, requested_date, context)
  }
}

make_error_row <- function(
    stage,
    country,
    member_key,
    url,
    error_status,
    http_status,
    attempts,
    content_type
) {
  if (is.null(content_type) || length(content_type) == 0L) {
    content_type <- NA_character_
  }
  
  tibble(
    stage = stage,
    country = country,
    member_key = as.character(member_key),
    url_queried = url,
    error_status = str_trunc(as.character(error_status), 3000L),
    http_status = as.integer(http_status),
    attempts = as.integer(attempts),
    content_type = as.character(content_type)
  )
}

# ---- 6. Read and inspect the live landing page ------------------------------

message("Reading IMF landing page...")
landing_response <- fetch_with_retry(LANDING_URL)

if (!landing_response$ok) {
  stop(
    paste0(
      "Could not retrieve the IMF landing page after ",
      landing_response$attempts,
      " attempt(s): ",
      landing_response$error
    ),
    call. = FALSE
  )
}

landing_doc <- read_html(landing_response$body)

uppercase <- "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
lowercase <- "abcdefghijklmnopqrstuvwxyz"

member_xpath <- paste0(
  "//select[translate(@name, '", uppercase, "', '", lowercase,
  "') = 'memberkey1']"
)
date_xpath <- paste0(
  "//select[translate(@name, '", uppercase, "', '", lowercase,
  "') = 'date1key']"
)

member_select <- html_element(landing_doc, xpath = member_xpath)
date_select <- html_element(landing_doc, xpath = date_xpath)

if (inherits(member_select, "xml_missing")) {
  stop("The Member dropdown was not found on the IMF landing page.", call. = FALSE)
}
if (inherits(date_select, "xml_missing")) {
  stop("The As of Date dropdown was not found on the IMF landing page.", call. = FALSE)
}

member_parameter <- html_attr(member_select, "name")
date_parameter <- html_attr(date_select, "name")

if (
  is.na(member_parameter) || member_parameter == "" ||
  is.na(date_parameter) || date_parameter == ""
) {
  stop("One or both IMF dropdowns had no query-parameter name.", call. = FALSE)
}

member_options <- html_elements(member_select, css = "option")
members <- tibble(
  country = html_text2(member_options) |> str_squish(),
  member_key = html_attr(member_options, "value") |> str_trim()
) |>
  # Excludes "Select Country" (ZZZ) and "All Members" (ZZZZ).
  filter(str_detect(member_key, "^[0-9]+$")) |>
  select(country, member_key)

if (nrow(members) < MIN_EXPECTED_MEMBER_COUNT) {
  stop(
    sprintf(
      paste0(
        "Only %d numeric member options were found; expected at least %d. ",
        "Stopping to avoid silently producing an incomplete dataset."
      ),
      nrow(members),
      MIN_EXPECTED_MEMBER_COUNT
    ),
    call. = FALSE
  )
}
if (anyDuplicated(members$member_key)) {
  stop("Duplicate IMF member keys were found on the landing page.", call. = FALSE)
}
if (any(members$country == "" | is.na(members$country))) {
  stop("At least one numeric member option had a blank country name.", call. = FALSE)
}

FORMER_MEMBERS <- tibble(
  country = c(
    "Cuba",
    "Czechoslovakia",
    "Yemen Arab Republic",
    "Yemen, People's Democratic Republic of",
    "Yugoslavia, Federal Republic of"
  ),
  member_key = c("229", "240", "1066", "1068", "1070")
)

members <- bind_rows(
  members,
  anti_join(FORMER_MEMBERS, members, by = "member_key")
)

date_options <- html_elements(date_select, css = "option")
date_values <- html_attr(date_options, "value") |> str_trim()
date_values <- date_values[str_detect(date_values, "^\\d{4}-\\d{2}-\\d{2}$")]
available_dates <- suppressWarnings(as.Date(date_values, format = "%Y-%m-%d"))
available_dates <- available_dates[!is.na(available_dates)]

if (length(available_dates) == 0L) {
  stop("No valid dates were found in the IMF As of Date dropdown.", call. = FALSE)
}

latest_as_of_date <- max(available_dates)

form_xpath <- paste0(
  "//form[.//select[translate(@name, '", uppercase, "', '", lowercase,
  "') = 'memberkey1']][1]"
)
results_form <- html_element(landing_doc, xpath = form_xpath)

if (inherits(results_form, "xml_missing")) {
  stop("The form containing the Member dropdown was not found.", call. = FALSE)
}

form_action <- html_attr(results_form, "action")
form_method <- html_attr(results_form, "method")

if (is.na(form_action) || str_trim(form_action) == "") {
  stop("The IMF results form had no action URL.", call. = FALSE)
}
if (is.na(form_method) || str_trim(form_method) == "") {
  form_method <- "get"
}
if (str_to_lower(form_method) != "get") {
  stop(
    paste0("The IMF form no longer uses GET (method was ", form_method, ")."),
    call. = FALSE
  )
}

results_base_url <- url_absolute(form_action, LANDING_URL)

message(strrep("=", 72L))
message("Latest IMF As of Date selected: ", format(latest_as_of_date, "%Y-%m-%d"))
message("Numeric IMF member options found: ", nrow(members))
message("Form action discovered: ", results_base_url)
message(
  "Query fields discovered: ", member_parameter, " and ", date_parameter
)
message(strrep("=", 72L))

# ---- 7. Query every member ---------------------------------------------------

arrangement_parts <- vector("list", nrow(members))
query_log_parts <- vector("list", nrow(members))
error_parts <- list()
source_headers_seen <- character()

for (i in seq_len(nrow(members))) {
  country <- members$country[i]
  member_key <- members$member_key[i]
  
  tsv_url <- build_results_url(
    results_base_url = results_base_url,
    member_parameter = member_parameter,
    date_parameter = date_parameter,
    member_key = member_key,
    as_of_date = latest_as_of_date,
    tsv = TRUE
  )
  
  message(sprintf("Processing %d/%d: %s", i, nrow(members), country))
  fetched <- fetch_with_retry(tsv_url)
  
  if (!fetched$ok) {
    query_status <- "failed"
    log_message <- fetched$error
    arrangement_rows <- 0L
    response_format <- NA_character_
    response_country <- NA_character_
    
    error_parts[[length(error_parts) + 1L]] <- make_error_row(
      stage = "member_query",
      country = country,
      member_key = member_key,
      url = tsv_url,
      error_status = fetched$error,
      http_status = fetched$status,
      attempts = fetched$attempts,
      content_type = fetched$content_type
    )
  } else {
    parsed_or_error <- tryCatch(
      parse_member_response(
        body = fetched$body,
        requested_date = latest_as_of_date,
        context = paste0(country, " [", member_key, "]")
      ),
      error = function(e) e
    )
    
    if (inherits(parsed_or_error, "error")) {
      query_status <- "failed"
      log_message <- paste("Parsing error:", conditionMessage(parsed_or_error))
      arrangement_rows <- 0L
      response_format <- NA_character_
      response_country <- NA_character_
      
      error_parts[[length(error_parts) + 1L]] <- make_error_row(
        stage = "member_query",
        country = country,
        member_key = member_key,
        url = tsv_url,
        error_status = log_message,
        http_status = fetched$status,
        attempts = fetched$attempts,
        content_type = fetched$content_type
      )
    } else {
      parsed <- parsed_or_error
      response_format <- parsed$response_format
      response_country <- parsed$response_country
      source_headers_seen <- union(source_headers_seen, parsed$source_headers)
      
      if (identical(parsed$status, "no_arrangements")) {
        query_status <- "queried_no_arrangements"
        log_message <- "No record returned for the specified member and date"
        arrangement_rows <- 0L
      } else {
        query_status <- "queried_with_arrangements"
        log_message <- "OK"
        arrangement_rows <- nrow(parsed$data)
        
        arrangement_parts[[i]] <- parsed$data |>
          mutate(
            country = country,
            member_key = member_key,
            as_of_date = latest_as_of_date,
            .before = 1L
          )
      }
    }
  }
  
  query_log_parts[[i]] <- tibble(
    member_number = i,
    country = country,
    member_key = member_key,
    as_of_date = latest_as_of_date,
    url_queried = tsv_url,
    status = query_status,
    arrangement_rows = as.integer(arrangement_rows),
    http_status = fetched$status,
    attempts = fetched$attempts,
    content_type = fetched$content_type,
    response_format = response_format,
    response_country = response_country,
    message = log_message
  )
  
  if (i < nrow(members)) {
    Sys.sleep(REQUEST_PAUSE_SECONDS + stats::runif(1L, 0, 0.15))
  }
}

arrangements <- if (all(vapply(arrangement_parts, is.null, logical(1L)))) {
  empty_arrangements()
} else {
  bind_rows(arrangement_parts)
}

query_log <- bind_rows(query_log_parts)
errors <- if (length(error_parts) == 0L) {
  empty_error_log()
} else {
  bind_rows(error_parts)
}

# ---- 8. Final dataset validation --------------------------------------------

number_of_members <- nrow(members)
number_successfully_queried <- sum(
  query_log$status %in% c(
    "queried_with_arrangements",
    "queried_no_arrangements"
  )
)
number_with_arrangements <- sum(query_log$status == "queried_with_arrangements")
number_with_no_arrangements <- sum(query_log$status == "queried_no_arrangements")
number_of_failures <- sum(query_log$status == "failed")
total_arrangement_rows <- nrow(arrangements)

if (nrow(query_log) != number_of_members) {
  stop("Internal validation failed: query log does not contain one row per member.")
}
if (number_successfully_queried + number_of_failures != number_of_members) {
  stop("Internal validation failed: member outcome counts do not sum correctly.")
}
if (sum(query_log$arrangement_rows, na.rm = TRUE) != total_arrangement_rows) {
  stop("Internal validation failed: query-log row counts do not match the dataset.")
}

unknown_members <- arrangements |>
  distinct(country, member_key) |>
  anti_join(members, by = c("country", "member_key"))
if (nrow(unknown_members) > 0L) {
  stop("Internal validation failed: arrangement rows contain an unknown member.")
}

wrong_as_of_date <- if (nrow(arrangements) == 0L) {
  0L
} else {
  sum(arrangements$as_of_date != latest_as_of_date, na.rm = TRUE)
}
if (wrong_as_of_date > 0L) {
  stop("Internal validation failed: inconsistent arrangement as-of dates.")
}

duplicate_key_columns <- c(
  "country",
  "member_key",
  "as_of_date",
  REQUIRED_IMF_COLUMNS,
  "amount_unit"
)
duplicate_rows_detected <- if (nrow(arrangements) == 0L) {
  0L
} else {
  sum(duplicated(as.data.frame(arrangements[duplicate_key_columns])))
}

negative_amount_values <- if (nrow(arrangements) == 0L) {
  0L
} else {
  sum(
    unlist(arrangements[AMOUNT_COLUMNS], use.names = FALSE) < 0,
    na.rm = TRUE
  )
}

missing_date_values <- if (nrow(arrangements) == 0L) {
  0L
} else {
  sum(is.na(arrangements$date_of_arrangement)) +
    sum(is.na(arrangements$expiration_date))
}

missing_amount_values <- if (nrow(arrangements) == 0L) {
  0L
} else {
  sum(is.na(unlist(arrangements[AMOUNT_COLUMNS], use.names = FALSE)))
}

units_used <- sort(unique(stats::na.omit(arrangements$amount_unit)))
units_metadata <- if (length(units_used) == 0L) {
  "No monetary unit observed because no arrangement rows were parsed"
} else {
  paste(units_used, collapse = "; ")
}

if (
  length(units_used) > 0L &&
  !all(units_used == "Thousands of SDRs")
) {
  warning(
    "At least one IMF response used an unexpected monetary unit: ",
    paste(units_used, collapse = "; ")
  )
}
if (duplicate_rows_detected > 0L) {
  warning(
    duplicate_rows_detected,
    " exact duplicate arrangement row(s) were detected and retained."
  )
}
if (negative_amount_values > 0L) {
  warning(negative_amount_values, " negative monetary value(s) were detected.")
}

# ---- 9. Drop sub-facility rows and append manual additions ------------------

# The IMF lists Supplemental Reserve Facility (SRF) resources as separate
# "of which Supplemental Reserve Facility" rows. They are part of a parent
# Stand-By or Extended arrangement (the parent's amount already includes them),
# so they are dropped. Each is first checked to lie within a parent arrangement
# for the same member, so dropping it cannot remove any programme time.
srf_rows <- arrangements |>
  filter(str_detect(facility, regex("Supplemental Reserve Facility", ignore_case = TRUE)))

parent_candidates <- arrangements |>
  filter(!str_detect(facility, regex("Supplemental Reserve Facility", ignore_case = TRUE))) |>
  select(
    member_key,
    parent_start = date_of_arrangement,
    parent_end = expiration_date
  )

srf_without_parent <- srf_rows |>
  left_join(parent_candidates, by = "member_key", relationship = "many-to-many") |>
  group_by(country, member_key, facility, date_of_arrangement, expiration_date) |>
  summarise(
    has_parent = any(
      !is.na(parent_start) &
        parent_start <= date_of_arrangement &
        parent_end >= expiration_date
    ),
    .groups = "drop"
  ) |>
  filter(!has_parent)

if (nrow(srf_without_parent) > 0L) {
  print(srf_without_parent, n = Inf, width = Inf)
  stop(
    "At least one Supplemental Reserve Facility row is not contained in a ",
    "parent arrangement for the same member; dropping it would remove ",
    "programme time. Review before rerunning.",
    call. = FALSE
  )
}

arrangements <- arrangements |>
  filter(!str_detect(facility, regex("Supplemental Reserve Facility", ignore_case = TRUE)))

number_of_srf_rows_dropped <- nrow(srf_rows)

# Scraped rows are labelled with their source; MANUAL_ARRANGEMENTS rows are
# appended after all validation of the scraped data above.
arrangements <- arrangements |>
  mutate(
    source = "IMF lending page",
    source_note = NA_character_
  )

manual_rows <- MANUAL_ARRANGEMENTS |>
  mutate(
    member_key = as.character(member_key),
    date_of_arrangement = as.Date(date_of_arrangement),
    expiration_date = as.Date(expiration_date)
  ) |>
  left_join(members, by = "member_key")

if (anyNA(manual_rows$country)) {
  stop(
    "MANUAL_ARRANGEMENTS contains a member key not in the member list: ",
    paste(manual_rows$member_key[is.na(manual_rows$country)], collapse = ", "),
    call. = FALSE
  )
}

if (anyNA(manual_rows$date_of_arrangement) || anyNA(manual_rows$expiration_date)) {
  stop("MANUAL_ARRANGEMENTS contains a missing or unparsable date.", call. = FALSE)
}

duplicate_manual_rows <- manual_rows |>
  count(member_key, facility, date_of_arrangement) |>
  filter(n > 1L)

if (nrow(duplicate_manual_rows) > 0L) {
  print(duplicate_manual_rows, n = Inf, width = Inf)
  stop(
    "MANUAL_ARRANGEMENTS contains the same member, facility and approval date ",
    "more than once.",
    call. = FALSE
  )
}

# Skip any manual row the IMF lists again.
manual_already_listed <- manual_rows |>
  semi_join(
    arrangements,
    by = c("member_key", "facility", "date_of_arrangement")
  )

manual_rows_added <- manual_rows |>
  anti_join(
    arrangements,
    by = c("member_key", "facility", "date_of_arrangement")
  ) |>
  transmute(
    country,
    member_key,
    as_of_date = latest_as_of_date,
    facility,
    date_of_arrangement,
    expiration_date,
    amount_agreed,
    amount_drawn,
    amount_outstanding,
    amount_unit = "Thousands of SDRs",
    source = "Manual addition",
    source_note
  )

if (nrow(manual_already_listed) > 0L) {
  message(
    "Manual arrangement(s) now listed by the IMF and therefore not added: ",
    paste(
      paste0(manual_already_listed$country, " ", manual_already_listed$facility,
             " ", manual_already_listed$date_of_arrangement),
      collapse = "; "
    ),
    ". They can be removed from MANUAL_ARRANGEMENTS or MANUAL_OUTRIGHT_PURCHASES."
  )
}

# Insert each manual row into its country's block, keeping the IMF row order:
# it goes just before the first IMF row with an earlier approval date (the IMF
# lists arrangements newest first), or at the end of the block. Manual rows
# that land in the same place are ordered newest first.
scraped_positions <- arrangements |>
  mutate(row_order = as.numeric(row_number())) |>
  select(member_key, date_of_arrangement, row_order)

manual_positions <- vapply(
  seq_len(nrow(manual_rows_added)),
  function(i) {
    same_member <- scraped_positions |>
      filter(member_key == manual_rows_added$member_key[i])
    earlier <- same_member |>
      filter(date_of_arrangement < manual_rows_added$date_of_arrangement[i])
    if (nrow(earlier) > 0L) {
      min(earlier$row_order) - 0.5
    } else if (nrow(same_member) > 0L) {
      max(same_member$row_order) + 0.5
    } else {
      Inf
    }
  },
  numeric(1L)
)

arrangements <- bind_rows(
  arrangements |>
    mutate(row_order = as.numeric(row_number())),
  manual_rows_added |>
    mutate(row_order = manual_positions)
) |>
  mutate(member_order = match(member_key, members$member_key)) |>
  arrange(member_order, row_order, desc(date_of_arrangement)) |>
  select(-member_order, -row_order)

number_of_manual_additions <- nrow(manual_rows_added)

manual_outright_added <- manual_rows_added |>
  filter(facility %in% OUTRIGHT_PURCHASE_FACILITIES)

manual_other_added <- manual_rows_added |>
  filter(!facility %in% OUTRIGHT_PURCHASE_FACILITIES)

number_of_outright_purchases_added <- nrow(manual_outright_added)

outright_purchase_counts <- manual_outright_added |>
  count(facility) |>
  arrange(match(facility, OUTRIGHT_PURCHASE_FACILITIES))

# ---- 10. Reproducibility metadata -------------------------------------------

RUN_COMPLETED_UTC <- format(
  Sys.time(),
  format = "%Y-%m-%dT%H:%M:%SZ",
  tz = "UTC"
)

package_versions <- paste(
  vapply(
    REQUIRED_PACKAGES,
    function(package_name) {
      paste0(package_name, " ", as.character(packageVersion(package_name)))
    },
    character(1L)
  ),
  collapse = "; "
)

run_metadata <- tibble(
  item = c(
    "Source landing-page URL",
    "Discovered results endpoint",
    "Form method",
    "Discovered member query parameter",
    "Discovered date query parameter",
    "TSV query parameter",
    "Run started (UTC)",
    "Run completed (UTC)",
    "IMF As of Date used",
    "Available IMF date options found",
    "IMF members found",
    "Members successfully queried",
    "Members returning at least one arrangement",
    "Members returning no arrangements",
    "Member query failures",
    "Total arrangement observations (scraped)",
    "Supplemental Reserve Facility rows dropped",
    "Manual additions appended",
    "Facility-name cleaning",
    "Financial amount units",
    "Monetary conversion",
    "IMF returned source headers observed",
    "Exact duplicate rows detected",
    "Duplicate-row handling",
    "Missing arrangement/expiration date values",
    "Missing financial amount values",
    "Negative financial amount values",
    "Requests",
    "Retry policy",
    "No-arrangement behavior",
    "User-Agent",
    "R version",
    "Package versions",
    "Output workbook"
  ),
  value = c(
    LANDING_URL,
    results_base_url,
    str_to_upper(form_method),
    member_parameter,
    date_parameter,
    "tsvflag=Y",
    RUN_STARTED_UTC,
    RUN_COMPLETED_UTC,
    format(latest_as_of_date, "%Y-%m-%d"),
    as.character(length(unique(available_dates))),
    as.character(number_of_members),
    as.character(number_successfully_queried),
    as.character(number_with_arrangements),
    as.character(number_with_no_arrangements),
    as.character(number_of_failures),
    as.character(total_arrangement_rows),
    paste0(
      number_of_srf_rows_dropped,
      if (number_of_srf_rows_dropped > 0L) {
        paste0(
          " (", paste(paste0(srf_rows$country, " ", srf_rows$date_of_arrangement), collapse = "; "),
          "); each lies within a parent arrangement for the same member"
        )
      } else {
        ""
      }
    ),
    if (number_of_manual_additions == 0L) {
      "None"
    } else {
      paste0(
        number_of_manual_additions, ": ",
        paste(
          c(
            paste0(manual_other_added$country, " ", manual_other_added$facility,
                   " approved ", manual_other_added$date_of_arrangement),
            paste0(outright_purchase_counts$n, " ", outright_purchase_counts$facility,
                   " outright purchases")
          ),
          collapse = "; "
        ),
        " (see source_note in the Arrangements sheet)"
      )
    },
    paste0(
      "HTML markup and trailing footnote markers removed from facility names ",
      "(e.g. 'Precautionary and Liquidity Line<sup>1/</sup>' becomes ",
      "'Precautionary and Liquidity Line')"
    ),
    units_metadata,
    paste0(
      "None. Displayed values were parsed numerically after removal of ",
      "grouping commas and remain in the IMF source unit."
    ),
    if (length(source_headers_seen) == 0L) {
      "No source headers observed"
    } else {
      paste(source_headers_seen, collapse = " | ")
    },
    as.character(duplicate_rows_detected),
    "Exact duplicates were flagged in validation but retained; none were silently removed.",
    as.character(missing_date_values),
    as.character(missing_amount_values),
    as.character(negative_amount_values),
    paste0(
      "Sequential; base inter-member pause ",
      REQUEST_PAUSE_SECONDS,
      " seconds plus 0-0.15 seconds jitter"
    ),
    paste0(
      "Up to ",
      MAX_ATTEMPTS,
      " attempts; retry network errors, empty HTTP 200 bodies, HTTP 408/425/429, and HTTP 5xx"
    ),
    paste0(
      "The IMF currently returns an HTML no-record page (HTTP 200), even when ",
      "tsvflag=Y; this is treated as a successful empty result."
    ),
    USER_AGENT,
    R.version.string,
    package_versions,
    OUTPUT_FILE
  )
)

# ---- 11. Write the Excel workbook -------------------------------------------

dir.create(dirname(OUTPUT_FILE), recursive = TRUE, showWarnings = FALSE)

wb <- createWorkbook(creator = "IMF Financial Arrangements R scraper")

header_style <- createStyle(
  fontColour = "#FFFFFF",
  fgFill = "#1F4E78",
  textDecoration = "bold",
  halign = "center",
  valign = "center",
  wrapText = TRUE,
  border = "Bottom",
  borderColour = "#D9EAF7"
)
date_style <- createStyle(numFmt = "yyyy-mm-dd")
amount_style <- createStyle(numFmt = "#,##0.###")
text_style <- createStyle(numFmt = "@")

write_workbook_sheet <- function(
    workbook,
    sheet_name,
    data,
    widths = "auto",
    filter = TRUE
) {
  addWorksheet(workbook, sheet_name, gridLines = FALSE)
  writeData(
    workbook,
    sheet = sheet_name,
    x = data,
    startRow = 1L,
    startCol = 1L,
    colNames = TRUE,
    rowNames = FALSE,
    headerStyle = header_style,
    withFilter = filter && nrow(data) > 0L,
    keepNA = FALSE
  )
  freezePane(workbook, sheet_name, firstRow = TRUE)
  setColWidths(
    workbook,
    sheet = sheet_name,
    cols = seq_len(ncol(data)),
    widths = widths
  )
  
  if (nrow(data) > 0L) {
    date_columns <- which(vapply(data, function(x) inherits(x, "Date"), logical(1L)))
    if (length(date_columns) > 0L) {
      addStyle(
        workbook,
        sheet = sheet_name,
        style = date_style,
        rows = 2L:(nrow(data) + 1L),
        cols = date_columns,
        gridExpand = TRUE,
        stack = TRUE
      )
    }
  }
}

write_workbook_sheet(
  wb,
  "Arrangements",
  arrangements,
  widths = c(38, 13, 13, 46, 18, 18, 18, 18, 20, 22, 20, 90)
)

if (nrow(arrangements) > 0L) {
  addStyle(
    wb,
    "Arrangements",
    amount_style,
    rows = 2L:(nrow(arrangements) + 1L),
    cols = match(AMOUNT_COLUMNS, names(arrangements)),
    gridExpand = TRUE,
    stack = TRUE
  )
  addStyle(
    wb,
    "Arrangements",
    text_style,
    rows = 2L:(nrow(arrangements) + 1L),
    cols = match("member_key", names(arrangements)),
    gridExpand = TRUE,
    stack = TRUE
  )
}

write_workbook_sheet(
  wb,
  "Members",
  members,
  widths = c(42, 16)
)
if (nrow(members) > 0L) {
  addStyle(
    wb,
    "Members",
    text_style,
    rows = 2L:(nrow(members) + 1L),
    cols = match("member_key", names(members)),
    gridExpand = TRUE,
    stack = TRUE
  )
}

write_workbook_sheet(
  wb,
  "Run_Metadata",
  run_metadata,
  widths = c(46, 110),
  filter = FALSE
)

write_workbook_sheet(
  wb,
  "Errors",
  errors,
  widths = c(18, 36, 13, 85, 85, 14, 12, 30)
)

# The query log makes successful empty results directly inspectable without
# conflating them with failures.
write_workbook_sheet(
  wb,
  "Query_Log",
  query_log,
  widths = c(14, 36, 13, 13, 85, 30, 18, 14, 12, 30, 24, 36, 60)
)


saveWorkbook(wb, OUTPUT_FILE, overwrite = TRUE)

# ---- 12. Concise console validation summary ---------------------------------

cat("\n", strrep("=", 72L), "\n", sep = "")
cat("IMF FINANCIAL ARRANGEMENTS: VALIDATION SUMMARY\n")
cat(strrep("=", 72L), "\n", sep = "")
cat(sprintf(
  "Latest IMF as-of date selected:       %s\n",
  format(latest_as_of_date, "%Y-%m-%d")
))
cat(sprintf("Members found:                       %d\n", number_of_members))
cat(sprintf("Members successfully processed:      %d\n", number_successfully_queried))
cat(sprintf("Members with arrangements:           %d\n", number_with_arrangements))
cat(sprintf("Members with no arrangements:        %d\n", number_with_no_arrangements))
cat(sprintf("Member failures:                     %d\n", number_of_failures))
cat(sprintf("Total arrangement rows (scraped):    %d\n", total_arrangement_rows))
cat(sprintf("SRF sub-facility rows dropped:       %d\n", number_of_srf_rows_dropped))
cat(sprintf("Manual additions appended:           %d\n", number_of_manual_additions))
cat(sprintf("  of which outright purchases:       %d\n", number_of_outright_purchases_added))
cat(sprintf("Exact duplicate rows detected:       %d\n", duplicate_rows_detected))
cat(sprintf("Workbook written to:                 %s\n", normalizePath(OUTPUT_FILE)))
cat(strrep("=", 72L), "\n", sep = "")

if (number_of_failures > 0L) {
  cat("Review the Errors and Query_Log sheets before using the dataset.\n")
}
