-- ============================================================
--  TERRAVIA-OPS RADAR DIAGNOSE
--  Checkt ob das Geraet die ESP-Stelle lesen/schreiben kann.
--  KEIN Patch - nur Diagnose.
-- ============================================================

local ORIG_HEX = '1f050031685a40f9e9179f1a09010039'

local function dwordToHexLE(v)
    local h = string.format('%08x', v)
    return h:sub(7, 8) .. h:sub(5, 6) .. h:sub(3, 4) .. h:sub(1, 2)
end

local function findCode()
    local ok, mods = pcall(gg.getRangesList)
    if not ok or type(mods) ~= 'table' then return nil end
    for _, m in ipairs(mods) do
        if m and m.start and (m.name or ''):find('libil2cpp', 1, true) and m.state == 'Xa' then
            return m
        end
    end
    return nil
end

local function allRegionsMask()
    local mask = 0
    for k, v in pairs(gg) do
        if type(v) == 'number' and k:match('^REGION_') then
            mask = mask + v
        end
    end
    return mask
end

local function read16(addr)
    local ok, res = pcall(gg.getValues, {
        { address = addr, flags = 4 },
        { address = addr + 4, flags = 4 },
        { address = addr + 8, flags = 4 },
        { address = addr + 12, flags = 4 },
    })
    if not ok or not res or #res < 4 then return nil end
    local a, b, c, d = res[1].value, res[2].value, res[3].value, res[4].value
    if a == nil or b == nil or c == nil or d == nil then return nil end
    if a == 0xffffffff or b == 0xffffffff or c == 0xffffffff or d == 0xffffffff then return nil end
    return dwordToHexLE(a) .. dwordToHexLE(b) .. dwordToHexLE(c) .. dwordToHexLE(d)
end

gg.setVisible(false)
gg.toast('Diagnose laeuft...')

local code = findCode()
if not code then
    gg.alert('FEHLER: libil2cpp Code-Region (Xa) nicht gefunden!' ..
        '\n\nIst Critical Ops gestartet und in GG ausgewaehlt?', 'OK')
    gg.setVisible(true)
    os.exit()
end

local stop = code['end'] or (code.start + (code.size or 0))
gg.alert('Code-Region gefunden:' ..
    '\nStart: 0x' .. string.format('%X', code.start) ..
    '\nEnde:  0x' .. string.format('%X', stop) ..
    '\nGroesse: 0x' .. string.format('%X', (stop - code.start)) ..
    '\n\nRegion-Konstanten in deinem GG: ' .. tostring(allRegionsMask()), 'OK')

gg.toast('Teste native Suche...')
local mask = allRegionsMask()
if mask > 0 then pcall(gg.setRanges, mask) end
gg.searchNumber('h ' .. ORIG_HEX:gsub('(%x%x)', '%1 '), 0x1)
local n = gg.getResultsCount()
gg.clearResults()
gg.alert('Native Suche nach dem 16-Byte-Muster:' ..
    '\n\nGefunden: ' .. tostring(n) .. ' Treffer' ..
    '\n\nErwartet: mindestens 1' ..
    '\n(0 = GG kann Code-Region nicht durchsuchen)', 'OK')

gg.toast('Teste direktes Lesen...')
local testAddr = code.start + 0x1000
local hex = read16(testAddr)
gg.alert('Direktes Lesen an 0x' .. string.format('%X', testAddr) .. ':' ..
    '\n\nBytes: ' .. tostring(hex or 'UNLESBAR') ..
    '\n\nUNLESBAR = GG kann Code-Region nicht lesen', 'OK')

gg.alert('Zusammenfassung:' ..
    '\n\nSuche >=1 Treffer UND Bytes lesbar:' ..
    '\n-> Geraet kann die Stelle finden. Radar-Script wird funktionieren.' ..
    '\n\nSuche 0 Treffer:' ..
    '\n-> GG-Suche blockiert.' ..
    '\n\nUNLESBAR:' ..
    '\n-> Root/GG-Problem auf dem Geraet.', 'OK')

gg.setVisible(true)
