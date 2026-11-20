# Helpers for the Harvard Dataverse native API, used to manage the IMF Monitor
# collection, https://dataverse.harvard.edu/dataverse/imfmonitor (CLAUDE.md,
# "Harvard Dataverse"). Source this file; nothing runs on its own.
#
# Reading needs no key. Changing anything needs an API token in the
# DATAVERSE_KEY environment variable, set in ~/.Renviron and never in the
# repository; httr2 redacts it whenever a request is printed.
#
# Every function that changes something takes dry_run, TRUE by default, and
# then prints the request and its JSON body without sending it. Changes to a
# dataset's metadata or files make a draft version that only its editors can
# see: nothing is public until dv_publish(). Links, moves, and collection
# settings take effect as soon as they are sent.

dv_server <- "https://dataverse.harvard.edu"

dv_or <- function(a, b) if (is.null(a)) b else a

# On Windows, RStudio's ~ is Documents, but R started from a shell that sets
# HOME (Git Bash) looks for ~/.Renviron in the user folder instead. If the key
# isn't set, read the Documents copy that RStudio uses.
dv_load_key <- function() {
  if (nzchar(Sys.getenv("DATAVERSE_KEY"))) return(invisible(TRUE))
  documents <- file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron")
  if (.Platform$OS.type == "windows" && file.exists(documents)) readRenviron(documents)
  invisible(nzchar(Sys.getenv("DATAVERSE_KEY")))
}

dv_has_key <- function() {
  dv_load_key()
  nzchar(Sys.getenv("DATAVERSE_KEY"))
}

dv_key <- function() {
  if (!dv_has_key()) {
    stop("No API token: add DATAVERSE_KEY to ~/.Renviron and restart R.", call. = FALSE)
  }
  Sys.getenv("DATAVERSE_KEY")
}

# Dataverse explains a refusal in the response body's "message".
dv_error_body <- function(resp) {
  tryCatch(httr2::resp_body_json(resp)$message, error = function(e) NULL)
}

dv_request <- function(path, query = list(), method = "GET", auth = dv_has_key()) {
  req <- httr2::request(dv_server) |>
    httr2::req_url_path_append(path) |>
    httr2::req_method(method) |>
    httr2::req_user_agent("imfmonitor dataverse scripts (httr2)") |>
    httr2::req_error(body = dv_error_body)
  if (length(query) > 0) req <- do.call(httr2::req_url_query, c(list(req), query))
  # Only reads are retried: a change that timed out may still have been applied.
  if (method == "GET") req <- httr2::req_retry(req, max_tries = 3)
  if (auth) {
    req <- httr2::req_headers(req, `X-Dataverse-key` = dv_key(), .redact = "X-Dataverse-key")
  }
  req
}

dv_perform <- function(req, dry_run = FALSE, body = NULL) {
  if (dry_run) {
    cat("DRY RUN, not sent:", req$method, req$url, "\n")
    if (!is.null(body)) cat(dv_json(body), "\n")
    return(invisible(NULL))
  }
  resp <- httr2::req_perform(req)
  httr2::resp_body_json(resp, simplifyVector = FALSE)$data
}

dv_json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null")

dv_get <- function(path, query = list(), auth = dv_has_key()) {
  dv_perform(dv_request(path, query, auth = auth))
}

# Reading ---------------------------------------------------------------------

# Confirms the token works without showing it.
dv_whoami <- function() {
  me <- dv_get("api/users/:me", auth = TRUE)
  cat("The token works for", me$displayName, paste0("(", me$identifier, ")"), "\n")
  invisible(me)
}

# The latest version, including a draft when the token's user can see it.
dv_dataset <- function(pid) {
  dv_get("api/datasets/:persistentId/", list(persistentId = pid))
}

dv_contents <- function(alias) dv_get(paste0("api/dataverses/", alias, "/contents"))

dv_files <- function(pid) {
  files <- dv_dataset(pid)$latestVersion$files
  data.frame(
    name = vapply(files, \(f) dv_or(f$dataFile$originalFileName, f$dataFile$filename), ""),
    directory = vapply(files, \(f) dv_or(f$directoryLabel, ""), ""),
    md5 = vapply(files, \(f) dv_or(f$dataFile$md5, NA_character_), ""),
    bytes = vapply(files, \(f) as.numeric(dv_or(f$dataFile$originalFileSize, f$dataFile$filesize)), 0),
    id = vapply(files, \(f) as.numeric(f$dataFile$id), 0)
  )
}

# Compares local files with a dataset's files by name and MD5. Dataverse keeps
# each original's MD5, including ingested .dta files.
dv_check_md5 <- function(pid, paths) {
  local <- data.frame(name = basename(paths), md5_local = unname(tools::md5sum(paths)))
  out <- merge(local, dv_files(pid)[c("name", "directory", "md5")], by = "name", all = TRUE)
  out$identical <- !is.na(out$md5_local) & !is.na(out$md5) & out$md5_local == out$md5
  out
}

# Metadata fields ---------------------------------------------------------------

dv_block_cache <- new.env()

dv_block <- function(name = "citation") {
  if (is.null(dv_block_cache[[name]])) {
    dv_block_cache[[name]] <- dv_get(paste0("api/metadatablocks/", name), auth = FALSE)
  }
  dv_block_cache[[name]]
}

# Builds a field in the API's full JSON form from a plain R value, checking its
# name, subfield names, and controlled-vocabulary values against the metadata
# block, so that a typo fails here rather than on Dataverse. A compound field
# takes a named list per entry; a multiple compound field, a list of them.
dv_field <- function(name, value, defs = dv_block()$fields) {
  def <- defs[[name]]
  if (is.null(def)) stop("Unknown metadata field: ", name, call. = FALSE)
  check_vocabulary <- function(v) {
    if (isTRUE(def$isControlledVocabulary)) {
      bad <- setdiff(unlist(v), unlist(def$controlledVocabularyValues))
      if (length(bad) > 0) {
        stop("Not in the vocabulary for ", name, ": ", paste(bad, collapse = ", "), call. = FALSE)
      }
    }
    v
  }
  compound_entry <- function(entry) {
    unknown <- setdiff(names(entry), names(def$childFields))
    if (length(unknown) > 0) {
      stop("Unknown subfield of ", name, ": ", paste(unknown, collapse = ", "), call. = FALSE)
    }
    entry <- entry[!vapply(entry, is.null, logical(1))]
    lapply(stats::setNames(names(entry), names(entry)), \(sub) dv_field(sub, entry[[sub]], def$childFields))
  }
  value <- if (def$typeClass == "compound") {
    if (isTRUE(def$multiple)) lapply(value, compound_entry) else compound_entry(value)
  } else if (isTRUE(def$multiple)) {
    as.list(check_vocabulary(unlist(value)))
  } else {
    check_vocabulary(value)
  }
  list(typeName = name, multiple = isTRUE(def$multiple), typeClass = def$typeClass, value = value)
}

dv_author <- function(name, affiliation = NULL, orcid = NULL) {
  list(
    authorName = name,
    authorAffiliation = affiliation,
    authorIdentifierScheme = if (!is.null(orcid)) "ORCID",
    authorIdentifier = orcid
  )
}

# A related publication with its DOI as the identifier, which Dataverse sends
# to DataCite as a machine-readable link between the data and the publication.
dv_publication <- function(citation, doi, relation = "IsSupplementTo") {
  list(
    publicationRelationType = relation,
    publicationCitation = citation,
    publicationIDType = "doi",
    publicationIDNumber = doi,
    publicationURL = paste0("https://doi.org/", doi)
  )
}

dv_license <- function(name = "CC0 1.0") {
  hit <- Filter(\(l) identical(l$name, name), dv_get("api/licenses", auth = FALSE))
  if (length(hit) != 1) stop("No such licence on Dataverse: ", name, call. = FALSE)
  list(name = hit[[1]]$name, uri = hit[[1]]$uri)
}

# Changes -----------------------------------------------------------------------

# With replace = TRUE, each field given replaces that field's current values.
dv_edit_metadata <- function(pid, fields, replace = TRUE, dry_run = TRUE) {
  body <- list(fields = unname(fields))
  query <- list(persistentId = pid, replace = tolower(as.character(replace)))
  req <- dv_request("api/datasets/:persistentId/editMetadata", query, "PUT", auth = !dry_run) |>
    httr2::req_body_json(body, auto_unbox = TRUE, null = "null")
  dv_perform(req, dry_run, body)
}

# "minor" for metadata-only changes; Dataverse refuses it if files changed.
dv_publish <- function(pid, type = c("minor", "major"), dry_run = TRUE) {
  type <- match.arg(type)
  query <- list(persistentId = pid, type = type)
  dv_perform(dv_request("api/datasets/:persistentId/actions/:publish", query, "POST", auth = !dry_run), dry_run)
}

# Shows a dataset owned elsewhere in a collection's listing, without moving it.
dv_link <- function(pid, alias, dry_run = TRUE) {
  path <- paste0("api/datasets/", dv_dataset(pid)$id, "/link/", alias)
  dv_perform(dv_request(path, method = "PUT", auth = !dry_run), dry_run)
}

# Makes the collection the dataset's owner. Dataverse allows it only to users
# who can publish in both the old and the new collection; the DOI is unchanged.
# If the dataset is already linked into the new collection, Dataverse wants
# force = TRUE, which drops that link, redundant once the collection owns it.
dv_move <- function(pid, alias, force = FALSE, dry_run = TRUE) {
  path <- paste0("api/datasets/", dv_dataset(pid)$id, "/move/", alias)
  query <- if (force) list(forceMove = "true") else list()
  dv_perform(dv_request(path, query, method = "POST", auth = !dry_run), dry_run)
}

# Changes one setting of a collection: name, description, affiliation, and a
# few others. Live at once. The theme (logo, colours, tagline, website link)
# has no API and is set in the web form (Edit → Theme + Widgets).
dv_set_collection <- function(alias, attribute, value, dry_run = TRUE) {
  path <- paste0("api/dataverses/", alias, "/attribute/", attribute)
  dv_perform(dv_request(path, list(value = value), method = "PUT", auth = !dry_run), dry_run)
}

# Changes the collection settings given, in a JSON body; per Dataverse's guide,
# omitted settings stay as they are. Use this for text with HTML, such as the
# description: Harvard's firewall refuses HTML in a query string (403), which
# rules out dv_set_collection() for it.
dv_update_collection <- function(alias, settings, dry_run = TRUE) {
  req <- dv_request(paste0("api/dataverses/", alias), method = "PUT", auth = !dry_run) |>
    httr2::req_body_json(settings, auto_unbox = TRUE, null = "null")
  dv_perform(req, dry_run, settings)
}

# The collections a dataset is linked into (not the one that owns it).
dv_links <- function(pid) {
  links <- dv_get("api/datasets/:persistentId/links", list(persistentId = pid))
  vapply(links[["linked-dataverses"]], \(l) l$alias, "")
}

# Creates an unpublished draft and returns its id and DOI.
dv_create_dataset <- function(alias, fields, license = "CC0 1.0", dry_run = TRUE) {
  body <- list(datasetVersion = list(
    license = dv_license(license),
    metadataBlocks = list(citation = list(fields = unname(fields)))
  ))
  req <- dv_request(paste0("api/dataverses/", alias, "/datasets"), method = "POST", auth = !dry_run) |>
    httr2::req_body_json(body, auto_unbox = TRUE, null = "null")
  dv_perform(req, dry_run, body)
}

# Dataverse locks a dataset while it ingests a tabular file (such as .dta) and
# refuses other changes until it finishes.
dv_wait_unlocked <- function(pid, timeout = 1800) {
  start <- Sys.time()
  repeat {
    locks <- dv_get("api/datasets/:persistentId/locks", list(persistentId = pid))
    if (length(locks) == 0) return(invisible(TRUE))
    if (difftime(Sys.time(), start, units = "secs") > timeout) {
      stop("Still locked after ", timeout, " seconds: ",
           paste(vapply(locks, \(l) l$lockType, ""), collapse = ", "), call. = FALSE)
    }
    Sys.sleep(10)
  }
}

dv_add_file <- function(pid, path, directory = NULL, description = NULL, dry_run = TRUE) {
  if (!file.exists(path)) stop("No such file: ", path, call. = FALSE)
  json <- list(directoryLabel = directory, description = description, restrict = FALSE)
  json <- json[!vapply(json, is.null, logical(1))]
  if (dry_run) {
    cat("DRY RUN, not sent: add", basename(path), paste0("(", file.size(path), " bytes)"),
        "to", pid, if (!is.null(directory)) paste("in", directory), "\n")
    return(invisible(NULL))
  }
  dv_wait_unlocked(pid)
  req <- dv_request("api/datasets/:persistentId/add", list(persistentId = pid), "POST") |>
    httr2::req_body_multipart(
      file = curl::form_file(path),
      jsonData = as.character(jsonlite::toJSON(json, auto_unbox = TRUE))
    ) |>
    httr2::req_timeout(3600)
  added <- dv_perform(req)
  cat("Added", basename(path), "\n")
  invisible(added)
}
