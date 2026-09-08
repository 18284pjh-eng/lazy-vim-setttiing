local M = {}
local uv = vim.uv
local active = {} -- one pending semantic request per tab

local function notice(message, level)
  vim.notify(message, level or vim.log.levels.WARN, { title = "Filelist" })
end

local function path(base, name)
  return vim.fs.normalize(name:sub(1, 1) == "/" and name or base .. "/" .. name, { expand_env = false })
end

function M.read(file, quiet)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then
    if not quiet then
      notice("无法读取清单: " .. file)
    end
    return nil
  end
  local list = { file = file, root = vim.fs.dirname(file), files = {}, members = {} }
  local skipped = 0
  for _, line in ipairs(lines) do
    line = line:gsub("\r$", "")
    if line ~= "" then
      local name = path(list.root, line)
      local stat = not line:find("%z") and uv.fs_stat(name)
      if line:sub(1, 1) == "/" or line:find("%z") or not stat or stat.type ~= "file" then
        skipped = skipped + 1
      elseif not list.members[name] then
        list.files[#list.files + 1] = name
        list.members[name] = true
      end
    end
  end
  if skipped > 0 and not quiet then
    notice(("清单跳过 %d 个无效条目；新增/删除文件后请重新生成"):format(skipped))
  end
  return list
end

function M.select()
  local explicit = vim.t.filelist_explicit
  if explicit then
    return M.read(explicit)
  end
  local current = vim.api.nvim_buf_get_name(0)
  local found = current ~= ""
      and vim.fs.find("tree_t.f", {
        path = vim.fs.dirname(current),
        upward = true,
        type = "file",
      })[1]
    or nil
  if not found and vim.t.filelist_source then
    local previous = M.read(vim.t.filelist_source, true)
    if previous and previous.members[current] then
      found = previous.file
    end
  end
  found = found or vim.fs.find("tree_t.f", { path = vim.fn.getcwd(), upward = true, type = "file" })[1]
  if found then
    vim.t.filelist_source = found
    return M.read(found)
  end
end

local function show(title, items, direct)
  if #items > 0 then
    Snacks.picker({
      title = title,
      items = items,
      format = "file",
      preview = "file",
      auto_confirm = direct,
      jump = { match = false },
    })
  end
end

function M.headers(list, line, source)
  local quoted = line:match('^%s*#%s*include%s*"([^"]+)"')
  local name = quoted or line:match("^%s*#%s*include%s*<([^>]+)>")
  if not name then
    return nil
  end
  local items = {}
  local local_file = quoted and path(vim.fs.dirname(source), name)
  for _, file in ipairs(list.files) do
    if file == local_file or file:sub(-#name - 1) == "/" .. name then
      items[#items + 1] = { file = file, text = file, pos = { 1, 0 } }
    end
  end
  return items
end

-- A custom Snacks finder keeps batching/cancellation inside the existing UI.
-- Explicit file operands mean rg never recursively scans parent directories.
function M.finder(list, word)
  return function()
    return function(cb)
      local async = require("snacks.picker.util.async").running()
      local process
      async:on("abort", function()
        if process then
          process:kill(15)
        end
      end)
      local index = 1
      while index <= #list.files do
        local args = { "rg", "--json", "--no-config", "--fixed-strings", "--word-regexp", "--", word }
        local bytes = #word
        while index <= #list.files and bytes < 24000 do
          args[#args + 1] = list.files[index]
          bytes = bytes + #list.files[index] + 1
          index = index + 1
        end
        local result
        async:schedule(function()
          if async:aborted() then
            return
          end
          process = vim.system(args, { text = true }, function(output)
            result = output
            async:resume()
          end)
        end)
        if not result then
          async:suspend()
        end
        process = nil
        if result.code > 1 then
          async:schedule(function()
            notice("清单搜索失败: " .. (result.stderr or "rg error"), vim.log.levels.ERROR)
          end)
        end
        for line in (result.stdout or ""):gmatch("[^\n]+") do
          local event = vim.json.decode(line)
          if event.type == "match" and event.data.path.text and event.data.lines.text then
            local data = event.data
            for _, match in ipairs(data.submatches) do
              cb({
                file = data.path.text,
                pos = { data.line_number, match.start },
                line = data.lines.text:gsub("[\r\n]+$", ""),
                text = data.path.text .. ":" .. data.line_number .. ": " .. data.lines.text:gsub("[\r\n]+$", ""),
              })
            end
          end
        end
      end
    end
  end
end

local function grep(list, word)
  if not list then
    notice("未找到 tree_t.f；请生成清单或使用 :FilelistUse 指定项目")
    return
  end
  if #list.files == 0 then
    notice("清单为空或没有有效文件，请重新生成")
    return
  end
  if not word or word == "" or word:find("[\r\n%z]") then
    notice("请将光标置于标识符，或使用 :FilelistGrep 搜索词")
    return
  end
  if vim.fn.executable("rg") ~= 1 then
    notice("找不到 rg，请通过离线包的 nvim 包装器启动", vim.log.levels.ERROR)
    return
  end
  Snacks.picker({
    title = "文本匹配（非语义引用）: " .. word,
    finder = M.finder(list, word),
    format = "file",
    preview = "file",
    jump = { match = false },
  })
end

local function semantic(method, fallback)
  local buf, win, tab =
    vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local done, timer, guard = false, nil, nil
  local requests, items, seen = {}, {}, {}
  local clients = vim.lsp.get_clients({ bufnr = buf, method = method })
  local pending = #clients
  local function cancel()
    if done then
      return
    end
    done = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if guard then
      vim.api.nvim_del_autocmd(guard)
    end
    for _, request in ipairs(requests) do
      if not request.finished then
        request.client:cancel_request(request.id)
      end
    end
    active[tab] = nil
  end
  local function finish()
    if done then
      return
    end
    cancel()
    if
      vim.api.nvim_get_current_win() ~= win
      or vim.api.nvim_get_current_buf() ~= buf
      or vim.api.nvim_get_current_tabpage() ~= tab
      or not vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
      or vim.api.nvim_buf_get_changedtick(buf) ~= tick
    then
      return
    end
    if #items > 0 then
      show(
        method == "textDocument/definition" and "LSP 定义" or "LSP 语义引用",
        items,
        method == "textDocument/definition"
      )
    else
      fallback()
    end
  end
  active[tab] = cancel
  if pending == 0 then
    finish()
    return
  end
  guard = vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "CursorMoved", "TextChanged", "InsertEnter" }, {
    buffer = buf,
    callback = cancel,
  })
  timer = vim.defer_fn(finish, 2000)
  for _, client in ipairs(clients) do
    local request = { client = client }
    local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
    if method == "textDocument/references" then
      params.context = { includeDeclaration = true }
    end
    local ok, id = client:request(method, params, function(err, result)
      request.finished = true
      if done then
        return
      end
      if not err and result then
        if result.uri or result.targetUri then
          result = { result }
        end
        for _, loc in ipairs(vim.lsp.util.locations_to_items(result, client.offset_encoding)) do
          local key = loc.filename .. ":" .. loc.lnum .. ":" .. loc.col
          if not seen[key] then
            seen[key] = true
            items[#items + 1] = {
              file = loc.filename,
              pos = { loc.lnum, loc.col - 1 },
              line = loc.text,
              text = key .. " " .. (loc.text or ""),
            }
          end
        end
      end
      pending = pending - 1
      if pending == 0 then
        finish()
      end
    end, buf)
    if ok then
      request.id = id
      requests[#requests + 1] = request
    else
      pending = pending - 1
    end
  end
  if pending == 0 then
    finish()
  end
end

function M.set_text_only(state)
  vim.g.filelist_text_only = state
  for _, cancel in pairs(active) do
    cancel()
  end
end

function M.navigate(kind)
  local pending = active[vim.api.nvim_get_current_tabpage()]
  if pending then
    pending()
  end
  local supported = vim.bo.filetype == "c" or vim.bo.filetype == "cpp"
  local text_only = supported and vim.g.filelist_text_only == true
  local list = supported and M.select() or nil
  if text_only and not list then
    return grep(nil)
  end
  if not list then
    -- Preserve LazyVim's ordinary LSP picker when no file list applies.
    if kind == "definition" then
      return Snacks.picker.lsp_definitions()
    end
    return Snacks.picker.lsp_references()
  end
  if kind == "definition" then
    local items = M.headers(list, vim.api.nvim_get_current_line(), vim.api.nvim_buf_get_name(0))
    if items and #items > 0 then
      show("清单头文件（选择完整路径）", items, true)
      return
    end
  end
  local word = vim.fn.expand("<cword>")
  if text_only then
    return grep(list, word)
  end
  semantic("textDocument/" .. kind, function()
    grep(list, word)
  end)
end

function M.setup()
  Snacks.toggle({
    id = "filelist_text_only",
    name = "Filelist 直接文本匹配",
    get = function()
      return vim.g.filelist_text_only == true
    end,
    set = M.set_text_only,
  }):map("<leader>uJ")
  for _, mapping in ipairs({ { "gd", "definition" }, { "gr", "references" } }) do
    Snacks.keymap.set("n", mapping[1], function()
      M.navigate(mapping[2])
    end, { ft = { "c", "cpp" }, desc = "Filelist / LSP " .. mapping[2], nowait = true })
  end
  vim.api.nvim_create_user_command("FilelistUse", function(opts)
    if opts.args == "" then
      vim.t.filelist_explicit, vim.t.filelist_source = nil, nil
      notice("已恢复自动选择清单", vim.log.levels.INFO)
      return
    end
    local name = opts.args:gsub("^~/", function()
      return vim.env.HOME .. "/"
    end)
    local file = path(vim.fn.getcwd(), name)
    if M.read(file) then
      vim.t.filelist_explicit = file
      notice("当前标签页清单: " .. file, vim.log.levels.INFO)
    end
  end, { nargs = "?", desc = "选择清单；无参数恢复自动选择（路径按原文输入）" })
  vim.api.nvim_create_user_command("FilelistGrep", function(opts)
    grep(M.select(), opts.args ~= "" and opts.args or vim.fn.expand("<cword>"))
  end, { nargs = "?", desc = "清单内完整词文本匹配（非语义引用）" })
end

return M
