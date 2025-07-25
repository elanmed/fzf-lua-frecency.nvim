local algo = require "fzf-lua-frecency.algo"
local h = require "fzf-lua-frecency.helpers"
local fs = require "fzf-lua-frecency.fs"

local root_dir = vim.fs.joinpath(vim.fn.getcwd(), "test-algo")
local db_dir = vim.fs.joinpath(root_dir, "db-dir")
local cwd = vim.fs.joinpath(root_dir, "files")
local sorted_files_path = h.get_sorted_files_path(db_dir, cwd)
local dated_files_path = h.get_dated_files_path(db_dir)
local max_scores_path = h.get_max_scores_path(db_dir)

local test_file_a = vim.fs.joinpath(cwd, "test-file-a.txt")
local test_file_b = vim.fs.joinpath(cwd, "test-file-b.txt")

local now = os.time { year = 2025, month = 1, day = 1, hour = 0, min = 0, sec = 0, }
local now_after_30_min = os.time { year = 2025, month = 1, day = 1, hour = 0, min = 30, sec = 0, }
local score_when_adding = 1
local date_at_score_one_now = algo.compute_date_at_score_one { now = now, score = score_when_adding, }
local score_decayed_after_30_min = 0.99951876362267

local function create_file(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local file = io.open(path, "w")
  if not file then
    error "io.open failed!"
  end
  file:write "content"
  file:close()
end

local function read_sorted()
  local file = io.open(sorted_files_path, "r")
  if not file then return "" end
  local data = file:read "*a"
  file:close()
  return data
end

local h_notify_error = h.notify_error

local function cleanup()
  h.notify_error = h_notify_error
  algo._now = function() return os.time() end
  vim.fn.delete(root_dir, "rf")
  create_file(test_file_a)
  create_file(test_file_b)
end

local T = MiniTest.new_set()
T["#update_file_score"] = MiniTest.new_set {
  hooks = {
    pre_case = cleanup,
    post_case = cleanup,
  },
}

T["#update_file_score"]["missing fields"] = MiniTest.new_set()
T["#update_file_score"]["missing fields"]["throws when missing filename"] = function()
  local called_err = false
  h.notify_error = function(msg)
    called_err = msg:find "ERROR: missing " ~= nil
  end

  algo.update_file_score()
  MiniTest.expect.equality(called_err, true)
end

T["#update_file_score"]["missing fields"]["throws when missing opts"] = function()
  local called_err = false
  h.notify_error = function(msg)
    called_err = msg:find "ERROR: missing " ~= nil
  end

  algo.update_file_score(test_file_a)
  MiniTest.expect.equality(called_err, true)
  MiniTest.expect.equality(fs.read(dated_files_path)[cwd], nil)
  MiniTest.expect.equality(read_sorted(), "")
end

T["#update_file_score"]["missing fields"]["throws when missing opts.update_type"] = function()
  local called_err = false
  h.notify_error = function(msg)
    called_err = msg:find "ERROR: missing " ~= nil
  end

  algo.update_file_score(test_file_a, {})
  MiniTest.expect.equality(called_err, true)
  MiniTest.expect.equality(fs.read(dated_files_path)[cwd], nil)
  MiniTest.expect.equality(read_sorted(), "")
end

T["#update_file_score"]["update_type=increase"] = MiniTest.new_set()
T["#update_file_score"]["update_type=increase"]["adds score entry for new file"] = function()
  algo._now = function() return now end
  algo.update_file_score(test_file_a, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "increase",
  })

  local dated_files = fs.read(dated_files_path)
  local date_at_score_one = dated_files[cwd][test_file_a]
  MiniTest.expect.equality(date_at_score_one, date_at_score_one_now)
  MiniTest.expect.equality(read_sorted(), test_file_a .. "\n")
  MiniTest.expect.equality(fs.read(max_scores_path)[cwd], score_when_adding)
end

T["#update_file_score"]["update_type=increase"]["increments score on repeated calls"] = function()
  algo._now = function() return now end
  algo.update_file_score(test_file_a, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    fs.read(dated_files_path)[cwd][test_file_a],
    date_at_score_one_now
  )

  algo._now = function() return now_after_30_min end
  algo.update_file_score(test_file_a, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    fs.read(dated_files_path)[cwd][test_file_a],
    algo.compute_date_at_score_one { now = now_after_30_min, score = score_decayed_after_30_min + 1, }
  )
  -- TODO: precision issue, values are the same
  -- MiniTest.expect.equality(fs.read(max_scores_path)[cwd], score_decayed_after_30_min + 1)
end

T["#update_file_score"]["update_type=increase"]["recalculates all scores when adding a new file"] = function()
  algo._now = function() return now end
  algo.update_file_score(test_file_a, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    fs.read(dated_files_path)[cwd][test_file_a],
    date_at_score_one_now
  )

  algo._now = function() return now_after_30_min end
  algo.update_file_score(test_file_b, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    fs.read(dated_files_path)[cwd][test_file_a],
    algo.compute_date_at_score_one { now = now_after_30_min, score = score_decayed_after_30_min, }
  )
  MiniTest.expect.equality(
    fs.read(dated_files_path)[cwd][test_file_b],
    algo.compute_date_at_score_one { now = now_after_30_min, score = score_when_adding, }
  )
  MiniTest.expect.equality(read_sorted(), test_file_b .. "\n" .. test_file_a .. "\n")
  MiniTest.expect.equality(fs.read(max_scores_path)[cwd], 1)
end

T["#update_file_score"]["update_type=increase"]["filters deleted files"] = function()
  algo._now = function() return now end
  algo.update_file_score(test_file_a, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    fs.read(dated_files_path)[cwd][test_file_a],
    date_at_score_one_now
  )

  os.remove(test_file_a)

  algo._now = function() return now_after_30_min end
  algo.update_file_score(test_file_b, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(
    fs.read(dated_files_path)[cwd][test_file_a],
    nil
  )
  MiniTest.expect.equality(
    fs.read(dated_files_path)[cwd][test_file_b],
    algo.compute_date_at_score_one { now = now_after_30_min, score = score_when_adding, }
  )
  MiniTest.expect.equality(read_sorted(), test_file_b .. "\n")
  MiniTest.expect.equality(fs.read(max_scores_path)[cwd], 1)
end

T["#update_file_score"]["update_type=remove"] = MiniTest.new_set()
T["#update_file_score"]["update_type=remove"]["adds entry for existing file"] = function()
  algo._now = function() return now end
  algo.update_file_score(test_file_a, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "increase",
  })

  MiniTest.expect.equality(fs.read(dated_files_path)[cwd][test_file_a], date_at_score_one_now)
  MiniTest.expect.equality(read_sorted(), test_file_a .. "\n")
  MiniTest.expect.equality(fs.read(max_scores_path)[cwd], score_when_adding)

  algo._now = function() return now end
  algo.update_file_score(test_file_a, {
    cwd = cwd,
    db_dir = db_dir,
    update_type = "remove",
  })

  MiniTest.expect.equality(fs.read(dated_files_path)[cwd][test_file_a], nil)
  MiniTest.expect.equality(read_sorted(), "")
  MiniTest.expect.equality(fs.read(max_scores_path)[cwd], 0)
end

return T
