local D = require("markdown_tools.document")
local M = {}

function M.toggle_checkbox(first, last)
  local lines = D.lines()
  local scan = D.scan(lines)
  first = first or vim.fn.line(".")
  for row = first, last or first do
    local line = lines[row]
    if line and not scan.excluded[row] and vim.trim(line) ~= "" then
      local item = D.item(line)
      if item then
        local body = item.state and ("[" .. (item.state == " " and "x" or " ") .. "] " .. item.content)
          or "[ ] " .. item.body
        lines[row] = item.prefix .. item.marker .. item.space .. body
      else
        local indent, text = line:match("^(%s*)(.*)$")
        lines[row] = indent .. "- [ ] " .. text
      end
    end
  end
  D.replace(lines)
end

function M.insert_item()
  local lines, row = D.lines(), vim.fn.line(".")
  local scan = D.scan(lines)
  local item = not scan.excluded[row] and D.item(lines[row])
  if not item then
    return false, "Cursor is not on a list item"
  end
  -- Insert a sibling after nested children and indented continuation lines.
  local after = row
  while lines[after + 1] and vim.trim(lines[after + 1]) ~= "" do
    local next_item = D.item(lines[after + 1])
    local indent = #(lines[after + 1]:match("^%s*") or "")
    if next_item and #next_item.prefix <= #item.prefix then
      break
    end
    if not next_item and indent <= #item.prefix then
      break
    end
    after = after + 1
  end
  local marker = item.number and (item.number + 1) .. item.delimiter or item.marker
  local text = item.prefix .. marker .. item.space .. (item.state and "[ ] " or "")
  table.insert(lines, after + 1, text)
  D.replace(lines)
  vim.api.nvim_win_set_cursor(0, { after + 1, #text })
  vim.cmd("startinsert!")
  return true
end

function M.renumber()
  local lines, row = D.lines(), vim.fn.line(".")
  local scan = D.scan(lines)
  local item = not scan.excluded[row] and D.item(lines[row])
  if not item or not item.number then
    return false, "Cursor is not on a numbered item"
  end
  local first, last = row, row
  local function belongs(index)
    local text = lines[index]
    if not text or scan.excluded[index] then
      return false
    end
    local other = D.item(text)
    if other then
      return #other.prefix > #item.prefix or (other.prefix == item.prefix and other.number ~= nil)
    end
    return vim.trim(text) ~= "" and #(text:match("^%s*") or "") > #item.prefix
  end
  while belongs(first - 1) do
    first = first - 1
  end
  while belongs(last + 1) do
    last = last + 1
  end
  local number
  for index = first, last do
    local other = D.item(lines[index])
    if other and other.prefix == item.prefix and other.number then
      number = number or other.number
      lines[index] = other.prefix .. number .. other.delimiter .. other.space .. other.body
      number = number + 1
    end
  end
  D.replace(lines)
  return true
end

function M.shift_heading(delta)
  local lines, row = D.lines(), vim.fn.line(".")
  local scan = D.scan(lines)
  local index = D.current_heading(scan, row)
  if not index or scan.excluded[row] then
    return false, "No current heading"
  end
  local heading, edits = scan.headings[index], {}
  for i = index, #scan.headings do
    local h = scan.headings[i]
    if i > index and h.level <= heading.level then
      break
    end
    if h.level + delta < 1 or h.level + delta > 6 then
      return false, "Heading levels must stay between 1 and 6"
    end
    edits[#edits + 1] = h
  end
  for i = #edits, 1, -1 do
    local h = edits[i]
    lines[h.row] = string.rep("#", h.level + delta) .. " " .. h.title
    if h.setext then
      table.remove(lines, h.last)
    end
  end
  D.replace(lines)
  return true
end

function M.heading(direction, count)
  local row, target = vim.fn.line("."), nil
  local headings = D.scan(D.lines()).headings
  if direction < 0 then
    local reversed = {}
    for i = #headings, 1, -1 do
      reversed[#reversed + 1] = headings[i]
    end
    headings = reversed
  end
  count = count or vim.v.count1
  for _, h in ipairs(headings) do
    if (h.row - row) * direction > 0 then
      target, count = h, count - 1
      if count == 0 then
        break
      end
    end
  end
  if target then
    D.jump(target.row)
  end
end

function M.outline()
  local buf, tick = vim.api.nvim_get_current_buf(), vim.api.nvim_buf_get_changedtick(0)
  local headings = D.scan(D.lines()).headings
  vim.ui.select(headings, {
    prompt = "Markdown headings",
    format_item = function(h)
      return string.rep("  ", h.level - 1) .. h.title .. "  :" .. h.row
    end,
  }, function(h)
    if h and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_changedtick(buf) == tick then
      vim.api.nvim_set_current_buf(buf)
      D.jump(h.row)
    end
  end)
end

function M.toc()
  local lines = D.lines()
  local scan = D.scan(lines)
  local first, last
  for row, line in ipairs(lines) do
    if scan.toc_markers[row] and line == "<!-- markdown-tools:toc -->" then
      if first then
        return false, "Multiple TOC regions"
      end
      first = row
    elseif scan.toc_markers[row] and line == "<!-- /markdown-tools:toc -->" then
      if last then
        return false, "Multiple TOC regions"
      end
      last = row
    end
  end
  if (first and not last) or (last and not first) or (first and last < first) then
    return false, "Unbalanced TOC markers"
  end
  local content, base = { "<!-- markdown-tools:toc -->" }, 6
  for _, h in ipairs(scan.headings) do
    if not first or h.row < first or h.row > last then
      base = math.min(base, h.level)
    end
  end
  for _, h in ipairs(scan.headings) do
    if not first or h.row < first or h.row > last then
      local title = h.title:gsub("([%[%]\\])", "\\%1")
      content[#content + 1] = string.rep("  ", h.level - base) .. "- [" .. title .. "](#" .. h.slug .. ")"
    end
  end
  content[#content + 1] = "<!-- /markdown-tools:toc -->"
  if first then
    for _ = first, last do
      table.remove(lines, first)
    end
  else
    first = vim.fn.line(".")
    if scan.excluded[first] then
      return false, "Cannot insert TOC in code or front matter"
    end
  end
  for i = #content, 1, -1 do
    table.insert(lines, first, content[i])
  end
  D.replace(lines)
  return true
end

return M
