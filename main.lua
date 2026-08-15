-- #!/
-- TERRAPIA OPS - Main Launcher
-- Combines: Skinschanger (terravia_ops.lua) + Coffee Critical Ops (Coffee_Critical_Ops.lua)
-- #!/

-- Check that both scripts exist
local function fileExists(path)
 local f = io.open(path, 'rb')
 if f then f:close() return true end
 return false
end

local SKIN = '/sdcard/Download/terravia_ops.lua'
local COFFEE = '/sdcard/Download/Coffee_Critical_Ops.lua'

-- Run a script file. os.exit is intercepted so the sub-script can "exit"
-- and we return to the main menu instead of killing the launcher.
local function runScript(path, name)
 if not fileExists(path) then
  gg.alert('Script not found:\n' .. path .. '\n\nPlace it in /sdcard/Download/', 'OK')
  return
 end

 local chunk, err = loadfile(path)
 if not chunk then
  gg.alert('Failed to load ' .. name .. ':\n' .. tostring(err), 'OK')
  return
 end

 gg.toast('Starting ' .. name .. ' ...')

 local realExit = os.exit
 os.exit = function()
  error('__OS_EXIT__', 0)
 end

 local ok, res = pcall(chunk)

 os.exit = realExit

 if not ok and res ~= '__OS_EXIT__' then
  gg.alert('Error in ' .. name .. ':\n' .. tostring(res), 'OK')
 end
end

while true do
 local choice = gg.choice({
  '🎨 Skinschanger',
  '☕ Coffee Cheats',
  'EXIT',
 }, nil, 'TERRAPIA OPS\nMain Menu')

 if choice == nil or choice == 3 then
  gg.setVisible(true)
  os.exit('0xff')
 end

 if choice == 1 then
  runScript(SKIN, 'Skinschanger')
 elseif choice == 2 then
  runScript(COFFEE, 'Coffee Cheats')
 end
end
