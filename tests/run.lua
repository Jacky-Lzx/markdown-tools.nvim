vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local tools = require("markdown_tools")
local D = require("markdown_tools.document")
local T = require("markdown_tools.tables")
local count = 0
local function equal(actual, expected)
  count = count + 1
  assert(vim.deep_equal(actual, expected), vim.inspect({ actual = actual, expected = expected }))
end
local function buffer(lines, row, col, ft)
  vim.cmd("enew!")
  vim.bo.filetype = ft or "markdown"
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  api.nvim_win_set_cursor(0, { row or 1, col or 0 })
end
local function lines()
  return D.lines()
end

assert(not package.loaded["markdown_tools.edit"])
tools.setup()
equal(vim.fn.exists(":MarkdownToolsOutline"), 0)
buffer({ "- [ ] work", "- [X] done", "- plain", "paragraph", "```md", "- [ ] code", "```" })
local cr, tab = vim.fn.maparg("<CR>", "i"), vim.fn.maparg("<Tab>", "i")
equal(vim.fn.exists(":MarkdownToolsOutline"), 2)
vim.cmd("1,7MarkdownToolsToggleCheckbox")
equal(lines(), { "- [x] work", "- [ ] done", "- [ ] plain", "- [ ] paragraph", "```md", "- [ ] code", "```" })
equal(vim.fn.maparg("<CR>", "i"), cr)
equal(vim.fn.maparg("<Tab>", "i"), tab)

buffer({ "3. first", "  - nested", "9. second", "22. third", "", "1. separate" }, 3)
assert(tools.renumber())
equal(lines(), { "3. first", "  - nested", "4. second", "5. third", "", "1. separate" })
buffer({ "3) [x] task", "  - child", "4) later" })
assert(tools.insert_item())
vim.cmd.stopinsert()
equal(lines(), { "3) [x] task", "  - child", "4) [ ] ", "4) later" })

buffer({
  "---",
  "title: hidden",
  "---",
  "# Intro",
  "## Child",
  "### Deep",
  "# Next",
  "```",
  "# code",
  "```",
  "Title",
  "===",
  "# Intro",
  "    # hidden",
  "<!--",
  "# hidden",
  "-->",
}, 5)
equal(
  vim.tbl_map(function(h)
    return { h.title, h.level, h.slug }
  end, tools.headings()),
  {
    { "Intro", 1, "intro" },
    { "Child", 2, "child" },
    { "Deep", 3, "deep" },
    { "Next", 1, "next" },
    { "Title", 1, "title" },
    { "Intro", 1, "intro-1" },
  }
)
assert(tools.demote_heading())
equal(lines()[5], "### Child")
equal(lines()[6], "#### Deep")
equal(lines()[7], "# Next")
tools.next_heading(2)
equal(vim.fn.line("."), 7)
tools.previous_heading()
equal(vim.fn.line("."), 6)
buffer({ "# Top", "###### Limit" })
local ok = tools.demote_heading()
equal(ok, false)
equal(lines(), { "# Top", "###### Limit" })
buffer({ "Title", "===", "Child", "---", "# End" })
assert(tools.demote_heading())
equal(lines(), { "## Title", "### Child", "# End" })
buffer({ "", "# 中文标题", "## Same", "## Same", "```", "# Hidden", "```" })
assert(tools.toc())
local toc = lines()
assert(table.concat(toc, "\n"):find("same%-1"))
assert(tools.toc())
equal(lines(), toc)
buffer({ "<!-- markdown-tools:toc -->", "# Missing end" })
equal(tools.toc(), false)

buffer({ "| 名字 | Value |", "| :--- | ---: |", "| 中文 | `a|b` |", "| x | a\\|b |" }, 3, 15)
assert(tools.format_table())
equal(lines(), { "| 名字 | Value |", "| :--- | ----: |", "| 中文 | `a|b` |", "| x    | a\\|b  |" })
api.nvim_win_set_cursor(0, { 1, 2 })
tools.next_cell()
equal(vim.fn.line("."), 1)
tools.next_cell()
equal(vim.fn.line("."), 3)
assert(tools.insert_row())
equal(#lines(), 5)
assert(tools.insert_column())
equal(#T.cells(lines()[1]), 3)
assert(tools.delete_column())
equal(#T.cells(lines()[1]), 2)
api.nvim_win_set_cursor(0, { 1, 2 })
equal(tools.delete_row(), false)
api.nvim_win_set_cursor(0, { 4, 2 })
assert(tools.delete_row())
equal(#lines(), 4)
buffer({ "```", "| a | b |", "| - | - |", "```" }, 2)
equal(tools.format_table(), false)
buffer({ "| a | b |", "| - | - |", "| too few |" })
equal(tools.format_table(), false)

local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
vim.fn.writefile({ "# Target", "## A heading" }, temp .. "/a file.md")
buffer({ "[target](a%20file.md#a-heading)" }, 1, 4)
api.nvim_buf_set_name(0, temp .. "/source.md")
vim.bo.modified = false
assert(tools.follow_link())
equal(vim.fn.line("."), 2)
equal(vim.fn.fnamemodify(api.nvim_buf_get_name(0), ":t"), "a file.md")
buffer({
  "# Here",
  "[here](#here)",
  "[ref][key]",
  '[key]: <a file.md> "title"',
  "`[hidden](#here)`",
  "[[a file#A heading|alias]]",
}, 2, 3)
equal(tools.link_at().target, "#here")
assert(tools.follow_link())
equal(vim.fn.line("."), 1)
api.nvim_win_set_cursor(0, { 3, 3 })
equal(tools.link_at().target, "a file.md")
api.nvim_win_set_cursor(0, { 5, 5 })
equal(tools.link_at(), nil)
api.nvim_win_set_cursor(0, { 6, 5 })
equal(tools.link_at().target, "a file#A heading")
buffer({ '[nested](file(a).md "title")', "<https://example.com>", "\\[hidden](x)", "[missing](no-such-file)" }, 1, 4)
equal(tools.link_at().target, "file(a).md")
api.nvim_win_set_cursor(0, { 2, 5 })
equal(tools.link_at().target, "https://example.com")
api.nvim_win_set_cursor(0, { 3, 5 })
equal(tools.link_at(), nil)
api.nvim_win_set_cursor(0, { 4, 5 })
equal(tools.follow_link(), false)

-- Shared link spans support vault indexing and lossless reference rewrites.
local link_lines = {
  '![img](<a file.png> "caption") [[note#Heading|Label]]',
  "[a][ref]",
  '[ref]: note.md#anchor "title"',
  "`[[skip]]`",
}
local parsed = require("markdown_tools.links").parse(link_lines)
equal(#parsed, 3)
for _, link in ipairs(parsed) do
  equal(link_lines[link.target_row]:sub(link.target_first, link.target_last), link.target)
end
equal(parsed[1].embed, true)
equal(parsed[3].target_row, 3)
buffer({ "[target](#here)", "# Here" }, 1, 3)
local delegated
tools.setup({
  link_handler = function(link, ctx)
    delegated = { link.target, ctx.buf }
    return true
  end,
})
assert(tools.follow_link())
equal(delegated, { "#here", api.nvim_get_current_buf() })
equal(vim.fn.line("."), 1)
tools.setup({
  link_handler = function()
    return nil
  end,
})
assert(tools.follow_link())
equal(vim.fn.line("."), 2)
tools.setup()

-- Protected TOC examples, nested tasks, and edits preserving unrelated marks.
buffer({ "```md", "<!-- markdown-tools:toc -->", "example", "<!-- /markdown-tools:toc -->", "```", "", "# Heading" }, 6)
assert(tools.toc())
equal(lines()[3], "example")
assert(table.concat(lines(), "\n"):find("#heading", 1, true))
buffer({ "- [ ] outer", "    - [ ] nested", "- [ ]" })
tools.toggle_checkbox(1, 3)
equal(lines(), { "- [x] outer", "    - [x] nested", "- [x] " })
buffer({ "    - [ ] code", "", "- [ ] real" })
tools.toggle_checkbox(1, 3)
equal(lines(), { "    - [ ] code", "", "- [x] real" })
local ns = api.nvim_create_namespace("markdown-tools-test")
local mark = api.nvim_buf_set_extmark(0, ns, 0, 1, {})
tools.toggle_checkbox(3, 3)
equal(api.nvim_buf_get_extmark_by_id(0, ns, mark, {}), { 0, 1 })

-- Lifecycle: caller options, repeated setup, user ownership, filetype isolation.
local options = {
  filetypes = { "markdown" },
  preview = function(ctx)
    return ctx.filetype
  end,
}
tools.setup(options)
options.filetypes[1] = "lua"
equal(tools.preview(), "markdown")
local before = #api.nvim_get_autocmds({ group = "MarkdownTools" })
tools.setup()
equal(#api.nvim_get_autocmds({ group = "MarkdownTools" }), before)
equal(pcall(tools.setup, { preview = true }), false)
equal(vim.fn.exists(":MarkdownToolsOutline"), 2)
api.nvim_buf_create_user_command(0, "MarkdownToolsOutline", function() end, {})
vim.keymap.set("n", "<Plug>(MarkdownToolsOutline)", "<Nop>", { buffer = true })
tools.dispose()
equal(vim.fn.exists(":MarkdownToolsOutline"), 2)
equal(vim.fn.maparg("<Plug>(MarkdownToolsOutline)", "n"), "<Nop>")
equal(vim.fn.exists(":MarkdownToolsToggleCheckbox"), 0)
api.nvim_buf_del_user_command(0, "MarkdownToolsOutline")
vim.keymap.del("n", "<Plug>(MarkdownToolsOutline)", { buffer = true })
tools.setup()
vim.bo.filetype = "lua"
equal(vim.fn.exists(":MarkdownToolsOutline"), 0)
vim.bo.filetype = "markdown"
equal(vim.fn.exists(":MarkdownToolsOutline"), 2)
local select = vim.ui.select
vim.ui.select = function(_, _, callback)
  api.nvim_buf_set_lines(0, 0, 0, false, { "# Changed" })
  callback({ row = 99 })
end
assert(pcall(tools.outline))
vim.ui.select = select
vim.fn.delete(temp, "rf")

buffer({ "$x$ and `$code$` and \\$escaped", "```tex", "$hidden$", "```", "$$", "display", "$$" })
equal(tools.in_math({ pos = { 0, 1 } }), true)
equal(tools.in_math({ pos = { 0, 5 } }), false)
equal(tools.in_math({ pos = { 0, 12 } }), false)
equal(tools.in_math({ pos = { 2, 2 } }), false)
equal(tools.in_math({ pos = { 5, 2 } }), true)
api.nvim_buf_set_lines(0, 0, -1, false, { "plain" })
equal(tools.in_math({ pos = { 0, 1 } }), false)
local other = api.nvim_create_buf(false, true)
api.nvim_buf_set_lines(other, 0, -1, false, { "$y$" })
equal(tools.in_math({ bufnr = other, pos = { 0, 1 } }), true)
equal(tools.in_math({ bufnr = other }), false)
api.nvim_buf_delete(other, { force = true })

print("PASS markdown-tools: " .. count .. " assertions")
vim.cmd("qa!")
