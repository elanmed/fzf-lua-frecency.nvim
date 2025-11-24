# fzf-lua-frecency.nvim

A frecency-based file picker for [fzf-lua](https://github.com/ibhagwan/fzf-lua) that ranks files based on how frequently and recently they're accessed.

![demo](https://elanmed.dev/nvim-plugins/fzf-lua-frecency.png)

Implements a [variant](https://wiki.mozilla.org/User:Jesse/NewFrecency) of Mozilla's frecency algorithm.

## Example Usage

### All frecency-ranked files: a scored version of `oldfiles`

```lua
require('fzf-lua-frecency').frecency()
```
```vimscript
:FzfLua frecency
```

### A smarter file picker: all files in the `cwd` with frecency-scored files listed first

```lua
require('fzf-lua-frecency').frecency({
    cwd_only = true,     
})
```
```vimscript
:FzfLua frecency cwd_only=true
```

## API

### `frecency`

```lua
--- @class FrecencyOpts
--- @field debug boolean
--- @field db_dir string
--- @field all_files boolean
--- @field stat_file boolean
--- @field display_score boolean
--- @field [string] any any fzf-lua option

--- @param opts? FrecencyOpts
require('fzf-lua-frecency').frecency()
require('fzf-lua-frecency').frecency({
   -- any fzf-lua option
   -- ...
   -- defaults:
    debug = false,
    db_dir = vim.fs.joinpath(vim.fn.stdpath "data", "fzf-lua-frecency")),
    -- Display files from the cwd only
    cwd_only = false,     
    -- Populate non-scored files in cwd? 
    -- defaults to `true` if `cwd_only=true`, else `false`
    all_files = nil,      
    -- Test for a scored file's existence in the file system before displaying it in the picker
    stat_file = true,     
    -- Prefix the fzf entry with its frecency score
    display_score = true,
})
```

### `setup`

`setup` does a few things:
1. Registers `fzf-lua-frecency` as an `fzf-lua` extension. This extends the `FzfLua` command to enable: `:FzfLua frecency ...`
2. Creates an autocommand to update a file's score on `BufWinEnter`
3. Adds an `fzf-lua` action (`ctrl-x`) to remove a file's frecency score

`setup` can be called explicitly if you wish to pass along any frecency options to the `ctrl-x` action or the autocommand. 
Otherwise, `setup` will be called automatically with the default options the first time `frecency` is called.

> [!NOTE]
> In the case when `setup` is not explicitly called, the `opts` passed to the first `frecency` call are _not_ passed 
along to `setup`. This is intentional - different remaps that call `frecency` may pass different options from one another,
and `fzf-lua-frecency` doesn't want to assume that a `frecency` invocation's options are intended for `setup` because 
it came first.

```lua
--- @class SetupOpts
--- @field debug boolean
--- @field db_dir string
--- @field stat_file boolean
--- @field [string] any any fzf-lua option

--- @param opts? SetupOpts
require('fzf-lua-frecency').setup({
   -- any fzf-lua option
   -- ...
   -- defaults:
    debug = false,
    db_dir = vim.fs.joinpath(vim.fn.stdpath "data", "fzf-lua-frecency"),
    -- Display files from the cwd only
    stat_file = true,
})
```

### `clear_db`

```lua
--- @class ClearDbOpts
--- @field db_dir? string

--- @param opts? ClearDbOpts
require('fzf-lua-frecency').clear_db()
require('fzf-lua-frecency').clear_db({
   -- defaults:
   db_dir = vim.fs.joinpath(vim.fn.stdpath "data", "fzf-lua-frecency")
})
```

## Default `FzfLua` opts

By default, the following options are passed along to `FzfLua.fzf_exec`:

```lua
local opts = {
  -- the default actions for FzfLua files, with an additional
  -- ["ctrl-x"] action to remove a file's frecency score
  actions      = actions,    
  -- FzfLua's default previewer
  previewer    = previewer,  
  file_icons   = true,
  color_icons  = true,
  git_icons    = false,
  fzf_opts     = {
    ["--multi"] = true,
    ["--scheme"] = "path",
    ["--no-sort"] = true,
  },
  winopts      = { preview = { winopts = { cursorline = false, }, }, },
  multiprocess = true,
  fn_transform = function(abs_file, opts)
    local entry = FzfLua.make_entry.file(rel_file, opts)
    -- ...
    -- prepends the frecency score if `display_score=true`
    -- filters out files that no longer exist if `stat_file=true`
    -- ...
    return entry
  end,
}
```

> [!IMPORTANT]
> By default, `fzf` will filter out results based on the current input and sort the results to display the most relevant items
first. With the `--no-sort` option enabled, `fzf` will continue to filter out results based on the current input, but it will
_not_ sort the list of results itself as you type. `fzf-lua-frecency` defaults `--no-sort` to `true` since the list provided to `fzf`
is already sorted: frecent files first (in order), everything else after. As a result, with `--no-sort` enabled, frecent items 
will always rank first in the list of results - even if another entry has a better fuzzy score based on the current input.
If you find `--no-sort` unintuitive, it can be disabled by passing `["--no-sort"] = false` to `fzf_opts`.

Any of the default options can be overriden by passing in your own option:

```lua
require('fzf-lua-frecency').frecency({
  file_icons   = false,
  color_icons  = false,
})

-- Using FzfLua's command
:FzfLua frecency display_score=false cwd_only=true
```

## How it works
- Files are ranked based on a frecency score. This score decays exponentially over time with a half-life of 30 days - i.e. if the current score is `1`, it will decay to `0.5` in 30 days.
- Scores are not stored directly. Instead, an `mpack`-encoded file keeps track of the `date_at_score_one` for each file, which represents the time at which the file's score will decay to `1`. Using the `date_at_score_one`, current time, and decay-rate, we can derive a file's current score.
- When a file is opened, the score for that file is computed, incremented by `1`, and converted back to a `date_at_score_one` format.
- The files are sorted based on current score and output to a `txt` file.
  - Files that are no longer available (i.e. deleted, renamed, moved) are also filtered during this step.
- When the picker is invoked, the `txt` file is read and its content are streamed into the UI. After the frecent files are fully populated, the results from `fd` are streamed in also. This ensures that the frecent files appear first, while also incrementally populating the picker UI.

## Performance
`fzf-lua-frecency.nvim` prioritizes performance in a few ways:

- Frecency scores are sorted after a file is opened, _not_ when populating the picker UI.
- The picker UI opens instantly, with frecency-ranked files and `fd` results streaming in over time.
- Files are processed for the picker UI by headless Neovim instances (`fzf-lua`'s `multiprocess=true` option). 
  - `fzf-lua-frecency` uses string interpolation to embed user configuration options into the headless instances

## Dependencies

- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [`fd`](https://github.com/sharkdp/fd), [`rg`](https://github.com/BurntSushi/ripgrep) or [`find`](https://www.gnu.org/software/findutils/)
- Neovim 0.9+

## Similar plugins
- [telescope-frecency.nvim](https://github.com/nvim-telescope/telescope-frecency.nvim)
- [smart-open.nvim](https://github.com/danielfalk/smart-open.nvim)
- [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim)
- [snacks.nvim's smart picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#smart)
- [fre integration with fzf-lua](https://github.com/ibhagwan/fzf-lua/discussions/2174)
- [fzf-lua-enchanted-files](https://github.com/otavioschwanck/fzf-lua-enchanted-files)
