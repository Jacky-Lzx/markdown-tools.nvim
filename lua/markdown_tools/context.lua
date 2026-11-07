local M = {}
local cached
local function scan(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if cached and cached.buf == buf and cached.tick == tick then
    return cached.ranges
  end
  local document = require("markdown_tools.document")
  local lines = document.lines(buf)
  local excluded = document.scan(lines).excluded
  local ranges, opening, code = {}, nil, nil
  for row, line in ipairs(lines) do
    if not excluded[row] then
      local col = 1
      while col <= #line do
        local char = line:sub(col, col)
        if char == "\\" then
          col = col + 2
        elseif char == "`" and not opening then
          local marker = line:sub(col):match("^`+")
          if code == #marker then
            code = nil
          elseif not code then
            code = #marker
          end
          col = col + #marker
        elseif char == "$" and not code then
          local marker = line:sub(col, col + 1) == "$$" and "$$" or "$"
          if opening and marker == opening.marker then
            ranges[#ranges + 1] = { opening.row, opening.col, row - 1, col - 1 }
            opening = nil
          elseif not opening then
            opening = { row = row - 1, col = col - 1 + #marker, marker = marker }
          end
          col = col + #marker
        else
          col = col + 1
        end
      end
      if opening and opening.marker == "$" then
        opening = nil
      end
    end
  end
  if opening then
    ranges[#ranges + 1] = { opening.row, opening.col, #lines, 0 }
  end
  cached = { buf = buf, tick = tick, ranges = ranges, excluded = excluded }
  return ranges
end

---Zero-based byte position; provide pos for a non-current buffer.
function M.in_math(opts)
  opts = opts or {}
  local buf = opts.bufnr
  if not buf or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_loaded(buf) then
    return false, "Buffer is not loaded"
  end
  local pos = opts.pos
  if not pos then
    if buf ~= vim.api.nvim_get_current_buf() then
      return false, "Provide pos for a non-current buffer"
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    pos = { cursor[1] - 1, cursor[2] }
  end
  local ranges = scan(buf)
  if cached.excluded[pos[1] + 1] then
    return false
  end
  for _, range in ipairs(ranges) do
    if
      (pos[1] > range[1] or pos[1] == range[1] and pos[2] >= range[2])
      and (pos[1] < range[3] or pos[1] == range[3] and pos[2] <= range[4])
    then
      return true
    end
  end
  return false
end
return M
