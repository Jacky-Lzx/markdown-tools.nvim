# markdown-tools.nvim

Markdown structural editing without a parser, server or vault.

## Features

- Edit tasks, lists, headings and tables.
- Follow Markdown and wiki links and maintain a table of contents.
- Choose your own physical keys for buffer-local commands and <Plug> endpoints.

## Requirements

Neovim **0.11+**. No runtime dependencies. Preview and export are optional callbacks supplied by your configuration.

## Installation

With lazy.nvim:

```lua
{
  "Jacky-Lzx/markdown-tools.nvim",
  main = "markdown_tools",
  opts = {},
}
```

Or put this repository and its required dependencies on `runtimepath`, then call:

```lua
require("markdown_tools").setup({})
```

## Usage

```vim
:MarkdownToolsToggleCheckbox
:MarkdownToolsOutline
:MarkdownToolsInfo
```

Commands attach to ordinary Markdown buffers. Physical keys remain your choice;
Insert-mode Enter and Tab keep their existing behavior.

## Documentation

- [Complete reference](doc/markdown-tools.txt) — `:help markdown-tools`.

## Development

Run from the repository root:

```sh
python3 tests/run.py unit --filter docs
python3 tests/run.py default
```

See [the test workflow](tests/README.md) for dependencies, optional suites and
retained failure evidence. Local development overrides belong in your package
manager configuration; public installation uses the repository above.

[License](LICENSE).
