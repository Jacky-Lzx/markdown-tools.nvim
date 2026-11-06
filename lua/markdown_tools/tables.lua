local D = require("markdown_tools.document")
local M = {}

-- Only unescaped pipes outside matching inline-code spans delimit cells.
function M.cells(line)
  local pipes, i = {}, 1
  while i <= #line do
    local char = line:sub(i, i)
    if char == "\\" then
      i = i + 2
    elseif char == "`" then
      local run = line:match("^`+", i)
      local close, search = nil, i + #run
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
      i = close and close + 1 or i + #run
    else
      if char == "|" then
        pipes[#pipes + 1] = i
      end
      i = i + 1
    end
  end
  if #pipes == 0 then
    return
  end
  local cells, bounds, start = {}, {}, 1
  for _, pipe in ipairs(pipes) do
    cells[#cells + 1], bounds[#bounds + 1] = vim.trim(line:sub(start, pipe - 1)), { start, pipe - 1 }
    start = pipe + 1
  end
  cells[#cells + 1], bounds[#bounds + 1] = vim.trim(line:sub(start)), { start, #line }
  if cells[#cells] == "" and line:sub(pipes[#pipes] + 1):match("^%s*$") then
    table.remove(cells)
    table.remove(bounds)
  end
  if cells[1] == "" and line:sub(1, pipes[1] - 1):match("^%s*$") then
    table.remove(cells, 1)
    table.remove(bounds, 1)
  end
  return cells, bounds
end

local function separator(cells)
  if not cells or #cells == 0 then
    return false
  end
  for _, cell in ipairs(cells) do
    if not cell:match("^:?-+:?$") then
      return false
    end
  end
  return true
end

function M.at()
  local lines, row = D.lines(), vim.fn.line(".")
  local scan = D.scan(lines)
  local function valid(r)
    return lines[r] and not scan.excluded[r] and M.cells(lines[r])
  end
  if not valid(row) then
    return
  end
  local first, last = row, row
  while valid(first - 1) do
    first = first - 1
  end
  while valid(last + 1) do
    last = last + 1
  end
  local rows, bounds = {}, {}
  for r = first, last do
    rows[#rows + 1], bounds[#bounds + 1] = M.cells(lines[r])
  end
  if #rows < 2 or not separator(rows[2]) or #rows[1] ~= #rows[2] then
    return
  end
  for _, cells in ipairs(rows) do
    if #cells ~= #rows[1] then
      return
    end
  end
  local col, selected = vim.fn.col("."), 1
  for index, bound in ipairs(bounds[row - first + 1]) do
    if col >= bound[1] then
      selected = index
    end
  end
  return {
    lines = lines,
    first = first,
    last = last,
    rows = rows,
    bounds = bounds,
    row = row - first + 1,
    col = selected,
    indent = lines[first]:match("^%s*"),
  }
end

local function render(table_data)
  local rows, widths = table_data.rows, {}
  for r, cells in ipairs(rows) do
    for col, cell in ipairs(cells) do
      widths[col] = math.max(widths[col] or 3, r == 2 and 3 or vim.fn.strdisplaywidth(cell))
    end
  end
  local output = {}
  for r, cells in ipairs(rows) do
    local values = {}
    for col, cell in ipairs(cells) do
      if r == 2 then
        local left, right = cell:sub(1, 1) == ":", cell:sub(-1) == ":"
        values[col] = (left and ":" or "")
          .. string.rep("-", math.max(3, widths[col] - (left and 1 or 0) - (right and 1 or 0)))
          .. (right and ":" or "")
        widths[col] = math.max(widths[col], #values[col])
      else
        values[col] = cell .. string.rep(" ", widths[col] - vim.fn.strdisplaywidth(cell))
      end
    end
    output[#output + 1] = table_data.indent .. "| " .. table.concat(values, " | ") .. " |"
  end
  -- Separator colon minimum widths may increase a column; render data again.
  for r, cells in ipairs(rows) do
    if r ~= 2 then
      local values = {}
      for col, cell in ipairs(cells) do
        values[col] = cell .. string.rep(" ", widths[col] - vim.fn.strdisplaywidth(cell))
      end
      output[r] = table_data.indent .. "| " .. table.concat(values, " | ") .. " |"
    end
  end
  local lines = table_data.lines
  for _ = table_data.first, table_data.last do
    table.remove(lines, table_data.first)
  end
  for i = #output, 1, -1 do
    table.insert(lines, table_data.first, output[i])
  end
  D.replace(lines)
end

function M.edit(action)
  local t = M.at()
  if not t then
    return false, "Cursor is not in a rectangular Markdown table"
  end
  if action == "insert_row" then
    local empty = {}
    for _ = 1, #t.rows[1] do
      empty[#empty + 1] = ""
    end
    local after = math.max(2, t.row)
    table.insert(t.rows, after + 1, empty)
  elseif action == "delete_row" then
    if t.row <= 2 then
      return false, "Cannot delete the table header or separator"
    end
    table.remove(t.rows, t.row)
  elseif action == "insert_column" then
    for r, cells in ipairs(t.rows) do
      table.insert(cells, t.col + 1, r == 2 and "---" or "")
    end
  elseif action == "delete_column" then
    if #t.rows[1] <= 1 then
      return false, "Cannot delete the last table column"
    end
    for _, cells in ipairs(t.rows) do
      table.remove(cells, t.col)
    end
  elseif action ~= "format" then
    error("Unknown table action: " .. tostring(action))
  end
  render(t)
  return true
end

function M.cell(direction, count)
  local t = M.at()
  if not t then
    return false, "Cursor is not in a Markdown table"
  end
  local positions, index = {}, nil
  for row, bounds in ipairs(t.bounds) do
    if row ~= 2 then
      for col, bound in ipairs(bounds) do
        positions[#positions + 1] = { row = t.first + row - 1, col = bound[1] - 1, text = t.rows[row][col] }
        if t.row == row and t.col == col then
          index = #positions
        end
      end
    end
  end
  index = index or (direction > 0 and #t.rows[1] or #t.rows[1] + 1)
  local target = positions[index + direction * (count or vim.v.count1)]
  if target then
    local line = t.lines[target.row]
    local col = target.col + #(line:sub(target.col + 1):match("^%s*") or "")
    D.jump(target.row, math.min(col, math.max(0, #line - 1)))
  end
  return true
end

return M
