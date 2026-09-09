-- Run with the full config: XDG_CONFIG_HOME="$PWD/config" nvim --headless
--   '+lua dofile("scripts/test-filelist-integration.lua")'
local work = vim.fn.tempname()
local project, sdk = work .. "/project", work .. "/sdk"
local function write(file, lines)
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  vim.fn.writefile(lines, file)
end
local function edit(file, row, word)
  vim.cmd.edit(vim.fn.fnameescape(file))
  local line = vim.fn.getline(row or 1)
  vim.api.nvim_win_set_cursor(0, { row or 1, word and assert(line:find(word, 1, true)) - 1 or 0 })
  -- Let CursorMoved/BufEnter handlers settle before testing actual mapped keys.
  vim.wait(150, function()
    return false
  end)
end
local function key(lhs)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "xt", false)
end
local function picker(count)
  local found
  assert(
    vim.wait(10000, function()
      found = Snacks.picker.get()[1]
      return found and #found:items() >= count and not found.finder:running()
    end, 20),
    "picker missing results"
  )
  return found
end
local function attached(name)
  assert(
    vim.wait(15000, function()
      return #vim.lsp.get_clients({ bufnr = 0, name = name }) > 0
    end, 50),
    name .. " did not attach"
  )
  vim.wait(200, function()
    return false
  end)
  return vim.lsp.get_clients({ bufnr = 0, name = name })[1]
end
local function test()
  vim.o.columns, vim.o.lines = 160, 50
  require("lazy").load({ plugins = { "nvim-lspconfig" } })
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
  vim.lsp.enable("clangd", false)
  write(project .. "/cpp/check.cpp", { '#include "dp.h"' })
  write(project .. "/.git/HEAD", { "ref: refs/heads/main" })
  write(project .. "/include/app.h", { "int shared(void);" })
  write(project .. "/src/main.c", { '#include "app.h"', '#include "dp.h"', "int main(void) { return shared(); }" })
  write(project .. "/src/impl.c", { '#include "app.h"', "int shared(void) { return 42; }" })
  write(sdk .. "/dp.h", { "// shared SDK header" })
  write(project .. "/outside.c", { "// shared must stay outside text search" })
  write(project .. "/tree_t.f", { "include/app.h", "src/main.c", "src/impl.c", "../sdk/dp.h" })
  local commands = {}
  for _, file in ipairs({ "main.c", "impl.c" }) do
    commands[#commands + 1] = {
      directory = project,
      file = project .. "/src/" .. file,
      arguments = { "cc", "-I" .. project .. "/include", "-I" .. sdk, "-c", project .. "/src/" .. file },
    }
  end
  write(project .. "/compile_commands.json", { vim.json.encode(commands) })
  vim.cmd.cd(vim.fn.fnameescape(project))
  edit(project .. "/cpp/check.cpp")
  assert(vim.bo.filetype == "cpp")
  key("gd")
  assert(
    vim.wait(3000, function()
      return vim.api.nvim_buf_get_name(0) == sdk .. "/dp.h"
    end),
    "C++ mapping before LSP failed"
  )
  edit(project .. "/src/main.c", 2)
  assert(#vim.lsp.get_clients({ bufnr = 0, name = "clangd" }) == 0)
  assert(type(vim.fn.maparg("gd", "n", false, true).callback) == "function")
  key("gd")
  assert(
    vim.wait(3000, function()
      return vim.api.nvim_buf_get_name(0) == sdk .. "/dp.h"
    end),
    "gd before LSP failed"
  )
  key("<C-o>")
  assert(vim.api.nvim_buf_get_name(0) == project .. "/src/main.c")

  write(project .. "/include/dp.h", { "// another SDK" })
  write(project .. "/tree_t.f", { "include/app.h", "include/dp.h", "src/main.c", "src/impl.c", "../sdk/dp.h" })
  key("gd")
  local p = picker(2)
  assert(p.opts.title:find("清单头文件") and #p:items() == 2)
  assert(p:items()[1].file ~= p:items()[2].file)
  assert(vim.api.nvim_win_is_valid(p.preview.win.win), "header preview not visible")
  p:close()
  edit(project .. "/src/main.c", 3, "shared")
  for _, lhs in ipairs({ "gd", "gr" }) do
    key(lhs)
    p = picker(lhs == "gd" and 1 or 3)
    assert(p.opts.title:find(lhs == "gd" and "定义候选" or "非语义引用"))
    assert(#p:items() == (lhs == "gd" and 1 or 3))
    for _, item in ipairs(p:items()) do
      assert((item.file == project .. "/src/impl.c") == (lhs == "gd"), "gd/gr did not distinguish function definitions")
      assert(item.file ~= project .. "/outside.c", "text search escaped filelist")
      assert(item.line and item.line:find("shared"), "text candidate lacks displayed context")
    end
    assert(vim.api.nvim_win_is_valid(p.list.win.win))
    local selected = assert(p:current())
    Snacks.picker.actions.jump(p, selected, {})
    assert(vim.wait(1000, function()
      return p.closed
    end))
    assert(vim.api.nvim_buf_get_name(0) == selected.file)
    key("<C-o>")
    assert(vim.api.nvim_buf_get_name(0) == project .. "/src/main.c", "picker jump lost Ctrl-o origin")
    edit(project .. "/src/main.c", 3, "shared")
  end
  io.stdout:write("REAL_UI_OK: C gd/gr without LSP, include choice/preview, rg context/scope, Ctrl-o\n")

  vim.lsp.enable("clangd")
  edit(project .. "/src/impl.c", 2, "shared")
  attached("clangd")
  edit(project .. "/src/main.c", 3, "shared")
  local client = attached("clangd")
  local toggle = assert(Snacks.toggle.get("filelist_text_only"))
  assert(not toggle:get(), "text-only mode must default off")
  key("<Space>uJ")
  assert(toggle:get(), "toggle key did not enable text-only mode")
  local request, navigation_requests = client.request, 0
  client.request = function(self, method, ...)
    if method == "textDocument/definition" or method == "textDocument/references" then
      navigation_requests = navigation_requests + 1
    end
    return request(self, method, ...)
  end
  for _, lhs in ipairs({ "gd", "gr" }) do
    key(lhs)
    p = picker(lhs == "gd" and 1 or 3)
    assert(p.opts.title:find(lhs == "gd" and "定义候选" or "非语义引用"))
    assert(#p:items() == (lhs == "gd" and 1 or 3))
    assert(navigation_requests == 0, "text-only navigation sent an LSP request")
    p:close()
    edit(project .. "/src/main.c", 3, "shared")
  end
  write(project .. "/src/objects.c", {
    "struct Record { int value; };",
    "int count, table[4];",
    "#define LIMIT 4",
    "void use(void) { struct Record item; count = table[0] + LIMIT; item.value = count; }",
  })
  local filelist = vim.fn.readfile(project .. "/tree_t.f")
  filelist[#filelist + 1] = "src/objects.c"
  write(project .. "/tree_t.f", filelist)
  for _, word in ipairs({ "Record", "value", "count", "table", "LIMIT" }) do
    edit(project .. "/src/objects.c", 4, word)
    for _, lhs in ipairs({ "gd", "gr" }) do
      key(lhs)
      p = picker(1)
      for _, item in ipairs(p:items()) do
        assert((item.pos[1] < 4) == (lhs == "gd"), word .. ": definition/use filtering failed")
      end
      p:close()
      edit(project .. "/src/objects.c", 4, word)
    end
  end
  io.stdout:write("SYMBOLS_OK: real gd/gr for structs, members, variables, arrays and macros\n")
  edit(project .. "/src/main.c", 3, "shared")
  client.request = request
  key("<Space>uJ")
  assert(not toggle:get(), "toggle key did not restore LSP mode")
  io.stdout:write("TOGGLE_OK: real key/picker, attached clangd receives no gd/gr requests when enabled\n")
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  assert(
    vim.wait(15000, function()
      local response = client:request_sync("textDocument/definition", params, 2000, 0)
      return response and response.result and vim.inspect(response.result):find("impl.c", 1, true)
    end, 100),
    "clangd cross-file index did not become ready"
  )
  key("gd")
  assert(
    vim.wait(4000, function()
      return vim.api.nvim_buf_get_name(0) == project .. "/src/impl.c"
    end),
    "gd after clangd attachment failed"
  )
  key("<C-o>")
  edit(project .. "/src/main.c", 3, "shared")
  key("gr")
  p = picker(2)
  assert(p.opts.title == "LSP 语义引用")
  p:close()
  edit(project .. "/src/main.c", 2)
  key("gd")
  p = picker(2)
  assert(p.opts.title:find("清单头文件"), "LSP attachment overwrote include handler")
  p:close()
  io.stdout:write("REAL_LSP_OK: clangd cross-file gd/gr and include mapping after attachment\n")

  -- Removing the list restores ordinary Snacks LSP navigation.
  vim.fn.delete(project .. "/tree_t.f")
  edit(project .. "/src/main.c", 3, "shared")
  key("gr")
  p = picker(2)
  assert(p.opts.source == "lsp_references", vim.inspect(p.opts.source))
  p:close()

  write(project .. "/helper.py", { "def shared():", "    return 42" })
  write(project .. "/main.py", { "from helper import shared", "print(shared())", "print(shared())" })
  write(project .. "/pyproject.toml", { "[tool.pyright]", 'include = ["."]' })
  write(project .. "/outside.py", { "def shared(): return 0" })
  write(project .. "/model.py", {
    "class Device:",
    "    field = 1",
    "COUNT = 1",
    "items = [COUNT]",
    "print(Device.field, COUNT, items)",
  })
  write(project .. "/tree_t.f", { "main.py", "helper.py", "model.py" })
  vim.lsp.enable("pyright", false)
  edit(project .. "/main.py", 2, "shared")
  for _, lhs in ipairs({ "gd", "gr" }) do
    key(lhs)
    p = picker(lhs == "gd" and 1 or 3)
    assert(#p:items() == (lhs == "gd" and 1 or 3))
    for _, item in ipairs(p:items()) do
      assert((item.file == project .. "/helper.py") == (lhs == "gd"), "Python definition/reference split failed")
      assert(item.file ~= project .. "/outside.py", "Python search escaped filelist")
    end
    local selected = assert(p:current())
    Snacks.picker.actions.jump(p, selected, {})
    assert(vim.wait(1000, function()
      return p.closed
    end))
    key("<C-o>")
    assert(vim.api.nvim_buf_get_name(0) == project .. "/main.py", "Python jump lost origin")
    edit(project .. "/main.py", 2, "shared")
  end
  for _, word in ipairs({ "Device", "field", "COUNT", "items" }) do
    edit(project .. "/model.py", 5, word)
    key("gd")
    p = picker(1)
    assert(#p:items() == 1 and p:items()[1].pos[1] < 5, "Python class/variable binding missing: " .. word)
    p:close()
  end
  vim.lsp.enable("pyright")
  edit(project .. "/main.py", 2, "shared")
  client = attached("pyright")
  key("<Space>uJ")
  assert(toggle:get())
  request, navigation_requests = client.request, 0
  client.request = function(self, method, ...)
    if method == "textDocument/definition" or method == "textDocument/references" then
      navigation_requests = navigation_requests + 1
    end
    return request(self, method, ...)
  end
  for _, lhs in ipairs({ "gd", "gr" }) do
    key(lhs)
    p = picker(lhs == "gd" and 1 or 3)
    assert(#p:items() == (lhs == "gd" and 1 or 3))
    assert(navigation_requests == 0, "Python text-only mode requested LSP navigation")
    p:close()
    edit(project .. "/main.py", 2, "shared")
  end
  -- Missing/empty Python lists must not fall through to LSP in text-only mode.
  for _, empty in ipairs({ true, false }) do
    if empty then
      write(project .. "/tree_t.f", {})
    else
      vim.fn.delete(project .. "/tree_t.f")
    end
    key("gd")
    key("gr")
    vim.wait(100, function()
      return false
    end)
    assert(#Snacks.picker.get() == 0 and navigation_requests == 0)
  end
  client.request = request
  write(project .. "/tree_t.f", { "main.py", "helper.py", "model.py" })
  key("<Space>uJ")
  key("gd")
  assert(vim.wait(4000, function()
    return vim.api.nvim_buf_get_name(0) == project .. "/helper.py"
  end))
  edit(project .. "/main.py", 2, "shared")
  key("gr")
  p = picker(2)
  assert(p.opts.title == "LSP 语义引用")
  p:close()
  io.stdout:write("PYTHON_OK: real gd/gr before Pyright, binding candidates, scope, Ctrl-o, toggle and LSP recovery\n")
  vim.fn.delete(project .. "/tree_t.f")
  write(project .. "/child.sv", { "module child;", "endmodule" })
  write(project .. "/top.sv", { "module top;", "  child u_child();", "  child u_child2();", "endmodule" })
  write(project .. "/other.sv", { "module other;", "  child u_child();", "endmodule" })
  write(project .. "/verible.filelist", { "child.sv", "top.sv", "other.sv" })
  -- Python without a list keeps ordinary LSP behavior; Verilog is unchanged.
  for _, case in ipairs({
    { "pyright", "main.py", 2, "shared", "helper.py" },
    { "verible", "top.sv", 2, "child", "child.sv" },
  }) do
    if case[1] == "verible" then
      write(project .. "/tree_t.f", { "src/main.c" })
      key("<Space>uJ")
    end
    edit(project .. "/" .. case[2], case[3], case[4])
    client = attached(case[1])
    params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local response = assert(client:request_sync("textDocument/definition", params, 15000, 0))
    assert(not response.err and vim.inspect(response.result):find(case[5], 1, true), vim.inspect(response))
    params.context = { includeDeclaration = true }
    response = assert(client:request_sync("textDocument/references", params, 15000, 0))
    assert(not response.err and vim.inspect(response.result):find(case[2], 1, true), vim.inspect(response))
    key("gr")
    p = picker(1)
    assert(p.opts.source == "lsp_references", vim.inspect(p.opts.source))
    p:close()
    io.stdout:write("REAL_LSP_OK: " .. case[1] .. " cross-file definitions/references and ordinary gr\n")
  end
end
vim.defer_fn(function()
  local ok, err = xpcall(test, debug.traceback)
  vim.fn.delete(work, "rf")
  if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
  end
  vim.cmd("qa!")
end, 300)
