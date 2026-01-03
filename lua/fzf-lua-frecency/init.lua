local h = require "fzf-lua-frecency.helpers"
local algo = require "fzf-lua-frecency.algo"

-- runtime path for this package, to be used with the headless instance for loading
local __FILE__ = debug.getinfo(1, "S").source:gsub("^@", "")
local __RTP__ = vim.fn.fnamemodify(__FILE__, ":h:h:h")

local M = {}

--- @class FrecencyOpts
--- @field debug? boolean
--- @field db_dir? string
--- @field all_files? boolean
--- @field stat_file? boolean
--- @field display_score? boolean
--- @field [string] any any fzf-lua option

--- @class SetupOpts
--- @field debug? boolean
--- @field db_dir? string
--- @field stat_file? boolean
--- @field [string] any any fzf-lua option

--- @param opts? SetupOpts
M.setup = function(opts)
  if M._did_setup then return end
  M._did_setup = true

  -- creates the FzfLua global object
  require "fzf-lua"

  opts = opts or {}
  local db_dir = h.default(opts.db_dir, h.default_opts.db_dir)
  local debug = h.default(opts.debug, h.default_opts.debug)
  local stat_file = h.default(opts.stat_file, h.default_opts.stat_file)

  FzfLua.register_extension("frecency", M.frecency, vim.tbl_deep_extend("keep", opts, {
      -- fzf-lua-frecency specific defaults
      cwd_only = false,
      all_files = nil,
      stat_file = true,
      display_score = true,
      -- relevant options from fzf-lua's default `files` options
      _type = "file", -- adds `fn_preprocess` if required
      previewer = FzfLua.defaults.files.previewer, -- inherit from default previewer (if `bat`)
      multiprocess = true,
      file_icons = true,
      color_icons = true,
      git_icons = false,
      hidden = true, -- add `--hidden` by default
      find_opts = [[-type f \! -path '*/.git/*']],
      rg_opts = [[--color=never --files -g "!.git"]],
      fd_opts = [[--color=never --type f --type l --exclude .git]],
      dir_opts = [[/s/b/a:-d]],
      fzf_opts = {
        ["--multi"] = true,
        ["--scheme"] = "path",
        ["--no-sort"] = true,
      },
      winopts = {
        title = " Frecency ",
        preview = { winopts = { cursorline = false, }, },
      },
      -- tell fzf to ignore fuzzy matching anything before the filename
      -- by adding a "--delimiter=utils.nbsp|--nth=-1.." to fzf_opts
      -- this avoids matching the score text/icons so we can perform
      -- searches like "^init.lua"
      _fzf_nth_devicons = true,
      -- display cwd (if different) and action (ctrl-x) headers
      _headers = { "cwd", "actions", },
      -- inherit actions from the users' setup/global `actions.files`
      _actions = function() return FzfLua.config.globals.actions.files end,
      actions = {
        ["ctrl-x"] = {
          fn = function(selected, o)
            for _, sel in ipairs(selected) do
              local filename = FzfLua.path.entry_to_file(sel, o).path
              algo.update_file_score(filename, {
                update_type = "remove",
                db_dir = db_dir,
                debug = debug,
                stat_file = stat_file,
              })
            end
          end,
          desc = "delete-score",
          header = "delete a frecency score",
          reload = true,
        },
      },
    }),
    true)

  local timer_id = nil
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("FzfLuaFrecency", { clear = true, }),
    callback = function(ev)
      if timer_id then
        vim.fn.timer_stop(timer_id)
      end

      local current_win = vim.api.nvim_get_current_win()
      local is_normal_win = vim.api.nvim_win_get_config(current_win).relative == ""
      if not is_normal_win then return end

      local is_normal_buf = vim.api.nvim_get_option_value("buftype", { buf = ev.buf, }) == ""
      if not is_normal_buf then return end

      local bname = vim.api.nvim_buf_get_name(ev.buf)
      if bname == "" then return end

      timer_id = vim.fn.timer_start(1000, function()
        algo.update_file_score(vim.fs.normalize(bname), {
          update_type = "increase",
          db_dir = db_dir,
          debug = debug,
          stat_file = stat_file,
        })
      end)
    end,
  })
end

--- @param opts? FrecencyOpts
M.frecency = function(opts)
  -- does nothing if already called
  M.setup()

  opts = FzfLua.config.normalize_opts(opts, "frecency")
  if not opts then return end

  opts.cwd = h.default(opts.cwd, vim.uv.cwd())
  local db_dir = h.default(opts.db_dir, h.default_opts.db_dir)
  local stat_file = h.default(opts.stat_file, h.default_opts.stat_file)
  local display_score = h.default(opts.display_score, h.default_opts.display_score)
  local all_files = opts.all_files == nil and opts.cwd_only or opts.all_files

  local sorted_files_path = h.get_sorted_files_path(db_dir)

  -- options that fzf-lua's multiprocess does not serialize
  -- these aren't included in the fn_transform callback opts
  --- @type GetFnTransformOpts
  local encodeable_opts = {
    db_dir = db_dir,
    stat_file = stat_file,
    all_files = all_files,
    display_score = display_score,
  }

  opts.fn_selected = function(...)
    _G._fzf_lua_frecency_dated_files = nil
    FzfLua.actions.act(...)
  end

  opts.fn_preprocess = string.format [[
    _G._fzf_lua_frecency_EOF = nil
    return require("fzf-lua.make_entry").preprocess
  ]]

  -- RPC worked fine on linux, but was hanging on mac - specifically vim.rpcrequest
  -- using basic string interpolation works well since all the opts that are used
  -- can be stringified
  opts.fn_transform = string.format([[
    vim.opt.runtimepath:append("%s")
    local rpc_opts = vim.mpack.decode(%q)
    return require "fzf-lua-frecency.fn_transform".get_fn_transform(rpc_opts)
  ]], __RTP__, vim.mpack.encode(encodeable_opts))

  opts.cmd = opts.cmd or (function()
    local cat_cmd = table.concat({
      h.IS_WINDOWS and "type" or "cat",
      vim.fn.shellescape(h.get_native_filepath(sorted_files_path)),
      "2>" .. (h.IS_WINDOWS and "nul" or "/dev/null"), -- in case the file doesn't exist
    }, " ")
    if not all_files then
      return cat_cmd
    end

    local all_files_cmd = require "fzf-lua.providers.files".get_files_cmd(opts)
    if not all_files_cmd then return cat_cmd end

    return ("%s %s %s"):format(cat_cmd, h.IS_WINDOWS and "&&" or ";", all_files_cmd)
  end)()

  -- set title flags (h|i|f) based on hidden/no-ignore/follow flags
  opts = FzfLua.core.set_title_flags(opts, { "cmd", })
  return FzfLua.fzf_exec(opts.cmd, opts)
end

--- @class ClearDbOpts
--- @field db_dir? string

--- deletes the `dated-files.mpack` file and the `cwds` directory.
--- does not delete `db_dir` itself or anything else in `db_dir`
--- @param opts? ClearDbOpts
M.clear_db = function(opts)
  opts = opts or {}
  local db_dir = h.default(opts.db_dir, h.default_opts.db_dir)
  local sorted_files_path = h.get_sorted_files_path(db_dir)
  local dated_files_path = h.get_dated_files_path(db_dir)

  vim.fn.delete(sorted_files_path)
  vim.fn.delete(dated_files_path)
end

return M
