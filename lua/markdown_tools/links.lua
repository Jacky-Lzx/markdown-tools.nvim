local D = require("markdown_tools.document")
local M = {}

local function decode(text)
  return (text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end
local function normalize(text)
  return vim.trim(text):gsub("%s+", " "):lower()
end

local function destination(text)
  text = vim.trim(text)
  if text:sub(1, 1) == "<" then
    return text:match("^<(.-)>")
  end
  local depth, escape = 0, false
  for index = 1, #text do
    local char = text:sub(index, index)
    if escape then
      escape = false
    elseif char == "\\" then
      escape = true
    elseif char == "(" then
      depth = depth + 1
    elseif char == ")" then
      depth = depth - 1
    elseif char:match("%s") and depth == 0 then
      return text:sub(1, index - 1)
    end
  end
  return text
end

function M.at()
  local lines, row, col = D.lines(), vim.fn.line("."), vim.fn.col(".")
  local scan = D.scan(lines)
  if scan.excluded[row] then
    return
  end
  local line, candidates, definitions = lines[row], {}, {}
  for r, text in ipairs(lines) do
    if not scan.excluded[r] then
      local label, target = text:match("^ ? ? ?%[([^%]]+)%]:%s*(.+)$")
      if label then
        definitions[normalize(label)] = destination(target)
      end
    end
  end
  -- Hide inline-code spans while keeping byte positions stable.
  local masked, index = line, 1
  while index <= #line do
    if line:sub(index, index) == "\\" then
      masked = masked:sub(1, index - 1) .. "  " .. masked:sub(index + 2)
      index = index + 2
    elseif line:sub(index, index) == "`" then
      local run = line:match("^`+", index)
      local search, close = index + #run, nil
      while search <= #line do
        local a, b = line:find("`+", search)
        if not a then
          break
        end
        if b - a + 1 == #run then
          close = b
          break
        end
        search = b + 1
      end
      if close then
        masked = masked:sub(1, index - 1) .. string.rep(" ", close - index + 1) .. masked:sub(close + 1)
      end
      index = close and close + 1 or index + #run
    else
      index = index + 1
    end
  end
  local function add(a, b, target, wiki)
    if target then
      candidates[#candidates + 1] = { first = a, last = b, target = target, wiki = wiki }
    end
  end
  index = 1
  while index <= #masked do
    local a, b, target = masked:find("%[%[([^%]]+)%]%]", index)
    if not a then
      break
    end
    add(a, b, target:match("^([^|]+)"), true)
    index = b + 1
  end
  index = 1
  while index <= #masked do
    local a, b, label = masked:find("%[([^%[%]]*)%]", index)
    if not a then
      break
    end
    local next_char = masked:sub(b + 1, b + 1)
    if next_char == "(" then
      local depth, ending, escape = 1, b + 2, false
      while ending <= #masked and depth > 0 do
        local char = line:sub(ending, ending)
        if escape then
          escape = false
        elseif char == "\\" then
          escape = true
        elseif char == "(" then
          depth = depth + 1
        elseif char == ")" then
          depth = depth - 1
        end
        ending = ending + 1
      end
      if depth == 0 then
        add(a, ending - 1, destination(line:sub(b + 2, ending - 2)))
      end
    elseif next_char == "[" then
      local ending, ref = masked:match("()%[([^%]]*)%]", b + 1)
      if ending == b + 1 then
        add(a, b + #ref + 2, definitions[normalize(ref ~= "" and ref or label)])
      end
    elseif masked:sub(a - 1, a - 1) ~= "[" and next_char ~= "]" then
      add(a, b, definitions[normalize(label)])
    end
    index = b + 1
  end
  for a, target, b in masked:gmatch("()<([^<>%s]+)>()") do
    if target:match("^%a[%w+.-]*:") then
      add(a, b - 1, target)
    end
  end
  for _, link in ipairs(candidates) do
    if col >= link.first and col <= link.last then
      return link
    end
  end
end

function M.follow()
  local link = M.at()
  if not link then
    return false, "No Markdown link under cursor"
  end
  local target = link.target:gsub("\\([%p])", "%1")
  if target:match("^%a[%w+.-]*:") and not target:match("^%a:[/\\]") then
    local _, err = vim.ui.open(target)
    if err then
      return false, err
    end
    return true
  end
  local file, anchor = target:match("^([^#]*)#(.*)$")
  file = decode(file or target)
  anchor = anchor and decode(anchor)
  local buf = vim.api.nvim_get_current_buf()
  if file ~= "" then
    if not vim.startswith(file, "/") and not file:match("^%a:[/\\]") then
      local current = vim.api.nvim_buf_get_name(0)
      file = vim.fs.joinpath(current ~= "" and vim.fs.dirname(current) or vim.fn.getcwd(), file)
    end
    if link.wiki and not vim.uv.fs_stat(file) and vim.uv.fs_stat(file .. ".md") then
      file = file .. ".md"
    end
    file = vim.fs.normalize(file)
    local stat = vim.uv.fs_stat(file)
    if not stat or stat.type ~= "file" then
      return false, "Linked file does not exist: " .. file
    end
    -- Reuse the normal edit path, preserving modified-buffer protection and autocommands.
    vim.cmd.edit(vim.fn.fnameescape(file))
    buf = vim.api.nvim_get_current_buf()
  end
  if anchor and anchor ~= "" then
    for _, h in ipairs(D.scan(D.lines(buf)).headings) do
      if h.slug == anchor or (link.wiki and h.title == anchor) then
        D.jump(h.row)
        return true
      end
    end
    return false, "Heading not found: " .. anchor
  end
  return true
end

return M
