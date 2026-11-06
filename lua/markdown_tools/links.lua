local D = require("markdown_tools.document")
local M = {}

function M.decode(text)
  return (text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end
local function normalize(text)
  return vim.trim(text):gsub("%s+", " "):lower()
end

-- Byte-preserving mask: escaped syntax and matched inline code are not links.
function M.mask(line)
  local masked, index = line, 1
  while index <= #line do
    if line:sub(index, index) == "\\" then
      local length = math.min(2, #line - index + 1)
      masked = masked:sub(1, index - 1) .. string.rep(" ", length) .. masked:sub(index + length)
      index = index + length
    elseif line:sub(index, index) == "`" then
      local run, close = line:match("^`+", index), nil
      local search = index + #run
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
  return masked
end

local function destination(text)
  local first = #(text:match("^%s*") or "") + 1
  if text:sub(first, first) == "<" then
    local last = text:find(">", first + 1, true)
    if last then
      return text:sub(first + 1, last - 1), first + 1, last - 1
    end
    return
  end
  local depth, escape, last = 0, false, #text
  for index = first, #text do
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
      last = index - 1
      break
    end
  end
  return text:sub(first, last), first, last
end

-- One-based byte spans; reference occurrences point to their definition's target span.
function M.parse(lines)
  local scan, definitions, links = D.scan(lines), {}, {}
  for row, line in ipairs(lines) do
    if not scan.excluded[row] then
      local label, offset, rest = line:match("^ ? ? ?%[([^%]]+)%]:%s*()(.*)$")
      if label then
        local target, first, last = destination(rest)
        if target then
          definitions[normalize(label)] = {
            target = target,
            target_row = row,
            target_first = offset + first - 1,
            target_last = offset + last - 1,
          }
        end
      end
    end
  end
  for row, line in ipairs(lines) do
    if not scan.excluded[row] and not line:match("^ ? ? ?%[[^%]]+%]:") then
      local masked, occupied = M.mask(line), {}
      local function add(a, b, target, first, last, wiki, definition)
        if not target then
          return
        end
        local item = {
          row = row,
          first = a,
          last = b,
          target = target,
          wiki = wiki or false,
          target_row = row,
          target_first = first,
          target_last = last,
        }
        if definition then
          for k, v in pairs(definition) do
            item[k] = v
          end
          item.reference = true
        end
        if a > 1 and line:sub(a - 1, a - 1) == "!" then
          item.first = a - 1
          item.embed = true
        end
        links[#links + 1] = item
        for i = item.first, b do
          occupied[i] = true
        end
      end
      local index = 1
      while index <= #masked do
        local a, b, raw = masked:find("%[%[([^%]]+)%]%]", index)
        if not a then
          break
        end
        local target = raw:match("^([^|]+)")
        add(a, b, target, a + 2, a + 1 + #target, true)
        index = b + 1
      end
      index = 1
      while index <= #masked do
        local a, b, label = masked:find("%[([^%[%]]*)%]", index)
        if not a then
          break
        end
        if not occupied[a] then
          local next_char = masked:sub(b + 1, b + 1)
          if next_char == "(" then
            local depth, ending, escape, angle = 1, b + 2, false, false
            while ending <= #masked and depth > 0 do
              local char = line:sub(ending, ending)
              if escape then
                escape = false
              elseif char == "\\" then
                escape = true
              elseif char == "<" then
                angle = true
              elseif char == ">" then
                angle = false
              elseif not angle and char == "(" then
                depth = depth + 1
              elseif not angle and char == ")" then
                depth = depth - 1
              end
              ending = ending + 1
            end
            if depth == 0 then
              local target, first, last = destination(line:sub(b + 2, ending - 2))
              if target then
                add(a, ending - 1, target, b + 1 + first, b + 1 + last)
              end
            end
          elseif next_char == "[" then
            local start, ref = masked:match("()%[([^%]]*)%]", b + 1)
            local def = start == b + 1 and definitions[normalize(ref ~= "" and ref or label)]
            if def then
              add(a, b + #ref + 2, def.target, nil, nil, false, def)
            end
          else
            local def = definitions[normalize(label)]
            if def then
              add(a, b, def.target, nil, nil, false, def)
            end
          end
        end
        index = b + 1
      end
      for a, target, b in masked:gmatch("()<([^<>%s]+)>()") do
        if not occupied[a] and target:match("^%a[%w+.-]*:") then
          add(a, b - 1, target, a + 1, b - 2)
        end
      end
    end
  end
  table.sort(links, function(a, b)
    return a.row == b.row and a.first < b.first or a.row < b.row
  end)
  return links
end

function M.at()
  local row, col = vim.fn.line("."), vim.fn.col(".")
  for _, link in ipairs(M.parse(D.lines())) do
    if link.row == row and col >= link.first and col <= link.last then
      return link
    end
  end
end

function M.follow(handler)
  local link = M.at()
  if not link then
    return false, "No Markdown link under cursor"
  end
  if handler then
    local handled, err =
      handler(vim.deepcopy(link), { buf = vim.api.nvim_get_current_buf(), file = vim.api.nvim_buf_get_name(0) })
    if handled ~= nil then
      return handled, err
    end
  end
  local target = link.target:gsub("\\([%p])", "%1")
  if target:match("^%a[%w+.-]*:") and not target:match("^%a:[/\\]") then
    local _, err = vim.ui.open(target)
    return err == nil, err
  end
  local file, anchor = target:match("^([^#]*)#(.*)$")
  file, anchor = M.decode(file or target), anchor and M.decode(anchor)
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
    vim.cmd.edit(vim.fn.fnameescape(file))
  end
  if anchor and anchor ~= "" then
    for _, h in ipairs(D.scan(D.lines()).headings) do
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
