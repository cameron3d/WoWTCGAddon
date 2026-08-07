-- Run all WoWTCG tests. Usage (from repo root): lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local Stub = require("wow_api_stub")
Stub.install()

local T = require("testkit")

local files = {
  "test_core", "test_cards", "test_packsystem",
  "test_pointsengine", "test_chatflex", "test_slash", "test_ui_load",
}

for _, f in ipairs(files) do
  local fh = io.open("tests/" .. f .. ".lua", "r")
  if fh then
    fh:close()
    require(f)
  else
    print("skip  " .. f .. " (not written yet)")
  end
end

os.exit(T.finish())
