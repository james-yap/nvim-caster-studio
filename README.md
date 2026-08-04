# nvim-caster-studio

A dependency-free Neovim plugin that serves a live, transparent project-tree overlay for OBS. The focused file follows Neovim buffer changes. Long jumps animate through the intervening rows with a Dock-style magnification trail.

## Install

For local development with `lazy.nvim`:

```lua
{
  dir = "/Users/james/GitHub/nvim-caster-studio",
  config = function()
    require("caster").setup()
  end,
}
```

The plugin only needs Neovim. There is no Node process or separate server to install.

## Start a casting session

From Neovim:

```vim
:CasterStart
```

The default browser-source URL is:

```text
http://127.0.0.1:8765/
```

Add that URL to OBS as a **Browser** source. The panel fills the source height and stays flush with its left edge. Drag its right-edge handle in browser interaction mode to adjust the width; the choice is saved in browser storage. Taller browser sources automatically show more tree rows and reduce pruning.

`:CasterStart` uses Neovim's current working directory. To cast a different root:

```vim
:CasterStart /absolute/path/to/project
```

Commands:

- `:CasterStart [root]` — start the local overlay server.
- `:CasterStop` — stop the server and disconnect the browser source.
- `:CasterRefresh` — rescan and publish the tree immediately.
- `:CasterUrl` — show the current browser-source URL.

## Configuration

```lua
require("caster").setup({
  host = "127.0.0.1",
  port = 8765,
  root = nil,              -- string, function returning a path, or current cwd
  opacity = 0.8,           -- panel background opacity, from 0 (clear) to 1 (solid)
  font_size = nil,         -- overlay text size in pixels; nil uses the responsive default
  max_entries = 32,        -- fallback rows for API clients without a viewport size
  max_scan_entries = 5000, -- hard bound for filesystem traversal
  max_depth = 8,
  show_hidden = false,
  respect_gitignore = true,
  open_browser = false,
  ignore = {
    [".git"] = true,
    ["node_modules"] = true,
    ["dist"] = true,
    ["build"] = true,
    ["target"] = true,
  },
})
```

Configuration is merged with the defaults. Set a default ignored name to `false` to include it.

## Behavior

- `BufEnter`, `BufWinEnter`, and `DirChanged` publish a fresh state over Server-Sent Events.
- Directories sort before files, then alphabetically, like a polished `tree` view.
- Large projects use broot-style breadth-first filling: shallow branches are represented before deeper traversal.
- Partially represented branches use local `N unlisted` pruning rows or a directory ellipsis, keeping every rendered row inside the viewport.
- Git repositories use Git's own ignore matcher, including nested `.gitignore` files, negations, repository excludes, and global excludes. Patterns apply regardless of index status, matching broot's filesystem view.
- Transient interfaces such as Telescope prompts retain the last normal file highlight until a file is selected.
- The server binds to localhost by default and exposes only read-only `GET` endpoints.

## Verify

```sh
nvim --headless -u NONE -l tests/run.lua
```
