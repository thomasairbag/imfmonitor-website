-- Shortcodes that display dataset facts from data/datasets.yml.
--
--   {{< dataset-glance >}}      at-a-glance panel
--   {{< dataset-downloads >}}   download list for the current release,
--                               codebooks first
--   {{< dataset-history >}}     version history: each release with its note
--                               and files, newest first
--   {{< dataset-value FIELD >}} one fact inline in running text, e.g.
--                               counts.conditions
--   {{< dataset-cite >}}        citation box with a copy button
--   {{< dataset-card ID >}}     summary card linking to the dataset's page
--   {{< dataset-entry ID >}}    coverage, status, files, and citation for a
--                               short entry on another page (Other Data)
--
-- glance, downloads, history, and cite use the ID given as their first
-- argument, or else the page's `dataset` metadata. Empty fields show "To be
-- confirmed", so nothing appears that the data file does not state. For a
-- forthcoming dataset, the version, downloads, and history say "Not yet
-- released".

local stringify = pandoc.utils.stringify

local TBC = "To be confirmed"

local STATUS_LABELS = {
  ["available"] = "Available",
  ["forthcoming"] = "Forthcoming",
  ["replication-only"] = "Replication only",
}

-- Versions are release dates, so there is no separate "Last updated" row.
-- Licences are stated once, in the footer, not per dataset.
local GLANCE_FIELDS = {
  { "coverage", "Coverage" },
  { "version", "Version" },
  { "unit", "Unit of observation" },
}

local function classes(...)
  return pandoc.Attr("", { ... })
end

local function is_empty(v)
  return v == nil or stringify(v) == ""
end

local function tbc()
  return pandoc.Span({ pandoc.Str(TBC) }, classes("tbc"))
end

-- A forthcoming dataset has no files or releases yet; say so rather than
-- show "To be confirmed" or an empty section.
local NOT_RELEASED = "Not yet released."

local function is_forthcoming(d)
  return not is_empty(d.status) and stringify(d.status) == "forthcoming"
end

local function not_released()
  return pandoc.Para({ pandoc.Span({ pandoc.Str(NOT_RELEASED) }, classes("tbc")) })
end

-- A metadata value as inlines, keeping any Markdown formatting.
local function inlines(v)
  local kind = pandoc.utils.type(v)
  if kind == "Inlines" then return v end
  if kind == "Blocks" then return pandoc.utils.blocks_to_inlines(v) end
  return pandoc.Inlines({ pandoc.Str(stringify(v)) })
end

local function value_or_tbc(v)
  if is_empty(v) then return pandoc.Inlines({ tbc() }) end
  return inlines(v)
end

-- The version, or "Not yet released" for a forthcoming dataset without one.
local function version_or_status(d)
  if is_empty(d.version) and is_forthcoming(d) then
    return pandoc.Inlines({ pandoc.Span({ pandoc.Str(NOT_RELEASED:sub(1, -2)) }, classes("tbc")) })
  end
  return value_or_tbc(d.version)
end

-- The file is read here rather than through Quarto's `metadata-files`,
-- which rewrites any value matching a file or folder name (on Windows,
-- "Conditionality" becomes "../Conditionality"). Pandoc parses the YAML and
-- the Markdown inside its values.
local cached_datasets = nil

local function all_datasets()
  if cached_datasets ~= nil then return cached_datasets end
  local path = pandoc.path.join({ quarto.project.directory, "data", "datasets.yml" })
  local file = io.open(path, "r")
  if file == nil then
    quarto.log.warning("imfmonitor: cannot read " .. path)
    cached_datasets = {}
    return cached_datasets
  end
  local yaml = file:read("a")
  file:close()
  local meta = pandoc.read("---\n" .. yaml .. "\n---\n", "markdown").meta
  cached_datasets = meta.datasets or {}
  return cached_datasets
end

-- Paths in datasets.yml are relative to the project root; links in the page
-- must be relative to the page. URLs pass through unchanged.
local function from_root(path)
  if path:match("^%a[%w+.-]*:") then return path end
  local offset = quarto.project.offset or "."
  return offset .. "/" .. path:gsub("^/", "")
end

-- An entry without a page of its own (`page` in datasets.yml) is a section
-- of that page, anchored by its id.
local function page_href(d)
  if not is_empty(d.page) then
    return from_root(stringify(d.page) .. "/index.qmd") .. "#" .. stringify(d.id)
  end
  return from_root(stringify(d.id) .. "/index.qmd")
end

local function find_dataset(id)
  for _, d in ipairs(all_datasets()) do
    if stringify(d.id) == id then return d end
  end
  quarto.log.warning("imfmonitor: no dataset with id '" .. id .. "' in data/datasets.yml")
  return nil
end

local function page_dataset(args, meta)
  local id = ""
  if args[1] ~= nil then
    id = stringify(args[1])
  elseif meta.dataset ~= nil then
    id = stringify(meta.dataset)
  end
  return find_dataset(id)
end

local function status_badge(d)
  local status = is_empty(d.status) and "" or stringify(d.status)
  local label = STATUS_LABELS[status]
  if label == nil and status ~= "" then
    quarto.log.warning("imfmonitor: unknown status '" .. status .. "' for " .. stringify(d.id) ..
      " in data/datasets.yml (use available, forthcoming, or replication-only)")
  end
  if label == nil then
    return pandoc.Span({ pandoc.Str("Status " .. TBC:lower()) }, classes("status", "status-tbc"))
  end
  return pandoc.Span({ pandoc.Str(label) }, classes("status", "status-" .. status))
end

local function glance(args, kwargs, meta)
  local d = page_dataset(args, meta)
  if d == nil then return pandoc.Blocks({}) end
  local items = {}
  for _, field in ipairs(GLANCE_FIELDS) do
    table.insert(items, {
      { pandoc.Str(field[2]) },
      { { pandoc.Plain(field[1] == "version" and version_or_status(d) or value_or_tbc(d[field[1]])) } },
    })
  end
  table.insert(items, {
    { pandoc.Str("Status") },
    { { pandoc.Plain({ status_badge(d) }) } },
  })
  return pandoc.Div({ pandoc.DefinitionList(items) }, classes("glance"))
end

local function kind(f)
  return stringify(f.kind or "")
end

-- Files on the site download directly. A Harvard Dataverse DOI opens the
-- record's landing page, not a file, so its button names the repository.
local function is_dataverse(href)
  return href:match("^https://doi%.org/10%.7910/") ~= nil
end

-- A list of files, each with its details and a Download button. The archive
-- leaves out the version, which its heading already gives.
local function file_list(files, show_version)
  local detail_keys = show_version and { "format", "size", "version" } or { "format", "size" }
  local items = {}
  for _, f in ipairs(files) do
    local href = stringify(f.href or "")
    local label = is_empty(f.label) and pandoc.Inlines({ pandoc.Str(href) }) or inlines(f.label)
    local details = {}
    for _, key in ipairs(detail_keys) do
      if not is_empty(f[key]) then table.insert(details, stringify(f[key])) end
    end
    -- A file not yet approved for publication has no href: say so rather
    -- than link to the site root.
    local button = tbc()
    if href ~= "" then
      local text, aria = "Download", "Download " .. stringify(label)
      if is_dataverse(href) then
        text, aria = "Harvard Dataverse", stringify(label) .. " on Harvard Dataverse"
      end
      button = pandoc.Link({ pandoc.Str(text) }, from_root(href), "",
        pandoc.Attr("", { "btn", "btn-primary", "btn-sm" }, { ["aria-label"] = aria }))
    end
    local text = { pandoc.Strong(label) }
    if not is_empty(f.description) then
      table.insert(text, pandoc.LineBreak())
      table.insert(text, pandoc.Span(inlines(f.description), classes("file-description")))
    end
    if #details > 0 then
      table.insert(text, pandoc.LineBreak())
      table.insert(text, pandoc.Span({ pandoc.Str(table.concat(details, " · ")) }, classes("file-details")))
    end
    table.insert(items, {
      pandoc.Div({
        pandoc.Div({ pandoc.Plain(text) }, classes("download-label")),
        pandoc.Plain({ button }),
      }, classes("download-item")),
    })
  end
  return pandoc.Div({ pandoc.BulletList(items) }, classes("downloads"))
end

-- Files of the current release; earlier releases go under Version history.
local function downloads(args, kwargs, meta)
  local d = page_dataset(args, meta)
  if d == nil then return pandoc.Blocks({}) end
  local ordered = {}
  for _, f in ipairs(d.files or {}) do
    if kind(f) == "codebook" then table.insert(ordered, f) end
  end
  for _, f in ipairs(d.files or {}) do
    if kind(f) ~= "codebook" and kind(f) ~= "archive" then table.insert(ordered, f) end
  end
  if #ordered == 0 then
    if is_forthcoming(d) then return pandoc.Div({ not_released() }, classes("downloads")) end
    return pandoc.Div({ pandoc.Para({ pandoc.Span({ pandoc.Str("Files " .. TBC:lower() .. ".") }, classes("tbc")) }) },
      classes("downloads"))
  end
  return file_list(ordered, true)
end

local MONTHS = {
  January = "01", February = "02", March = "03", April = "04", May = "05", June = "06",
  July = "07", August = "08", September = "09", October = "10", November = "11", December = "12",
}

-- "September 2017" -> "2017-09"; nil if the version is not a release date.
local function release_month(version)
  local month, year = version:match("^(%a+) (%d%d%d%d)$")
  local mm = month and MONTHS[month]
  return mm and (year .. "-" .. mm) or nil
end

local function warn_not_release_date(d, what, version)
  quarto.log.warning("imfmonitor: " .. what .. " version '" .. version .. "' for " .. stringify(d.id) ..
    " in data/datasets.yml is not a release date such as 'September 2017'")
end

-- A superseded release's files are named vYYYY-MM_IMFMonitor_... after its
-- release date (Thomas, 20 October 2026). Warn when an archive entry's label
-- or href doesn't carry the prefix that matches its version.
local function check_archive_name(d, f, version)
  local ym = release_month(version)
  if ym == nil then
    warn_not_release_date(d, "archive file", version)
    return
  end
  local prefix = "v" .. ym .. "_IMFMonitor_"
  for _, key in ipairs({ "label", "href" }) do
    local value = stringify(f[key] or "")
    if value ~= "" and not value:find(prefix, 1, true) then
      quarto.log.warning("imfmonitor: archive file " .. key .. " '" .. value .. "' for " ..
        stringify(d.id) .. " in data/datasets.yml should use the file name prefix " .. prefix)
    end
  end
end

-- Version history: one entry per release, newest first, from the dataset's
-- `history` list. Each has a heading (release date, and the old version number
-- if it had one), a note on what changed, and its files: a pointer to Downloads
-- for the current release, the archive files for an earlier one. Archive files
-- of a release with no history entry still appear, under a heading of their own.
local function history(args, kwargs, meta)
  local d = page_dataset(args, meta)
  if d == nil then return pandoc.Blocks({}) end
  local current = is_empty(d.version) and "" or stringify(d.version)

  local versions, groups = {}, {}
  for _, f in ipairs(d.files or {}) do
    if kind(f) == "archive" then
      local v = is_empty(f.version) and TBC or stringify(f.version)
      check_archive_name(d, f, v)
      if groups[v] == nil then
        groups[v] = {}
        table.insert(versions, v)
      end
      table.insert(groups[v], f)
    end
  end

  local blocks = pandoc.Blocks({})
  local shown = {}
  local function heading(v, former)
    local text = pandoc.Inlines({ pandoc.Str(v) })
    if former ~= "" then text:extend({ pandoc.Space(), pandoc.Str("(" .. former .. ")") }) end
    blocks:insert(pandoc.Header(3, text, classes("unnumbered", "unlisted")))
  end

  for _, entry in ipairs(d.history or {}) do
    local v = is_empty(entry.version) and TBC or stringify(entry.version)
    if release_month(v) == nil then warn_not_release_date(d, "history", v) end
    heading(v, is_empty(entry.former) and "" or stringify(entry.former))
    if not is_empty(entry.note) then blocks:insert(pandoc.Para(inlines(entry.note))) end
    if v == current then
      blocks:extend(pandoc.read("Current release: its files are under [Downloads](#downloads).", "markdown").blocks)
    end
    if groups[v] ~= nil then blocks:insert(file_list(groups[v], false)) end
    shown[v] = true
  end

  for _, v in ipairs(versions) do
    if not shown[v] then
      heading(v, "")
      blocks:insert(file_list(groups[v], false))
    end
  end
  if #blocks == 0 and is_forthcoming(d) then blocks:insert(not_released()) end
  return blocks
end

-- One fact, inline in running text, so prose never hard-codes a number that
-- datasets.yml holds: {{< dataset-value counts.conditions >}} for the page's
-- dataset, or {{< dataset-value ID FIELD >}} for another. A dotted FIELD
-- reaches into a nested record.
local function value(args, kwargs, meta)
  local path
  local d
  if #args >= 2 then
    d = find_dataset(stringify(args[1]))
    path = stringify(args[2])
  else
    d = page_dataset({}, meta)
    path = stringify(args[1] or "")
  end
  if d == nil then return pandoc.Inlines({ tbc() }) end
  local v = d
  for key in path:gmatch("[^.]+") do
    -- Only a metadata map has named fields; Inlines and lists are tables too.
    v = pandoc.utils.type(v) == "table" and v[key] or nil
    if v == nil then break end
  end
  if is_empty(v) then
    quarto.log.warning("imfmonitor: no value '" .. path .. "' for " .. stringify(d.id) .. " in data/datasets.yml")
    return pandoc.Inlines({ tbc() })
  end
  return inlines(v)
end

local function cite(args, kwargs, meta)
  local d = page_dataset(args, meta)
  if d == nil then return pandoc.Blocks({}) end
  if is_empty(d.citation) then
    return pandoc.Div({ pandoc.Para({ pandoc.Span({ pandoc.Str("Citation " .. TBC:lower() .. ".") }, classes("tbc")) }) },
      classes("cite-box"))
  end
  return pandoc.Div({
    pandoc.Para(inlines(d.citation)),
    pandoc.RawBlock("html",
      '<button type="button" class="btn btn-outline-primary btn-sm cite-copy">Copy citation</button>'),
  }, classes("cite-box"))
end

local function card(args, kwargs, meta)
  local d = page_dataset(args, meta)
  if d == nil then return pandoc.Blocks({}) end
  local title = pandoc.Link(inlines(d.name), page_href(d), "", classes("stretched-link"))
  local coverage = { pandoc.Span({ pandoc.Str("Coverage:") }, classes("card-label")), pandoc.Space() }
  for _, inline in ipairs(value_or_tbc(d.coverage)) do table.insert(coverage, inline) end
  -- no-anchor: the heading has no id, so Quarto's anchor link would point
  -- to "#" and add a stray "Anchor" stop for keyboard users.
  return pandoc.Div({
    pandoc.Header(3, { title }, classes("unnumbered", "unlisted", "no-anchor")),
    pandoc.Para(value_or_tbc(d.tagline)),
    pandoc.Para(coverage),
    pandoc.Para({ status_badge(d) }),
  }, classes("dataset-card"))
end

-- A short entry on another page: the page gives its heading (anchored by
-- the record's id) and text; this adds coverage and status, the files, and
-- the citation.
local function entry(args, kwargs, meta)
  local d = page_dataset(args, meta)
  if d == nil then return pandoc.Blocks({}) end
  local line = { pandoc.Span({ pandoc.Str("Coverage:") }, classes("card-label")), pandoc.Space() }
  for _, inline in ipairs(value_or_tbc(d.coverage)) do table.insert(line, inline) end
  table.insert(line, pandoc.Space())
  table.insert(line, status_badge(d))
  local blocks = pandoc.Blocks({ pandoc.Para(line) })
  local files = {}
  for _, f in ipairs(d.files or {}) do
    if kind(f) ~= "archive" then table.insert(files, f) end
  end
  if #files > 0 then
    blocks:insert(file_list(files, false))
  else
    blocks:insert(pandoc.Para({ pandoc.Span({ pandoc.Str("Files " .. TBC:lower() .. ".") }, classes("tbc")) }))
  end
  blocks:insert(pandoc.Para({ pandoc.Span({ pandoc.Str("How to cite") }, classes("card-label")) }))
  blocks:insert(cite({ d.id }, kwargs, meta))
  return pandoc.Div(blocks, classes("dataset-entry"))
end

return {
  ["dataset-glance"] = glance,
  ["dataset-downloads"] = downloads,
  ["dataset-history"] = history,
  ["dataset-value"] = value,
  ["dataset-cite"] = cite,
  ["dataset-card"] = card,
  ["dataset-entry"] = entry,
}
