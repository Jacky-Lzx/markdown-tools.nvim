local M = {}

function M.lines(buf)
  return vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end

-- Exclude front matter, fenced/indented code and HTML comments without a parser dependency.
function M.scan(lines)
  local result = { headings = {}, excluded = {}, toc_markers = {} }
  local fence, front, comment, list_indent
  local used = {}
  for row, line in ipairs(lines) do
    if
      not front
      and not fence
      and not comment
      and (line == "<!-- markdown-tools:toc -->" or line == "<!-- /markdown-tools:toc -->")
    then
      result.toc_markers[row] = true
    end
    local indent = #(line:match("^%s*") or "")
    local item = M.item(line)
    local nested_item = item and list_indent and indent >= list_indent
    if not fence and not front and not comment then
      if item and (indent < 4 or nested_item) then
        list_indent = math.min(list_indent or math.huge, indent + #item.marker + #item.space)
      elseif vim.trim(line) ~= "" and list_indent and indent < list_indent then
        list_indent = nil
      end
    end
    local text = line:gsub("^%s*> ?", "")
    while text:match("^%s*>") do
      text = text:gsub("^%s*> ?", "")
    end
    if row == 1 and (text == "---" or text == "+++") then
      front = text
      result.excluded[row] = true
    elseif front then
      result.excluded[row] = true
      if text == front or (front == "---" and text == "...") then
        front = nil
      end
    elseif fence then
      result.excluded[row] = true
      local marker, tail = text:match("^ ? ? ?([`~]+)(.*)$")
      if
        marker
        and marker:sub(1, 1) == fence.char
        and not marker:find("[^" .. fence.char .. "]")
        and #marker >= fence.length
        and tail:match("^%s*$")
      then
        fence = nil
      end
    else
      local marker, tail = text:match("^ ? ? ?([`~]+)(.*)$")
      if
        marker
        and #marker >= 3
        and not marker:find("[^" .. marker:sub(1, 1) .. "]")
        and (marker:sub(1, 1) ~= "`" or not tail:find("`", 1, true))
      then
        fence = { char = marker:sub(1, 1), length = #marker }
        result.excluded[row] = true
      elseif comment or text:find("<!--", 1, true) then
        result.excluded[row] = true
        comment = not text:find("-->", 1, true)
      elseif (line:match("^    ") or line:match("^\t")) and not nested_item then
        result.excluded[row] = true
      else
        local hashes, title = line:match("^ ? ? ?(#+)%s+(.-)%s*$")
        if not hashes then
          hashes = line:match("^ ? ? ?(#+)%s*$")
          title = ""
        end
        local heading
        if hashes and #hashes <= 6 then
          title = title:gsub("%s+#+%s*$", "")
          heading = { row = row, last = row, level = #hashes, title = title }
        elseif row > 1 and not result.excluded[row - 1] and vim.trim(lines[row - 1]) ~= "" then
          local underline = line:match("^ ? ? ?(=+)%s*$") or line:match("^ ? ? ?(%-+)%s*$")
          local previous = result.headings[#result.headings]
          if
            underline
            and not (previous and previous.last == row - 1)
            and not M.item(lines[row - 1])
            and not lines[row - 1]:match("^%s*[>#]")
          then
            heading = {
              row = row - 1,
              last = row,
              level = underline:sub(1, 1) == "=" and 1 or 2,
              title = vim.trim(lines[row - 1]),
              setext = true,
            }
          end
        end
        if heading then
          local base = M.slug(heading.title)
          local slug, suffix = base, 0
          while used[slug] do
            suffix = suffix + 1
            slug = base .. "-" .. suffix
          end
          heading.slug, used[slug] = slug, true
          result.headings[#result.headings + 1] = heading
        end
      end
    end
  end
  return result
end

function M.slug(text)
  text = text:gsub("!%[([^%]]*)%]%([^)]*%)", "%1"):gsub("%[([^%]]*)%]%([^)]*%)", "%1")
  text = text:gsub("<[^>]*>", "")
  text = vim.fn.tolower(text)
  text = text:gsub("[%p]", function(char)
    return (char == "-" or char == "_") and char or ""
  end)
  return text:gsub("%s", "-")
end

function M.item(line)
  local prefix, rest = line:match("^(%s*>%s*)(.*)$")
  prefix, rest = prefix or "", rest or line
  while rest:match("^>%s*") do
    local quote, tail = rest:match("^(>%s*)(.*)$")
    prefix, rest = prefix .. quote, tail
  end
  local indent, marker, space, body = rest:match("^(%s*)([-+*])(%s+)(.*)$")
  local number, delimiter
  if not marker then
    indent, number, delimiter, space, body = rest:match("^(%s*)(%d+)([.)])(%s+)(.*)$")
    if number then
      marker = number .. delimiter
    end
  end
  if not marker then
    return
  end
  local state, content = body:match("^%[([ xX])%]%s+(.*)$")
  if not state then
    state = body:match("^%[([ xX])%]$")
    content = state and "" or nil
  end
  return {
    prefix = prefix .. indent,
    marker = marker,
    space = space,
    body = body,
    number = tonumber(number),
    delimiter = delimiter,
    state = state,
    content = content,
    start_col = #prefix + #indent,
  }
end

function M.current_heading(scan, row)
  local current
  for index, heading in ipairs(scan.headings) do
    if heading.row > row then
      break
    end
    current = index
  end
  return current
end

function M.jump(row, col)
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { row, col or 0 })
  vim.cmd("normal! zv")
end

function M.replace(lines)
  if not vim.bo.modifiable then
    error("Buffer is not modifiable")
  end
  if not vim.deep_equal(lines, M.lines()) then
    local before = M.lines()
    local first, old_last, new_last = 0, #before, #lines
    while first < math.min(old_last, new_last) and before[first + 1] == lines[first + 1] do
      first = first + 1
    end
    while old_last > first and new_last > first and before[old_last] == lines[new_last] do
      old_last, new_last = old_last - 1, new_last - 1
    end
    vim.api.nvim_buf_set_lines(0, first, old_last, false, vim.list_slice(lines, first + 1, new_last))
  end
end

return M
