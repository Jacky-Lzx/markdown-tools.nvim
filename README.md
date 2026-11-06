# markdown-tools.nvim

Dependency-free Markdown editing for Neovim 0.11+. Configuration owns physical
keys; this plugin owns structural edits, buffer commands and `<Plug>` endpoints.
Tree-sitter, a language server and a vault are not required.

```lua
require('markdown_tools').setup({
  filetypes = { 'markdown', 'markdown.mdx' },
  -- Optional adapters, called only by explicit commands:
  preview = function(ctx) require('peek').open() end,
  export = function(ctx) -- delegate ctx.file to your task runner
  end,
})
vim.keymap.set('n', '<localleader>Mx', '<Plug>(MarkdownToolsToggleCheckbox)')
```

Add this directory to `runtimepath` using your plugin manager. `setup()` attaches
existing ordinary Markdown buffers and future FileType events. No default user
keys, Insert-mode Enter, Tab, renderer, opener override or global options are
installed. The adapters receive `{buf, file, filetype}`. They are disabled by
default; optional plugins load only when an adapter invokes them.

## Commands and API

Commands are buffer-local and start with `MarkdownTools`. Normal-mode `<Plug>`
endpoints use the full command name, e.g. `<Plug>(MarkdownToolsNextHeading)`.
Lua functions use snake_case names, e.g. `next_heading(count)`.

| Command suffix | Behavior |
| --- | --- |
| `ToggleCheckbox` | Toggle existing tasks, add a checkbox to a list item, or turn text into a task. Accepts an Ex line range. |
| `InsertItem` | Insert a sibling after the current item's indented children, retain bullet/number/quote prefix, reset checkbox, enter Insert mode. |
| `Renumber` | Renumber the current contiguous numbered list at its indentation, retaining the first number and nested items. |
| `NextHeading` / `PreviousHeading` | Move by headings; Normal `<Plug>` endpoints honor counts and set jump history. |
| `PromoteHeading` / `DemoteHeading` | Change the enclosing heading and descendants by one level; reject the entire edit outside levels 1–6. Setext headings become ATX. |
| `Outline` | Select a heading through `vim.ui.select`. |
| `Toc` | Insert a TOC before the cursor, or refresh the existing marked TOC. Duplicate headings get distinct anchors. |
| `FollowLink` | Follow the Markdown/wiki link at the cursor, including local file anchors, reference links and URI autolinks. |
| `FormatTable` | Align a rectangular pipe table by display width, preserving colon alignment. |
| `InsertRow` / `DeleteRow` | Add a body row after the current row, or delete a body row. |
| `InsertColumn` / `DeleteColumn` | Add a column after the current cell, or delete a column (retain at least one). |
| `NextCell` / `PreviousCell` | Move through existing cells with counts, skipping the separator. |
| `Preview` / `Export` | Invoke the configured adapter. |
| `Info` | Inspect attached buffers and options. |

Lua also exposes `headings(buf?)`, `link_at()`, `setup(opts?)` and `dispose()`.
Edits return `false, reason` when their target is missing or invalid; command
wrappers report the reason through `vim.notify`. A structural edit is one undo
step and only replaces the changed span. Navigation preserves folds and jump
history. It does not create missing link targets or renumber after insertion;
run `Renumber` when you want to normalize a list.

For Visual task toggling, bind an explicit line range:

```lua
vim.keymap.set('x', '<localleader>Mx', ":<C-u>'<,'>MarkdownToolsToggleCheckbox<CR>")
```

TOC regions use `<!-- markdown-tools:toc -->` and
`<!-- /markdown-tools:toc -->`; malformed or multiple regions are rejected.
Plain ATX/Setext headings use GitHub-style lowercase anchors, preserve Unicode,
remove punctuation and suffix duplicates. Existing custom HTML IDs are not used.

The lightweight scanner supports ordinary Markdown documents: fenced/indented
code, front matter and HTML comments are excluded from edits. It is not a full
CommonMark/MDX parser. Headings inside lists/quotes, multiline link labels,
multiline reference definitions, raw HTML/JSX blocks, and vault-wide wiki-link
search are outside its scope. Wiki paths resolve relative to the current file;
Obsidian remains responsible for vault behavior. Table cells may contain escaped
pipes or matched backtick code spans; ragged tables are rejected without edits.
Image display/insertion, snippets, pairs, LSP, formatting and rendering stay in
their owning plugins.

Repeated setup replaces owned registrations. Invalid options leave the running
setup intact; disposal and filetype changes remove only unchanged owned commands
and mappings, preserving later user replacements. Physical user mappings belong
to your configuration and should be buffer-local.

## Development

```sh
stylua --check lua tests
TMPDIR=/private/tmp nvim --clean --headless -i NONE -l tests/run.lua
```
