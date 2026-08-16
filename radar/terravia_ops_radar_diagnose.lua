-- //============================================================\\
-- //  TERRAVIA-OPS RADAR · Diagnose
-- //  Prüft, ob dein Gerät die ESP-Patchstelle lesen/schreiben kann.
-- //  KEIN Patch — nur Diagnose. Zeigt dir den Status.
-- //============================================================\\

-- // Das exakte 16-Byte-Muster aus 1.80.0.f3358 (arm64)
local ORIG_HEX = '1f050031685a40f9e9179f1a09010039'

local function dwordToHexLE(v)
    local h = string.format('%08x', v)
    return h:sub(7, 8) .. h:sub(5, 6) .. h:sub(3, 4) .. h:sub(1, 2)
end

-- // libil2cpp Code-Region (Xa) finden
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

-- // Alle vorhandenen gg.REGION_*-Konstanten sammeln
local function allRegionsMask()
    local mask = 0
    for k, v in pairs(gg) do
        if type(v) == 'number' and k:match('^REGION_') then
            mask = mask + v
        end
    end
    return mask
end

-- // 16 Bytes an addr lesen (nil wenn unlesbar)
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
gg.toast('Diagnose läuft...')

local code = findCode()
if not code then
    gg.alert('❌ libil2cpp Code-Region (Xa) nicht gefunden!\n\n' ..
        'Ist Critical Ops gestartet und in GG ausgewählt?\n' ..
        'Falls ja: prüfe in GG die Prozessliste — muss "Critical Ops" sein.', 'OK')
    gg.setVisible(true)
    os.exit()
end

local stop = code['end'] or (code.start + (code.size or 0))
gg.alert('✅ Code-Region gefunden:\n\n' ..
    'Start: 0x' .. string.format('%X', code.start) .. '\n' ..
    'Ende:  0x' .. string.format('%X', stop) .. '\n' ..
    'Größe: 0x' .. string.format('%X', (stop - code.start)) .. '\n\n' ..
    'Region-Konstanten in deinem GG:\n' .. tostring(allRegionsMask()), 'OK')

-- 1) Native Suche testen
gg.toast('Teste native Suche...')
local mask = allRegionsMask()
if mask > 0 then pcall(gg.setRanges, mask) end
gg.searchNumber('h ' .. ORIG_HEX:gsub('(%x%x)', '%1 '), 0x1)
local n = gg.getResultsCount()
gg.clearResults()
gg.alert('🔍 Native Suche nach dem 16-Byte-Muster:\n\n' ..
    'Gefunden: ' .. tostring(n) .. ' Treffer\n\n' ..
    'Erwartet: mindestens 1 (das Muster existiert in 1.80.0.f3358 genau 1x).\n' ..
    'Falls 0: GG kann die Code-Region nicht durchsuchen (Regionen-Problem).', 'OK')

-- 2) Direktes Lesen an einer Stelle in der Code-Region
gg.toast('Teste direktes Lesen...')
local testAddr = code.start + 0x1000  -- eine beliebige Stelle in der Region
local hex = read16(testAddr)
gg.alert('📖 Direktes Lesen an 0x' .. string.format('%X', testAddr) .. ':\n\n' ..
    'Bytes: ' .. tostring(hex or 'UNLESBAR') .. '\n\n' ..
    'Falls "UNLESBAR": GG kann die Code-Region nicht lesen (Root/VM-Problem).\n' ..
    'Falls Bytes angezeigt werden: Lesen funktioniert!', 'OK')

-- 3) Schreib-Test an einer harmlosen Stelle? NEIN — nicht patchen in der Diagnose.
--    Stattdessen: Prüfen ob die Zieladresse (vom bekannten Muster) lesbar wäre,
--    indem wir die native Suche auswerten — das haben wir in Schritt 1 getan.

gg.alert('📋 Zusammenfassung:\n\n' ..
    'Wenn Schritt 1 ≥1 Treffer UND Schritt 2 Bytes zeigt:\n' ..
    '→ Dein Gerät kann die Stelle finden und lesen. Das Radar-Script wird funktionieren.\n\n' ..
    'Wenn Schritt 1 = 0 Treffer:\n' ..
    '→ GG-Suche blockiert. Schick mir die Diagnose-Werte.\n\n' ..
    'Wenn Schritt 2 "UNLESBAR":\n' ..
    '→ Root/GG-Problem auf dem Gerät.', 'OK')

gg.setVisible(true)
