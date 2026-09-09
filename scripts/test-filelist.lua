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
    "int target(int x);",
    "extern int target;",
    "struct target;",
    "int target(int x) { return target(x - 1); }",
    "void use(void) { target(1); target = 2; target++; }",
    "// target is mentioned in a comment",
    'const char *text = "target";',
    "#define DECLARE(name) int name",
    "DECLARE(target);",
    "#define target 42",
    "void (*target)(int);",
    "typedef int target;",
  })
  local defs = matches({ functions }, "definition")
  local rows = {}
  for _, item in ipairs(defs) do
    rows[#rows + 1] = item.pos[1]
  end
  assert(vim.deep_equal(rows, { 1, 2, 3, 4, 9, 10, 11, 12 }), vim.inspect(defs))
  local all = matches({ functions })
  assert(vim.deep_equal(matches({ functions }, "references"), all), "gr must retain all text, including definitions")
  local uncertain = project .. "/uncertain.c"
  write(uncertain, { "CUSTOM_TYPE target CUSTOM_ATTRIBUTE", "BROKEN(target" })
  local candidates = matches({ functions, uncertain }, "definition")
  assert(
    vim.tbl_contains(candidates, function(item)
      return item.file == uncertain
    end, { predicate = true }),
    "recognized definitions must not hide unknown syntax in other files"
  )
  local usage = project .. "/usage.c"
  write(usage, { "void run(void) { target(); }" })
  assert(#matches({ usage }, "definition") == 0, "gd must not reinsert rejected uses when no candidates remain")
  local cpp = project .. "/syntax.cpp"
  write(cpp, { "struct Device { static int target; int target(); };", "int Device::target() { return target(); }" })
  assert(#matches({ cpp }, "definition", "cpp") == 3)
  assert(#matches({ cpp }, "references", "cpp") == 4)
  local objects = project .. "/objects.c"
  write(objects, { "int table[4];", "void use(void) { table[0] = 1; }" })
  assert(#matches({ objects }, "definition", "c", "table") == 1)
  print("C/C++: gd keeps declarations/unknowns, removes clear uses; gr retains all candidates OK")
  local rust = project .. "/rust/model.rs"
  write(rust, {
    "pub async unsafe fn target(target: i32) -> i32 { target(); return target; }",
    "struct target { target: i32 }",
    "enum target { target }",
    "trait target { fn target(); }",
    "impl target for Other { fn target() {} }",
    "type target = i32;",
    "const target: i32 = target();",
    "static mut target: [i32; 4] = [0; 4];",
    "macro_rules! target { ($name:ident) => { fn $name() {} }; }",
    "use crate::other as target;",
    "fn uses() {",
    "    let mut target = target();",
    "    let (target, other) = pair;",
    "    for target in values {}",
    "    if let Some(target) = option {}",
    "    match option { Some(target) => {}, _ => {} }",
    "    target(); target = 2; target += 1; return target;",
    "}",
    "// target",
    "/* target */",
    'const TEXT: &str = "target";',
    'const RAW: &str = r#"target"#;',
    "build!(target);",
    "fn generated() { make!(target); }",
    "fn nested() { invoke(|| { let target = 1; }); }",
  })
  rows = {}
  for _, item in ipairs(matches({ rust }, "definition", "rust")) do
    rows[#rows + 1] = item.pos[1]
  end
  assert(
    vim.deep_equal(rows, { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 23, 24, 25 }),
    vim.inspect(rows)
  )
  local rust_all = matches({ rust }, nil, "rust")
  assert(vim.deep_equal(matches({ rust }, "references", "rust"), rust_all))
  local rust_unknown = project .. "/rust/unknown.rs"
  write(rust_unknown, { "custom target syntax", "build!(target" })
  assert(#matches({ rust, rust_unknown }, "definition", "rust") == #rows + 2, "Rust unknowns lost beside definitions")
  local rust_usage = project .. "/rust/usage.rs"
  write(rust_usage, { "fn run() { target(); target = 1; target += 1; return target; }" })
  assert(#matches({ rust_usage }, "definition", "rust") == 0, "Rust gd reinserted rejected uses")
  assert(#matches({ rust, functions }, "definition", "rust") == #rows + #defs, "mixed Rust/C parsers failed")
  write(project .. "/rust/foreign.py", { "target = 1" })
  generate({ "rust" })
  assert(vim.deep_equal(vim.fn.readfile(project .. "/tree_t.f"), {
    "rust/foreign.py",
    "rust/model.rs",
    "rust/unknown.rs",
    "rust/usage.rs",
  }))
  run({ "bash", generator, "--root", project, "--ext", "rs", "--", "rust" })
  assert(
    vim.deep_equal(vim.fn.readfile(project .. "/tree_t.f"), { "rust/model.rs", "rust/unknown.rs", "rust/usage.rs" })
  )
  print("Rust: permissive gd, unfiltered gr, types/bindings/macros, mixed parsers and rs generation OK")
  local python = project .. "/python/model.py"
  write(python, {
    "from elsewhere import Kind, value as renamed",
    "LIMIT = 4",
    "items: list[int] = []",
    "@decorator",
    "async def fetch(arg: Kind, default=LIMIT, *args, **kwargs):",
    "    local: int = arg",
    "    first, (second, *tail) = args",
    "    items[index] = local",
    "    local += 1",
    "    if (count := len(items)):",
    "        return count",
    "    for key, val in pairs:",
    "        pass",
    "    with open(path) as stream:",
    "        pass",
    "    try: pass",
    "    except Error as exc: pass",
    "class Device:",
    "    field: int",
    "    def method(self, typed: Kind=LIMIT):",
    "        self.field = typed",
    "        return self.field",
    "items = [entry for entry in source]",
    "callback = lambda param: param + LIMIT",
    "print(fetch, Device, renamed, items, local, first, field)",
    "# fetch Device LIMIT items",
    'text = "class Device: def fetch(): LIMIT = items"',
  })
  for word, rows in pairs({
    fetch = { 5 },
    Device = { 18 },
    LIMIT = { 2 },
    items = { 3, 23 },
    arg = { 5 },
    default = { 5 },
    args = { 5 },
    kwargs = { 5 },
    ["local"] = { 6 },
    first = { 7 },
    second = { 7 },
    tail = { 7 },
    count = { 10 },
    key = { 12 },
    val = { 12 },
    stream = { 14 },
    exc = { 17 },
    field = { 19, 21 },
    method = { 20 },
    self = { 20 },
    typed = { 20 },
    entry = { 23 },
    param = { 24 },
    renamed = { 1 },
  }) do
    local definitions = matches({ python }, "definition", "python", word)
    assert(#definitions == #rows, word .. ": " .. vim.inspect(definitions))
    for i, row in ipairs(rows) do
      assert(definitions[i].file == python and definitions[i].pos[1] == row, word .. ": wrong Python binding")
    end
    assert(
      #matches({ python }, "references", "python", word) + #definitions == #matches({ python }, nil, "python", word)
    )
  end
  for _, word in ipairs({ "Kind", "index", "decorator" }) do
    assert(#matches({ python }, "references", "python", word) == #matches({ python }, nil, "python", word))
  end
  -- Mixed lists select each file's parser, regardless of the source buffer.
  assert(#matches({ python, objects }, "definition", "c", "fetch") == 1)
  assert(#matches({ python, objects }, "definition", "python", "table") == 1)
  write(project .. "/python/api.pyi", { "def stub(arg: int) -> int: ..." })
  generate({ "python" })
  assert(vim.deep_equal(vim.fn.readfile(project .. "/tree_t.f"), { "python/api.pyi", "python/model.py" }))
  assert(#matches({ project .. "/python/api.pyi" }, "definition", "python", "stub") == 1)
  run({ "bash", generator, "--root", project, "--ext", "py", "--", "python" })
  assert(vim.deep_equal(vim.fn.readfile(project .. "/tree_t.f"), { "python/model.py" }))
  generate({ "src", "include", "../sdk/include" })
  print("Python: definitions/bindings, reads/updates, mixed parsers and py/pyi generation OK")
  local parse = vim.treesitter.get_string_parser
  local parses = 0
  vim.treesitter.get_string_parser = function()
    parses = parses + 1
    error("test: parser unavailable")
  end
  assert(#matches({ functions }, "definition") == #all, "missing parser must preserve text search")
  assert(#matches({ rust }, "definition", "rust") == #rust_all, "Rust parser failure lost candidates")
  parses = 0
  assert(#matches({ functions }, "references") == #all)
  assert(#matches({ rust }, "references", "rust") == #rust_all)
  assert(parses == 0, "C/C++/Rust gr must not parse or classify definitions")
  vim.treesitter.get_string_parser = parse
  print("navigation: parser failure preserves all candidates OK")
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
  edit(rust)
  vim.bo.filetype = "rust"
  local headers = nav.headers
  nav.headers = function()
    error("Rust navigation attempted C include lookup")
  end
  for _, kind in ipairs({ "definition", "references" }) do
    nav.navigate(kind)
    assert(picker.finder and picker.title:find(kind == "definition" and "定义候选" or "全部文本"))
  end
  nav.headers = headers
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
  vim.bo.filetype = "verilog"
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
