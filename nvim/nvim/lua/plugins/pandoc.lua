-- Markdown -> PDF via pandoc.
--   `,ll` build the current file          `,lv` view its PDF
--   `,lb` build the whole course into one PDF, with a table of contents
--   `,lB` view the course PDF
-- Saving rebuilds whichever of the two PDFs already exist.
--
-- A course is the nearest ancestor directory containing `lectures/`; its PDF
-- is named after it, e.g. `statistics/statistics.pdf`, and its title comes from
-- an optional `course.yaml` beside it. A `pandoc.yaml` found by walking up is
-- passed as a defaults file so a notes tree shares one style.

local function pdf_path() return vim.fn.expand "%:p:r" .. ".pdf" end

local viewers = {
  { path = "/Applications/Skim.app", cmd = { "open", "-a", "Skim" } },
  { path = "/opt/homebrew/bin/zathura", cmd = { "zathura" } },
  { path = "/System/Applications/Preview.app", cmd = { "open", "-a", "Preview" } },
}

local function viewer_cmd()
  for _, viewer in ipairs(viewers) do
    if vim.uv.fs_stat(viewer.path) then return viewer.cmd end
  end
  return { "open" }
end

local function defaults_file(dir) return vim.fs.find("pandoc.yaml", { path = dir, upward = true, type = "file" })[1] end

local function course_root(dir)
  local lectures = vim.fs.find("lectures", { path = dir, upward = true, type = "directory" })[1]
  return lectures and vim.fs.dirname(lectures) or nil
end

local function course_pdf(root) return root .. "/" .. vim.fs.basename(root) .. ".pdf" end

local function open_pdf(pdf)
  if vim.fn.filereadable(pdf) == 0 then return vim.notify("No PDF yet - build it first", vim.log.levels.WARN) end
  local cmd = vim.deepcopy(viewer_cmd())
  table.insert(cmd, pdf)
  vim.system(cmd)
end

local function run(cmd, pdf, open_after)
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then return vim.notify("pandoc failed:\n" .. (result.stderr or ""), vim.log.levels.ERROR) end
      vim.notify("pandoc: " .. vim.fs.basename(pdf), vim.log.levels.INFO)
      if open_after then open_pdf(pdf) end
    end)
  end)
end

local function pandoc_cmd(inputs, dir, pdf, extra)
  local cmd = { "pandoc" }
  vim.list_extend(cmd, inputs)

  local resources = { dir, dir .. "/figures" }
  local defaults = defaults_file(dir)
  if defaults then
    vim.list_extend(cmd, { "--defaults", defaults })
    table.insert(resources, vim.fs.dirname(defaults))
  end

  vim.list_extend(cmd, extra or {})
  vim.list_extend(cmd, { "--resource-path=" .. table.concat(resources, ":"), "-o", pdf })
  return cmd
end

local function build_file(open_after)
  vim.cmd "silent! write"
  local dir = vim.fn.expand "%:p:h"
  local pdf = pdf_path()
  run(pandoc_cmd({ vim.fn.expand "%:p" }, dir, pdf, nil), pdf, open_after)
end

-- Per-lecture YAML blocks would otherwise leak into the merged document (the
-- last block wins), so the course build appends its own block as the final
-- input: `course.yaml` if present, else a title from the directory name.
local function course_meta_input(root, title)
  local custom = root .. "/course.yaml"
  local body = vim.fn.filereadable(custom) == 1 and table.concat(vim.fn.readfile(custom), "\n")
    or ('title: "%s"\nsubtitle: ""\ndate: ""'):format(title)

  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.split("---\n" .. body .. "\n---", "\n"), tmp)
  return tmp
end

local function build_course(open_after)
  vim.cmd "silent! write"

  local root = course_root(vim.fn.expand "%:p:h")
  if not root then return vim.notify("No course root (no lectures/ above this file)", vim.log.levels.WARN) end

  local inputs = vim.fn.glob(root .. "/lectures/*.md", false, true)
  if #inputs == 0 then return vim.notify("No markdown files in " .. root .. "/lectures", vim.log.levels.WARN) end
  table.sort(inputs)

  local name = vim.fs.basename(root)
  table.insert(inputs, course_meta_input(root, name:sub(1, 1):upper() .. name:sub(2)))

  local pdf = course_pdf(root)
  run(pandoc_cmd(inputs, root, pdf, { "--toc" }), pdf, open_after)
end

local function rebuild_existing()
  local dir = vim.fn.expand "%:p:h"
  if vim.fn.filereadable(pdf_path()) == 1 then build_file(false) end

  local root = course_root(dir)
  if root and vim.fn.filereadable(course_pdf(root)) == 1 then build_course(false) end
end

local function set_mappings(buf)
  local map = function(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc }) end
  map("<LocalLeader>ll", function() build_file(true) end, "Pandoc: build this file")
  map("<LocalLeader>lv", function() open_pdf(pdf_path()) end, "Pandoc: view this file's PDF")
  map("<LocalLeader>lb", function() build_course(true) end, "Pandoc: build whole course")
  map("<LocalLeader>lB", function()
    local root = course_root(vim.fn.expand "%:p:h")
    if root then open_pdf(course_pdf(root)) end
  end, "Pandoc: view course PDF")
end

---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = {
      autocmds = {
        pandoc_markdown = {
          {
            event = "FileType",
            pattern = "markdown",
            desc = "Pandoc build/view mappings for markdown buffers",
            callback = function(args) set_mappings(args.buf) end,
          },
          {
            event = "BufWritePost",
            pattern = "*.md",
            desc = "Rebuild existing PDFs on save",
            callback = rebuild_existing,
          },
        },
      },
    },
  },
}
