-- Run: nvim -u NONE -n --headless -l scripts/test-filelist.lua
-- Set FILELIST_CONFIG / FILELIST_GENERATOR to test an installed package.
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(vim.env.FILELIST_CONFIG or (root .. "/config/nvim"))
local generator = vim.env.FILELIST_GENERATOR or (root .. "/scripts/nvim-filelist.sh")
local work = vim.fn.tempname()
vim.fn.mkdir(work, "p")
local project = work .. "/project"
local sdk = work .. "/sdk"
local nav = require("config.filelist")
local notes = {}
vim.notify = function(message)
  notes[#notes + 1] = message
end
local function write(file, lines)
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  vim.fn.writefile(lines, file)
end
local function run(args, cwd, expected)
  local result = vim.system(args, { cwd = cwd or project, text = true }):wait()
  assert(result.code == (expected or 0), vim.inspect({ args, result }))
  return result.stdout
end
local function generate(dirs, expected, at)
  local args = { "bash", generator, "--root", at or project, "--" }
  vim.list_extend(args, dirs)
  return run(args, at, expected)
end
local function edit(file, row, col)
  vim.cmd.edit(vim.fn.fnameescape(file))
  vim.bo.filetype = "c"
  vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
end
local picker
_G.Snacks = {
  toggle = function()
    return { map = function() end }
  end,
  keymap = { set = function() end },
  picker = setmetatable({
    lsp_definitions = function()
      picker = "normal definitions"
    end,
    lsp_references = function()
      picker = "normal references"
    end,
  }, {
    __call = function(_, opts)
      picker = opts
    end,
  }),
}
local function test()
  write(project .. "/src/main.c", { '#include "dp.h"', "int main(void) { return shared(); }", "// shared" })
  write(project .. "/include/app.h", { "int shared(void);" })
  write(sdk .. "/include/dp.h", { "int shared(void);" })
  write(project .. "/include/带 空格.h", { "// shared" })
  write(project .. "/ignored/out.h", { "int shared(void);" })
  write(project .. "/excluded.c", { "// shared must not be searched here" })
  write(project .. "/.gitignore", { "ignored/" })
  write(project .. "/include/readme.txt", { "not C" })
  run({ "git", "init", "-q" })
  run({ "ln", "-s", sdk .. "/include", project .. "/sdk-link" })
  run({ "ln", "-s", sdk .. "/include", project .. "/src/internal-link" })
  run({ "ln", "-s", sdk .. "/include/dp.h", project .. "/include/file-link.h" })
  generate({ "src", "include", "include", "../sdk/include", "ignored", "sdk-link" })
  local lines = vim.fn.readfile(project .. "/tree_t.f")
  assert(vim.tbl_contains(lines, "../sdk/include/dp.h"))
  assert(vim.tbl_contains(lines, "sdk-link/dp.h"))
  assert(vim.tbl_contains(lines, "include/file-link.h"))
  assert(vim.tbl_contains(lines, "include/带 空格.h"))
  assert(vim.tbl_contains(lines, "ignored/out.h"))
  assert(not table.concat(lines, "\n"):find("internal%-link"))
  assert(#lines == 7, vim.inspect(lines))
  run({ "git", "check-ignore", "-q", "tree_t.f" })
  assert(run({ "git", "status", "--porcelain", "--", "tree_t.f" }) == "")
  generate({ "missing" }, 1)
  assert(vim.deep_equal(lines, vim.fn.readfile(project .. "/tree_t.f")))
  vim.fn.mkdir(project .. "/empty", "p")
  generate({ "empty" }, 1)
  write(project .. "/src/invalid\nname.c", { "" })
  generate({ "src" }, 1)
  vim.fn.delete(project .. "/src/invalid\nname.c")
  run({ "git", "add", "-f", "tree_t.f" })
  generate({ "src" }, 1)
  run({ "git", "rm", "--cached", "-q", "tree_t.f" })
  run({
    "git",
    "-c",
    "user.name=Test",
    "-c",
    "user.email=test@example.invalid",
    "commit",
    "--allow-empty",
    "-qm",
    "fixture",
  })
  run({ "git", "worktree", "add", "--detach", "-q", work .. "/linked" })
  write(work .. "/linked/nested [a]/src/test.c", { "int x;" })
  generate({ "src" }, 0, work .. "/linked/nested [a]")
  run({ "git", "check-ignore", "-q", "tree_t.f" }, work .. "/linked/nested [a]")
  vim.fn.delete(project .. "/ignored/out.h")
  generate({ "src", "include", "../sdk/include" })
  assert(not table.concat(vim.fn.readfile(project .. "/tree_t.f"), "\n"):find("ignored"))
  print("filelist generator: paths, links, atomic failure, Git/worktree exclusion OK")

  nav.setup()
  local special = "include/$FILELIST_LITERAL%name.h"
  write(project .. "/" .. special, { "// shared" })
  generate({ "src", "include", "../sdk/include" })
  assert(nav.read(project .. "/tree_t.f").members[project .. "/" .. special])
  local chosen = work .. "/chosen $FILELIST_LITERAL% space/tree_t.f"
  write(chosen, { "../sdk/include/dp.h" })
  vim.api.nvim_cmd({ cmd = "FilelistUse", args = { chosen } }, {})
  assert(nav.select().file == chosen)
  vim.cmd.tabnew()
  assert(vim.t.filelist_explicit == nil, "explicit selection leaked into another tab")
  vim.api.nvim_cmd({ cmd = "FilelistUse", args = { project .. "/tree_t.f" } }, {})
  edit(sdk .. "/include/dp.h")
  assert(nav.select().root == project)
  vim.cmd.tabprevious()
  edit(sdk .. "/include/dp.h")
  assert(nav.select().file == chosen, "shared SDK lost tab-local selection")
  vim.cmd.FilelistUse()
  assert(vim.t.filelist_explicit == nil and vim.t.filelist_source == nil)
  vim.cmd.tabnext()
  vim.cmd.tabclose()

  vim.cmd.cd(vim.fn.fnameescape(project))
  edit(project .. "/src/main.c")
  local list = assert(nav.select())
  local headers = nav.headers(list, '#include "dp.h"', project .. "/src/main.c")
  assert(#headers == 1 and headers[1].file == sdk .. "/include/dp.h", vim.inspect(headers))
  assert(#nav.headers(list, "#include <wrong/dp.h>", project .. "/src/main.c") == 0)
  assert(nav.headers(list, "#include HEADER", project .. "/src/main.c") == nil)
  nav.navigate("definition")
  assert(picker.auto_confirm and #picker.items == 1 and picker.items[1].file == sdk .. "/include/dp.h")
  edit(sdk .. "/include/dp.h")
  assert(nav.select().file == list.file, "SDK lost source filelist")
  edit(project .. "/src/main.c")
  write(project .. "/include/dp.h", { "int shared(void);" })
  generate({ "src", "include", "../sdk/include" })
  nav.navigate("definition")
  assert(#picker.items == 2 and picker.title:find("清单头文件"))
  local missing = vim.fn.readfile(project .. "/tree_t.f")
  missing[#missing + 1] = "missing.h\r"
  vim.fn.writefile(missing, project .. "/tree_t.f")
  assert(#nav.select().files == #missing - 1)
  assert(notes[#notes]:find("跳过"))
  edit(project .. "/src/main.c", 2, 25)
  local original_clients = vim.lsp.get_clients
  vim.lsp.get_clients = function()
    return {}
  end
  nav.navigate("definition")
  assert(picker.finder and picker.title:find("定义候选"))

  -- Drive the actual rg batching finder through Snacks' async runtime.
  local data = vim.env.FILELIST_DATA or (vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
  vim.opt.rtp:append(data)
  local Async = require("snacks.picker.util.async")
  local output = {}
  local job = Async.new(function()
    picker.finder()(function(item)
      output[#output + 1] = item
    end)
  end)
  job:wait()
  assert(#output >= 4, vim.inspect(output))
  for _, item in ipairs(output) do
    assert(nav.select().members[item.file], "search escaped filelist")
    assert(item.file ~= project .. "/excluded.c")
  end
  assert(
    vim.tbl_contains(notes, function(message)
      return message:find("未识别到符号定义") ~= nil
    end, { predicate = true }),
    "gd without definitions must explain the text fallback"
  )
  local function matches(files, kind, language, word)
    local items, failure = {}, nil
    local task = Async.new(function()
      nav.finder({ files = files }, word or "target", kind, language)()(function(item)
        items[#items + 1] = item
      end)
    end)
    task:on("error", function(err)
      failure = err
    end)
    task:wait()
    assert(not failure, failure)
    return items
  end
  local functions = project .. "/syntax.c"
  write(functions, {
    "typedef int result_t;",
    "int target(int x);", -- return type plus semicolon is a prototype
    "int consume(void) { target(1); return target(2); }",
    "static inline int target(int x) { return target(x - 1); }", -- recursive call on the same line
    "result_t",
    "target(",
    "  int x)",
    "{",
    "  return x;",
    "}",
    "const char *",
    "target(void)",
    "{",
    '  return "text";',
    "}",
    "/* int target(void) { return 0; } */",
    'const char *text = "int target(void) { return 0; }";',
    "#define CALLBACK target",
    "void target(int (*callback)(int)) { callback(1); }",
  })
  local defs = matches({ functions }, "definition")
  assert(
    #defs == 4 and defs[1].pos[1] == 4 and defs[2].pos[1] == 6 and defs[3].pos[1] == 12 and defs[4].pos[1] == 19,
    vim.inspect(defs)
  )
  local refs, all = matches({ functions }, "references"), matches({ functions })
  assert(#all == #refs + #defs, "references must exclude only function definition names")
  assert(
    vim.tbl_contains(refs, function(item)
      return item.pos[1] == 4 and item.pos[2] > defs[1].pos[2]
    end, { predicate = true }),
    "recursive call on definition line was lost"
  )
  local cpp = project .. "/syntax.cpp"
  write(cpp, { "struct Device { int target(); };", "int Device::target() { return target(); }" })
  defs = matches({ cpp }, "definition", "cpp")
  assert(#defs == 1 and defs[1].pos[1] == 2 and defs[1].pos[2] == 12, vim.inspect(defs))
  assert(#matches({ cpp }, "references", "cpp") == 2)
  local objects = project .. "/objects.c"
  write(objects, {
    "struct Record;", -- forward declaration
    "struct Record { int value; int slots[4]; int (*hook)(int); };",
    "typedef struct Record Record_t;",
    "struct Record record;",
    "extern int count;",
    "int count, *cursor = &count;",
    "int table[4] = {1, 2};",
    "extern int table[];",
    "extern int initialized = 1;", -- initializer makes this a definition
    "int (*handler)(int), *factory(int prototype_arg);",
    "#define LIMIT 4",
    "#define APPLY(x) ((x) + LIMIT)",
    "enum Mode { IDLE, BUSY = IDLE + 1 };",
    "union Value { int number; };",
    "void use(int argument, int (*callback)(int nested_arg)) {",
    "  int local = count; count = local; table[0] = APPLY(LIMIT);",
    "  record.value = table[0]; record.slots[1] = count;",
    "  struct Record *p = &record; Record_t copy = *p;",
    "  for (int index = 0; index < LIMIT; index++) count += index;",
    "  argument = callback(local); handler(argument); record.hook(1);",
    "}",
    "// count table Record LIMIT APPLY local",
  })
  for word, rows in pairs({
    Record = { 2 },
    Record_t = { 3 },
    record = { 4 },
    value = { 2 },
    slots = { 2 },
    hook = { 2 },
    count = { 6 },
    cursor = { 6 },
    table = { 7 },
    initialized = { 9 },
    handler = { 10 },
    LIMIT = { 11 },
    APPLY = { 12 },
    Mode = { 13 },
    IDLE = { 13 },
    BUSY = { 13 },
    Value = { 14 },
    argument = { 15 },
    callback = { 15 },
    ["local"] = { 16 },
    index = { 19 },
  }) do
    local definitions = matches({ objects }, "definition", "c", word)
    local references = matches({ objects }, "references", "c", word)
    local texts = matches({ objects }, nil, "c", word)
    assert(#definitions == #rows, word .. ": " .. vim.inspect(definitions))
    for i, row in ipairs(rows) do
      assert(definitions[i].pos[1] == row, word .. ": wrong definition line")
    end
    assert(#references + #definitions == #texts, word .. ": gr lost references or retained definitions")
  end
  for _, word in ipairs({ "factory", "prototype_arg", "nested_arg" }) do
    assert(
      #matches({ objects }, "references", "c", word) == #matches({ objects }, nil, "c", word),
      word .. " is not a definition"
    )
  end
  write(cpp, {
    "class Device;",
    "class Device { public: static int count; int value; inline static int total = 0; };",
    "int Device::count = 0;",
    "using Alias = Device;",
    "void bind(int arg) { auto [left, right] = pair; int &ref = arg; ref = left + right; }",
  })
  for word, row in pairs({
    Device = 2,
    count = 3,
    value = 2,
    total = 2,
    Alias = 4,
    left = 5,
    right = 5,
    ref = 5,
    arg = 5,
  }) do
    local definitions = matches({ cpp }, "definition", "cpp", word)
    assert(#definitions == 1 and definitions[1].pos[1] == row, word .. ": " .. vim.inspect(definitions))
    assert(#matches({ cpp }, "references", "cpp", word) + 1 == #matches({ cpp }, nil, "cpp", word))
  end
  print("gd/gr: structs, members, arrays, variables, macros, typedefs, enums and declaration/use boundaries OK")
  local parse = vim.treesitter.get_string_parser
  vim.treesitter.get_string_parser = function()
    error("test: parser unavailable")
  end
  assert(#matches({ functions }, "definition") == #all, "missing parser must preserve text search")
  assert(#matches({ functions }, "references") == #all)
  vim.treesitter.get_string_parser = parse
  print("gd/gr: multiline, pointer/custom return types, prototypes, recursion, comments, C++ and parser fallback OK")
  local batches, actual_system = 0, vim.system
  local many = { files = {} }
  for i = 1, 350 do
    local file = project .. "/batch/" .. string.rep("long", 30) .. i .. ".h"
    write(file, { "shared shared_extra" })
    many.files[#many.files + 1] = file
  end
  vim.system = function(args, opts, callback)
    if args[1] == "rg" then
      batches = batches + 1
    end
    return actual_system(args, opts, callback)
  end
  output = {}
  job = Async.new(function()
    nav.finder(many, "shared")()(function(item)
      output[#output + 1] = item
    end)
  end)
  local async_error
  job:on("error", function(err)
    async_error = err
  end)
  job:wait()
  assert(not async_error, async_error)
  assert(batches > 1 and #output == #many.files, "rg batching/whole-word matching failed")
  local killed, started = false, false
  vim.system = function()
    started = true
    return {
      kill = function()
        killed = true
      end,
    }
  end
  job = Async.new(function()
    nav.finder(list, "shared")()(function()
      error("cancelled finder emitted a match")
    end)
  end)
  assert(vim.wait(1000, function()
    return started
  end))
  job:abort()
  assert(
    vim.wait(1000, function()
      return killed
    end),
    "cancelled finder left rg running"
  )
  started = false
  job = Async.new(function()
    nav.finder(list, "shared")()(function()
      error("cancelled finder emitted a match")
    end)
  end)
  job:step() -- queue the spawn on the main thread, then cancel before it runs
  job:abort()
  vim.wait(100, function()
    return false
  end)
  assert(not started, "cancelling before spawn still started rg")
  vim.system = actual_system
  write(project .. "/tree_t.f", { "", "missing.h", "\r" })
  picker = nil
  vim.cmd.FilelistGrep("shared")
  assert(picker == nil and notes[#notes]:find("清单为空"), "empty list broadened search")
  generate({ "src", "include", "../sdk/include" })
  local late, cancelled = nil, false
  local fake = {
    offset_encoding = "utf-16",
    request = function(_, _, _, cb)
      late = cb
      return true, 10
    end,
    cancel_request = function()
      cancelled = true
    end,
  }
  vim.lsp.get_clients = function()
    return { fake }
  end
  for _, reply in ipairs({ "empty", "error" }) do
    picker = nil
    nav.navigate("references")
    late(reply == "error" and { message = "test failure" } or nil, {})
    assert(picker and picker.title:find("非语义引用"), reply .. " did not fall back")
  end
  local location = {
    uri = vim.uri_from_fname(project .. "/excluded.c"),
    range = {
      start = { line = 0, character = 3 },
      ["end"] = { line = 0, character = 9 },
    },
  }
  picker, cancelled = nil, false
  nav.navigate("definition")
  local before_toggle = late
  nav.set_text_only(true)
  assert(cancelled, "toggle did not cancel pending LSP request")
  before_toggle(nil, { location })
  assert(picker == nil and vim.api.nvim_buf_get_name(0) == project .. "/src/main.c")
  local fake_clients = vim.lsp.get_clients
  vim.lsp.get_clients = function()
    error("text-only mode queried LSP")
  end
  for _, kind in ipairs({ "definition", "references" }) do
    nav.navigate(kind)
    assert(picker.finder and picker.title:find(kind == "definition" and "定义候选" or "非语义引用"))
  end
  edit(project .. "/src/main.c")
  nav.navigate("definition")
  assert(picker.title:find("清单头文件"), "toggle broke include lookup")
  local saved = vim.fn.readfile(project .. "/tree_t.f")
  write(project .. "/tree_t.f", {})
  picker = nil
  nav.navigate("definition")
  assert(picker == nil and notes[#notes]:find("清单为空"))
  vim.fn.delete(project .. "/tree_t.f")
  nav.navigate("references")
  assert(picker == nil and notes[#notes]:find("未找到 tree_t.f"), "missing list fell back to LSP")
  write(project .. "/tree_t.f", saved)
  nav.set_text_only(false)
  vim.lsp.get_clients = fake_clients
  edit(project .. "/src/main.c", 2, 25)
  nav.navigate("references")
  late(nil, { location, location })
  assert(picker.title == "LSP 语义引用" and #picker.items == 1 and not picker.finder and not picker.auto_confirm)
  picker = nil
  nav.navigate("definition")
  late(nil, {
    {
      uri = vim.uri_from_fname(project .. "/excluded.c"),
      range = {
        start = { line = 0, character = 3 },
        ["end"] = { line = 0, character = 9 },
      },
    },
  })
  assert(
    picker.auto_confirm and picker.items[1].file == project .. "/excluded.c",
    "LSP must not be limited by filelist"
  )
  edit(project .. "/src/main.c", 2, 25)
  picker = nil
  nav.navigate("references")
  assert(
    vim.wait(2500, function()
      return picker ~= nil
    end, 10),
    "timeout did not fall back"
  )
  assert(cancelled and picker.title:find("非语义引用"))
  picker, cancelled = nil, false
  nav.navigate("references")
  local obsolete = late
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  nav.navigate("definition")
  assert(cancelled and picker.title:find("清单头文件"))
  local headers_picker = picker
  obsolete(nil, { location })
  assert(picker == headers_picker, "old semantic response replaced include navigation")
  edit(project .. "/src/main.c", 2, 25)
  picker = nil
  nav.navigate("definition")
  edit(sdk .. "/include/dp.h")
  late(nil, {})
  vim.wait(2100, function()
    return false
  end)
  assert(picker == nil, "stale LSP response opened picker")
  vim.bo.filetype = "python"
  nav.navigate("definition")
  assert(picker == "normal definitions")
  nav.navigate("references")
  assert(picker == "normal references")
  vim.lsp.get_clients = original_clients
  print("navigation: include disambiguation, SDK, Ctrl-o, actual rg, LSP timeout/stale responses OK")
end
local ok, err = xpcall(test, debug.traceback)
vim.fn.delete(work, "rf")
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
