local conjure_root = assert(os.getenv("KVIST_CONJURE_ROOT"), "KVIST_CONJURE_ROOT is required")
local port = assert(tonumber(os.getenv("KVIST_CONJURE_PORT")), "KVIST_CONJURE_PORT is required")
local source_file = assert(os.getenv("KVIST_CONJURE_SOURCE"), "KVIST_CONJURE_SOURCE is required")

vim.opt.runtimepath:prepend(conjure_root)
vim.g["conjure#filetypes"] = { "kvist" }
vim.g["conjure#filetype#kvist"] = "conjure.client.clojure.nrepl"
vim.g["conjure#log#hud#enabled"] = false
vim.g["conjure#log#treesitter"] = false
vim.g["conjure#client#clojure#nrepl#connection#port_files"] = {}
vim.g["conjure#client#clojure#nrepl#connection#auto_repl#enabled"] = false
vim.cmd.runtime("plugin/conjure.lua")
vim.cmd.edit(vim.fn.fnameescape(source_file))
vim.bo.filetype = "kvist"

local config = require("conjure.config")
assert(
  config["get-in"]({ "filetype", "kvist" }) == "conjure.client.clojure.nrepl",
  "Conjure did not select its nREPL client for the kvist filetype"
)

local action = require("conjure.client.clojure.nrepl.action")
local nrepl = require("conjure.remote.nrepl")
local server = require("conjure.client.clojure.nrepl.server")
local state = require("conjure.client.clojure.nrepl.state")

local ready = false
server.connect({
  host = "127.0.0.1",
  port = port,
  cb = function()
    ready = true
  end,
})
if not vim.wait(15000, function() return ready end, 10) then
  local pending = {}
  local pending_conn = state.get("conn")
  if pending_conn and pending_conn.state and pending_conn.state.msgs then
    for id, entry in pairs(pending_conn.state.msgs) do
      table.insert(pending, { id = id, msg = entry.msg })
    end
  end
  error("Conjure connection setup timed out: " .. vim.inspect({
    connected = pending_conn ~= nil,
    ready = pending_conn and pending_conn["ready?"],
    session = pending_conn and pending_conn.session,
    describe = pending_conn and pending_conn.describe,
    pending = pending,
  }))
end

local conn = assert(state.get("conn"), "Conjure did not retain its connection")
assert(conn["ready?"], "Conjure connection did not become ready")
assert(conn.session, "Conjure did not clone or assume an nREPL session")
assert(conn.describe.ops.interrupt, "Conjure did not discover the interrupt op")

local value
local eval_done = false
action["eval-str"]({
  code = "(+ 40 2)",
  ["on-result"] = function(result)
    value = result
  end,
  cb = function(msg)
    if msg.status and msg.status.done then
      eval_done = true
    end
  end,
})
assert(vim.wait(15000, function() return eval_done end, 10), "Conjure eval timed out")
assert(value == "42", "Conjure eval returned " .. vim.inspect(value))

local loaded_value
local load_done = false
local load_messages = {}
action["eval-file"]({
  ["file-path"] = source_file,
  ["on-result"] = function(result)
    loaded_value = result
  end,
  cb = function(msg)
    table.insert(load_messages, msg)
    if msg.status and msg.status.done then
      load_done = true
    end
  end,
})
assert(vim.wait(15000, function() return load_done end, 10), "Conjure load-file timed out")
assert(
  loaded_value == "43",
  "Conjure load-file returned " .. vim.inspect(loaded_value) .. ": " .. vim.inspect(load_messages)
)

local completion_done = false
local completion_names = {}
server.send(
  { op = "cider/complete", prefix = "pri", session = conn.session },
  nrepl["with-all-msgs-fn"](function(messages)
    for _, msg in ipairs(messages) do
      for _, item in ipairs(msg.completions or {}) do
        completion_names[item.candidate] = true
      end
    end
    completion_done = true
  end)
)
assert(vim.wait(15000, function() return completion_done end, 10), "Conjure completion timed out")
assert(completion_names.println, "Conjure completion omitted println")

local info_done = false
local info_name
server.send(
  { op = "cider/info", sym = "println", session = conn.session },
  nrepl["with-all-msgs-fn"](function(messages)
    for _, msg in ipairs(messages) do
      info_name = msg.name or info_name
    end
    info_done = true
  end)
)
assert(vim.wait(15000, function() return info_done end, 10), "Conjure info timed out")
assert(info_name == "core.println", "Conjure info returned " .. vim.inspect(info_name))

local interrupted = false
server.eval({ code = "(do (while true (discard 1)) 0)" }, function(msg)
  if msg.status and msg.status.interrupted and msg.status.done then
    interrupted = true
  end
end)
vim.defer_fn(action.interrupt, 250)
assert(vim.wait(15000, function() return interrupted end, 10), "Conjure interrupt timed out")

local recovered
local recover_done = false
local recovery_messages = {}
action["eval-str"]({
  code = "(+ 1 2)",
  ["on-result"] = function(result)
    recovered = result
  end,
  cb = function(msg)
    table.insert(recovery_messages, msg)
    if msg.status and msg.status.done then
      recover_done = true
    end
  end,
})
assert(vim.wait(15000, function() return recover_done end, 10), "Conjure recovery eval timed out")
assert(
  recovered == "3",
  "Conjure recovery eval returned " .. vim.inspect(recovered) .. ": " .. vim.inspect(recovery_messages)
)

server.disconnect()
print("conjure nrepl: ok")
