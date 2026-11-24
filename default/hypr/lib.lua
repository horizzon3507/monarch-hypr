-- Helpers shared by the Monarch Hyprland modules. Loaded once by hyprland.lua
-- and exposed as the global `monarch`.
local M = {}

M.root = os.getenv("MONARCH_PATH") or "/usr/share/monarch"

-- Run a default module shipped under default/hypr/.
function M.default(name)
  return dofile(M.root .. "/default/hypr/" .. name .. ".lua")
end

-- Load a user-owned or generated file. A missing file is fine, a broken one
-- raises a notification instead of stopping the rest of the config.
function M.optional(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  file:close()
  local ok, result = pcall(dofile, path)
  if not ok then
    hl.notification.create({ text = "Monarch: error in " .. path .. ": " .. tostring(result), timeout = 10000 })
    return nil
  end
  return result
end

-- hl.bind with a description (shown by `monarch menu keybindings`).
function M.bind(keys, action, description, opts)
  opts = opts or {}
  opts.description = description
  return hl.bind(keys, action, opts)
end

-- Bind a key to a shell command.
function M.cmd(keys, command, description, opts)
  return M.bind(keys, hl.dsp.exec_cmd(command), description, opts)
end

-- Run a command once when the session starts.
function M.autostart(command)
  hl.on("hyprland.start", function()
    hl.exec_cmd(command)
  end)
end

return M
