-- Shortcodes that display dataset facts from data/datasets.yml.
--
--   {{< dataset-glance >}}      at-a-glance panel
--   {{< dataset-downloads >}}   download list for the current release,
--                               codebooks first
--   {{< dataset-archive >}}     files of earlier releases, by release date
--                               (Version history)
--   {{< dataset-cite >}}        citation box with a copy button
--   {{< dataset-card ID >}}     summary card linking to the dataset's page
--   {{< dataset-hub >}}         one table row per dataset (Download Data)
--
-- glance, downloads, archive, and cite use the ID given as their first
-- argument, or else the page's `dataset` metadata. Empty fields show "To be confirmed",
-- so nothing appears that the data file does not state.

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

local function page_href(d)
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
      { { pandoc.Plain(value_or_tbc(d[field[1]])) } },
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
      button = pandoc.Link({ pandoc.Str("Download") }, from_root(href), "",
        pandoc.Attr("", { "btn", "btn-primary", "btn-sm" }, { ["aria-label"] = "Download " .. stringify(label) }))
    end
    local text = { pandoc.Strong(label) }
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
    return pandoc.Div({ pandoc.Para({ pandoc.Span({ pandoc.Str("Files " .. TBC:lower() .. ".") }, classes("tbc")) }) },
      classes("downloads"))
  end
  return file_list(ordered, true)
end

local MONTHS = {
  January = "01", February = "02", March = "03", April = "04", May = "05", June = "06",
  July = "07", August = "08", September = "09", October = "10", November = "11", December = "12",
}

-- A superseded release's files are named vYYYY-MM_IMFMonitor_... after its
-- release date (Thomas, 20 October 2026). Warn when an archive entry's label
-- or href doesn't carry the prefix that matches its version.
local function check_archive_name(d, f, version)
  local month, year = version:match("^(%a+) (%d%d%d%d)$")
  local mm = month and MONTHS[month]
  local where = stringify(d.id) .. " in data/datasets.yml"
  if mm == nil then
    quarto.log.warning("imfmonitor: archive file version '" .. version .. "' for " .. where ..
      " is not a release date such as 'September 2017'")
    return
  end
  local prefix = "v" .. year .. "-" .. mm .. "_IMFMonitor_"
  for _, key in ipairs({ "label", "href" }) do
    local value = stringify(f[key] or "")
    if value ~= "" and not value:find(prefix, 1, true) then
      quarto.log.warning("imfmonitor: archive file " .. key .. " '" .. value .. "' for " .. where ..
        " should use the file name prefix " .. prefix)
    end
  end
end

-- Files of earlier releases, grouped under each release date in the order
-- they appear in datasets.yml. Nothing at all if there are none.
local function archive(args, kwargs, meta)
  local d = page_dataset(args, meta)
  if d == nil then return pandoc.Blocks({}) end
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
  for _, v in ipairs(versions) do
    blocks:insert(pandoc.Header(3, { pandoc.Str(v) }, classes("unnumbered", "unlisted")))
    blocks:insert(file_list(groups[v], false))
  end
  return blocks
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
  return pandoc.Div({
    pandoc.Header(3, { title }, classes("unnumbered", "unlisted")),
    pandoc.Para(value_or_tbc(d.tagline)),
    pandoc.Para(coverage),
    pandoc.Para({ status_badge(d) }),
  }, classes("dataset-card"))
end

local function hub(args, kwargs, meta)
  local function cell(content) return { pandoc.Plain(content) } end
  local headers = {
    cell({ pandoc.Str("Dataset") }),
    cell({ pandoc.Str("Coverage") }),
    cell({ pandoc.Str("Version") }),
    cell({ pandoc.Str("Status") }),
  }
  local rows = {}
  for _, d in ipairs(all_datasets()) do
    table.insert(rows, {
      cell({ pandoc.Link(inlines(d.name), page_href(d)) }),
      cell(value_or_tbc(d.coverage)),
      cell(value_or_tbc(d.version)),
      cell({ status_badge(d) }),
    })
  end
  local aligns = { pandoc.AlignDefault, pandoc.AlignDefault, pandoc.AlignDefault, pandoc.AlignDefault }
  local simple = pandoc.SimpleTable({}, aligns, { 0, 0, 0, 0 }, headers, rows)
  return pandoc.Div({ pandoc.utils.from_simple_table(simple) }, classes("dataset-hub"))
end

return {
  ["dataset-glance"] = glance,
  ["dataset-downloads"] = downloads,
  ["dataset-archive"] = archive,
  ["dataset-cite"] = cite,
  ["dataset-card"] = card,
  ["dataset-hub"] = hub,
}
