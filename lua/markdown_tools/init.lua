local M = {}
local api = vim.api
local defaults = { filetypes = { "markdown", "markdown.mdx" }, preview = false, export = false, link_handler = false }
local options = vim.deepcopy(defaults)
local attached, group = {}, nil
local function warn(message)
  vim.notify(message, vim.log.levels.WARN, { title = "Markdown tools" })
end
local function invoke(callback, ...)
  local ok, result, message = pcall(callback, ...)
  if not ok then
    warn(result)
  elseif result == false and message then
    warn(message)
  end
  return ok and result
end
local function edit(name, ...)
  return require("markdown_tools.edit")[name](...)
end

function M.toggle_checkbox(first, last)
  return edit("toggle_checkbox", first, last)
end
function M.insert_item()
  return edit("insert_item")
end
function M.renumber()
  return edit("renumber")
end
function M.promote_heading()
  return edit("shift_heading", -1)
end
function M.demote_heading()
  return edit("shift_heading", 1)
end
function M.next_heading(count)
  return edit("heading", 1, count)
end
function M.previous_heading(count)
  return edit("heading", -1, count)
end
function M.outline()
  return edit("outline")
end
function M.toc()
  return edit("toc")
end
function M.follow_link()
  return require("markdown_tools.links").follow(options.link_handler)
end
function M.format_table()
  return require("markdown_tools.tables").edit("format")
end
function M.insert_row()
  return require("markdown_tools.tables").edit("insert_row")
end
function M.delete_row()
  return require("markdown_tools.tables").edit("delete_row")
end
function M.insert_column()
  return require("markdown_tools.tables").edit("insert_column")
end
function M.delete_column()
  return require("markdown_tools.tables").edit("delete_column")
end
function M.next_cell(count)
  return require("markdown_tools.tables").cell(1, count)
end
function M.previous_cell(count)
  return require("markdown_tools.tables").cell(-1, count)
end
function M.headings(buf)
  return require("markdown_tools.document").scan(require("markdown_tools.document").lines(buf)).headings
end
function M.link_at()
  return require("markdown_tools.links").at()
end

local function integration(name)
  if not options[name] then
    return false, "Configure setup()." .. name .. " to use this integration"
  end
  return options[name]({ buf = api.nvim_get_current_buf(), file = api.nvim_buf_get_name(0), filetype = vim.bo.filetype })
end
function M.preview()
  return integration("preview")
end
function M.export()
  return integration("export")
end
function M.info()
  return { attached = vim.tbl_keys(attached), options = vim.deepcopy(options) }
end

local actions = {
  ToggleCheckbox = "toggle_checkbox",
  InsertItem = "insert_item",
  Renumber = "renumber",
  PromoteHeading = "promote_heading",
  DemoteHeading = "demote_heading",
  NextHeading = "next_heading",
  PreviousHeading = "previous_heading",
  Outline = "outline",
  Toc = "toc",
  FollowLink = "follow_link",
  FormatTable = "format_table",
  InsertRow = "insert_row",
  DeleteRow = "delete_row",
  InsertColumn = "insert_column",
  DeleteColumn = "delete_column",
  NextCell = "next_cell",
  PreviousCell = "previous_cell",
  Preview = "preview",
  Export = "export",
  Info = "info",
}

local function mapping(buf, lhs)
  for _, map in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
    if vim.keycode(map.lhs) == vim.keycode(lhs) then
      return map
    end
  end
end
local function detach(buf)
  local state = attached[buf]
  if not state then
    return
  end
  if api.nvim_buf_is_valid(buf) then
    local commands = api.nvim_buf_get_commands(buf, {})
    for name, command in pairs(state.commands) do
      if vim.deep_equal(commands[name], command) then
        pcall(api.nvim_buf_del_user_command, buf, name)
      end
    end
    for lhs, map in pairs(state.maps) do
      if vim.deep_equal(mapping(buf, lhs), map) then
        pcall(vim.keymap.del, "n", lhs, { buffer = buf })
      end
    end
  end
  attached[buf] = nil
end

local function attach(buf)
  if attached[buf] or vim.bo[buf].buftype ~= "" or not vim.tbl_contains(options.filetypes, vim.bo[buf].filetype) then
    return
  end
  local state = { commands = {}, maps = {} }
  local global = api.nvim_get_commands({})
  local local_commands = api.nvim_buf_get_commands(buf, {})
  -- Reject command collisions before making any changes.
  for suffix in pairs(actions) do
    local name = "MarkdownTools" .. suffix
    if global[name] or local_commands[name] then
      error("Markdown tools command already exists: " .. name)
    end
  end
  attached[buf] = state
  for suffix, method in pairs(actions) do
    local name, lhs = "MarkdownTools" .. suffix, "<Plug>(MarkdownTools" .. suffix .. ")"
    api.nvim_buf_create_user_command(buf, name, function(args)
      if method == "toggle_checkbox" then
        invoke(M[method], args.line1, args.line2)
      elseif method == "info" then
        vim.notify(vim.inspect(M.info()), vim.log.levels.INFO, { title = "Markdown tools", filetype = "lua" })
      else
        invoke(M[method])
      end
    end, { range = method == "toggle_checkbox" or nil, desc = "Markdown: " .. suffix, force = false })
    state.commands[name] = api.nvim_buf_get_commands(buf, {})[name]
    if not mapping(buf, lhs) then
      vim.keymap.set("n", lhs, function()
        if method == "info" then
          vim.notify(vim.inspect(M.info()), vim.log.levels.INFO, { title = "Markdown tools", filetype = "lua" })
        else
          invoke(M[method])
        end
      end, { buffer = buf, silent = true, desc = "Markdown: " .. suffix })
      state.maps[lhs] = mapping(buf, lhs)
    end
  end
end

function M.dispose()
  if group then
    pcall(api.nvim_del_augroup_by_id, group)
    group = nil
  end
  for _, buf in ipairs(vim.tbl_keys(attached)) do
    detach(buf)
  end
end

function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("Markdown tools setup expects a table")
  end
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if type(config.filetypes) ~= "table" or not vim.islist(config.filetypes) then
    error("filetypes must be a list")
  end
  for _, ft in ipairs(config.filetypes) do
    if type(ft) ~= "string" then
      error("filetypes must contain strings")
    end
  end
  for _, name in ipairs({ "preview", "export", "link_handler" }) do
    if config[name] ~= false and type(config[name]) ~= "function" then
      error(name .. " must be false or a function")
    end
  end
  M.dispose()
  options = config
  group = api.nvim_create_augroup("MarkdownTools", { clear = true })
  api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(event)
      detach(event.buf)
      invoke(attach, event.buf)
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      attached[event.buf] = nil
    end,
  })
  for _, buf in ipairs(api.nvim_list_bufs()) do
    invoke(attach, buf)
  end
  return M
end

return M
